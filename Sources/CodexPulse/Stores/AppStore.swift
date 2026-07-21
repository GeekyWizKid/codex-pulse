import Combine
import Foundation
import OSLog

@MainActor
final class AppStore: ObservableObject {
    @Published var usage = DashboardUsage()
    @Published var status: LoadStatus = .idle
    @Published var radarStatus: LoadStatus = .idle
    @Published var accountStatus: LoadStatus = .idle
    @Published var range: DashboardRange = .today {
        didSet { rebuildPresentation() }
    }

    private let logger = Logger(subsystem: "com.codexpulse.monitor", category: "Sync")
    private let localScanner: LocalCodexScanner
    private let radarService: CodexRadarService
    private let accountClient: CodexAppServerClient
    private var cancellables = Set<AnyCancellable>()
    private var localMonitorTask: Task<Void, Never>?
    private var started = false

    private var localSnapshot: LocalUsageSnapshot?
    private var radarSnapshot: RadarSnapshot?
    private var accountSnapshot = AccountUsageSnapshot.empty

    init(
        localScanner: LocalCodexScanner = LocalCodexScanner(),
        radarService: CodexRadarService? = nil,
        accountClient: CodexAppServerClient? = nil
    ) {
        self.localScanner = localScanner
        self.radarService = radarService ?? CodexRadarService()
        self.accountClient = accountClient ?? CodexAppServerClient()
        bindServices()
    }

    var displayQuotas: [DashboardQuota] {
        let limits = accountSnapshot.rateLimits
        return [limits?.primary, limits?.secondary]
            .enumerated()
            .compactMap { index, window in
                guard let window else { return nil }
                let minutes = window.windowDurationMins
                return DashboardQuota(
                    id: index == 0 ? "primary" : "secondary",
                    title: Self.quotaTitle(minutes: minutes, fallbackIndex: index),
                    usedPercent: window.usedPercent,
                    windowMinutes: minutes,
                    resetAt: window.resetsAt
                )
            }
    }

    var forecastTokens: Int? {
        guard range == .today, usage.tokens > 0 else { return nil }
        let forecastEnabled = UserDefaults.standard.object(forKey: "enableForecast") as? Bool ?? true
        guard forecastEnabled else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let elapsed = max(Date().timeIntervalSince(start), 60)
        // Very early extrapolations overwhelm the chart and are not decision
        // quality. Wait for three hours of observed activity before projecting.
        guard elapsed >= 3 * 3_600 else { return nil }
        let day = max(calendar.date(byAdding: .day, value: 1, to: start)?.timeIntervalSince(start) ?? 86_400, 1)
        let forecast = Double(usage.tokens) * day / elapsed
        guard forecast.isFinite else { return nil }
        return Int(min(forecast, Double(Int.max)))
    }

    var comparisonText: String {
        guard let localSnapshot else { return "等待本地数据" }
        let previous = tokenTotal(inPreviousRangeOf: localSnapshot)
        guard previous > 0 else { return "首次建立对比基线" }
        let delta = (Double(usage.tokens) - Double(previous)) / Double(previous)
        let direction = delta >= 0 ? "+" : ""
        let label = range == .today ? "昨天" : "上一周期"
        return "较\(label) \(direction)\(delta.formatted(.percent.precision(.fractionLength(1))))"
    }

    var averageSessionDuration: TimeInterval {
        guard usage.sessions > 0 else { return 0 }
        return usage.activeDuration / Double(usage.sessions)
    }

    var dailyUsage: [DailyUsagePoint] {
        guard let localSnapshot else { return [] }
        return localSnapshot.dailyUsage
            .filter { $0.date >= range.startDate && $0.date <= Date() }
            .map {
                DailyUsagePoint(
                    date: $0.date,
                    tokens: Self.clampedInt($0.tokens.total),
                    activeDuration: $0.actualTaskDuration
                )
            }
            .sorted { $0.date < $1.date }
    }

    var hourlyTokens: [Int] {
        guard let localSnapshot else { return Array(repeating: 0, count: 24) }
        var values = Array(repeating: 0, count: 24)
        let calendar = Calendar.current
        for bucket in localSnapshot.hourlyUsage where bucket.date >= range.startDate && bucket.date <= Date() {
            let hour = calendar.component(.hour, from: bucket.date)
            values[hour] = Self.saturatedAdd(values[hour], Self.clampedInt(bucket.tokens.total))
        }
        return values
    }

    var peakHourLabel: String {
        guard let peak = hourlyTokens.enumerated().max(by: { $0.element < $1.element }), peak.element > 0 else {
            return "暂无"
        }
        return String(format: "%02d:00–%02d:00", peak.offset, (peak.offset + 1) % 24)
    }

    var longestProjectLabel: String {
        usage.projects.max(by: { $0.activeDuration < $1.activeDuration })?.name ?? "暂无"
    }

    var radarMetadata: String {
        guard let metadata = radarSnapshot?.metadata else { return "等待 CodexRadar" }
        return "\(metadata.taskCount) 项任务 · \(metadata.comboCount) 个组合 · \(metadata.onlineVolunteers) 位在线志愿者"
    }

    var menuBarTitle: String {
        guard UserDefaults.standard.object(forKey: "showMenuBarPercentage") as? Bool ?? true,
              let remaining = displayQuotas.first?.remainingPercent else {
            return "Codex Pulse"
        }
        return "Codex \(Int(remaining.rounded()))%"
    }

    func startMonitoringIfNeeded() async {
        guard !started else { return }
        started = true
        logger.info("Monitoring started")

        await refreshAll(force: true)
        radarService.startAutoRefresh(immediately: false)
        accountClient.startMonitoring(refreshInterval: 60)
        startLocalMonitor()
    }

    func refreshAll(force: Bool = false) async {
        async let local: Void = refreshLocal()
        async let radar: Void = refreshRadar(force: force)
        async let account: Void = refreshAccount()
        _ = await (local, radar, account)
    }

    private func bindServices() {
        radarService.$snapshot
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.radarSnapshot = snapshot
                if let snapshot {
                    self.radarStatus = .ready(snapshot.fetchedAt)
                }
                self.rebuildPresentation()
            }
            .store(in: &cancellables)

        radarService.$lastError
            .compactMap { $0 }
            .sink { [weak self] message in
                guard let self else { return }
                self.radarStatus = .degraded(message, self.radarSnapshot?.fetchedAt)
            }
            .store(in: &cancellables)

        accountClient.$snapshot
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.accountSnapshot = snapshot
                if let date = snapshot.lastUpdatedAt {
                    self.accountStatus = .ready(date)
                }
                self.rebuildPresentation()
            }
            .store(in: &cancellables)

        accountClient.$lastError
            .compactMap { $0 }
            .sink { [weak self] error in
                guard let self else { return }
                self.accountStatus = .degraded(error.localizedDescription, self.accountSnapshot.lastUpdatedAt)
            }
            .store(in: &cancellables)
    }

    private func refreshLocal() async {
        if localSnapshot == nil {
            status = .loading("正在读取本地 Codex 数据")
        }
        do {
            let snapshot = try await localScanner.scan { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, self.localSnapshot == nil else { return }
                    self.status = .loading(Self.progressLabel(progress))
                }
            }
            localSnapshot = snapshot
            status = .ready(snapshot.scannedAt)
            rebuildPresentation()
            logger.info("Local scan finished: \(snapshot.threads.count, privacy: .public) threads")
        } catch is CancellationError {
            return
        } catch {
            status = .degraded(error.localizedDescription, localSnapshot?.scannedAt)
            logger.error("Local scan failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshRadar(force: Bool) async {
        if radarSnapshot == nil { radarStatus = .loading("正在获取公共榜单") }
        let result = await radarService.refresh(force: force)
        if let result {
            radarSnapshot = result
            radarStatus = .ready(result.fetchedAt)
            rebuildPresentation()
        } else if let error = radarService.lastError {
            radarStatus = .degraded(error, radarSnapshot?.fetchedAt)
        }
    }

    private func refreshAccount() async {
        if accountSnapshot.lastUpdatedAt == nil { accountStatus = .loading("正在连接 Codex") }
        do {
            let snapshot = try await accountClient.refresh()
            accountSnapshot = snapshot
            accountStatus = .ready(snapshot.lastUpdatedAt ?? Date())
            rebuildPresentation()
        } catch {
            accountStatus = .degraded(error.localizedDescription, accountSnapshot.lastUpdatedAt)
            logger.error("Account usage refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startLocalMonitor() {
        localMonitorTask?.cancel()
        localMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = max(5, UserDefaults.standard.double(forKey: "localRefreshInterval"))
                let actualInterval = interval == 5 && UserDefaults.standard.object(forKey: "localRefreshInterval") == nil ? 10 : interval
                try? await Task.sleep(nanoseconds: UInt64(actualInterval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                await self.refreshLocal()
            }
        }
    }

    private func rebuildPresentation() {
        var next = DashboardUsage()
        next.generatedAt = localSnapshot?.scannedAt
        next.dataSourceLabel = localSnapshot.map {
            "\($0.stateDatabaseName) + 增量 JSONL"
        } ?? "本地 Codex 日志"

        if let snapshot = localSnapshot {
            let temporal = filteredTemporalUsage(snapshot)
            next.tokens = Self.clampedInt(temporal.tokens.total)
            next.inputTokens = Self.clampedInt(temporal.tokens.input)
            next.cachedTokens = Self.clampedInt(temporal.tokens.cachedInput)
            next.outputTokens = Self.clampedInt(temporal.tokens.output)
            next.reasoningTokens = Self.clampedInt(temporal.tokens.reasoning)
            next.activeDuration = temporal.duration

            let filteredSessions = snapshot.threads.flatMap(\.sessions).filter { session in
                guard let date = session.lastEventAt ?? session.startedAt else { return false }
                return date >= range.startDate && date <= Date()
            }
            next.sessions = filteredSessions.count
            next.activeSessions = snapshot.currentActivity.activeThreadCount
            next.projects = makeProjects(from: snapshot, sessions: filteredSessions)
            next.chartPoints = makeChartPoints(from: snapshot)
        }

        if let summary = accountSnapshot.summary {
            next.lifetimeTokens = summary.lifetimeTokens.map(Self.clampedInt)
            next.currentStreakDays = summary.currentStreakDays.map(Self.clampedInt)
        }

        if let radarSnapshot {
            next.models = radarSnapshot.rows.map { row in
                DashboardModel(
                    model: row.model,
                    effort: row.effort.rawValue,
                    liveIQ: row.liveIQ ?? 0,
                    recentIQ: row.recentIQ ?? 0,
                    longTermIQ: row.longTermIQ ?? 0,
                    coverage: row.coverage,
                    samples: row.recentSampleCount,
                    meanDuration: row.meanRecentDurationSeconds,
                    meanCost: row.meanRecentCostUSD
                )
            }
        }

        next.quotas = displayQuotas
        usage = next
    }

    private func filteredTemporalUsage(_ snapshot: LocalUsageSnapshot) -> (tokens: LocalTokenUsage, duration: TimeInterval) {
        let buckets: [(LocalTokenUsage, TimeInterval)]
        if range == .today {
            buckets = snapshot.hourlyUsage
                .filter { $0.date >= range.startDate && $0.date <= Date() }
                .map { ($0.tokens, $0.actualTaskDuration) }
        } else {
            buckets = snapshot.dailyUsage
                .filter { $0.date >= range.startDate && $0.date <= Date() }
                .map { ($0.tokens, $0.actualTaskDuration) }
        }
        return buckets.reduce(into: (LocalTokenUsage(), 0.0)) { result, bucket in
            result.0 = result.0 + bucket.0
            result.1 += bucket.1
        }
    }

    private func makeProjects(
        from snapshot: LocalUsageSnapshot,
        sessions: [LocalSessionUsageSummary]
    ) -> [DashboardProject] {
        struct Accumulator {
            var sessions = 0
            var duration: TimeInterval = 0
            var tokens = LocalTokenUsage()
            var isActive = false
            var lastActive: Date?
            var models = Set<String>()
        }

        let threadsByID = Dictionary(uniqueKeysWithValues: snapshot.threads.map { ($0.id, $0) })
        var grouped: [String: Accumulator] = [:]

        for session in sessions {
            var value = grouped[session.projectName, default: Accumulator()]
            value.sessions += 1
            value.duration += session.actualTaskDuration
            value.tokens = value.tokens + session.tokens
            value.isActive = value.isActive || session.isActive
            value.lastActive = Self.later(value.lastActive, session.lastEventAt)
            if let model = threadsByID[session.threadID]?.model { value.models.insert(model) }
            grouped[session.projectName] = value
        }

        // A newly created thread may be visible in SQLite before its rollout has
        // a complete session event. Keep it visible without inventing tokens.
        for thread in snapshot.threads where thread.updatedAt >= range.startDate && thread.updatedAt <= Date() {
            if grouped[thread.projectName] == nil {
                var value = Accumulator()
                value.isActive = thread.isActive
                value.lastActive = thread.updatedAt
                if let model = thread.model { value.models.insert(model) }
                grouped[thread.projectName] = value
            }
        }

        let projectTokenTotal = max(grouped.values.reduce(Int64(0)) { partial, value in
            Self.saturatedAdd(partial, value.tokens.total)
        }, 1)

        return grouped.map { name, value in
            DashboardProject(
                id: name,
                name: name,
                activeDuration: value.duration,
                sessions: value.sessions,
                tokens: Self.clampedInt(value.tokens.total),
                inputTokens: Self.clampedInt(value.tokens.input),
                cachedTokens: Self.clampedInt(value.tokens.cachedInput),
                outputTokens: Self.clampedInt(value.tokens.output),
                reasoningTokens: Self.clampedInt(value.tokens.reasoning),
                share: Double(value.tokens.total) / Double(projectTokenTotal),
                isActive: value.isActive,
                lastActiveAt: value.lastActive,
                models: value.models.sorted()
            )
        }
        .sorted {
            if $0.tokens != $1.tokens { return $0.tokens > $1.tokens }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func makeChartPoints(from snapshot: LocalUsageSnapshot) -> [UsageChartPoint] {
        let now = Date()
        let source: [(Date, Int64)]
        if range == .today {
            source = snapshot.hourlyUsage
                .filter { $0.date >= range.startDate && $0.date <= now }
                .map { ($0.date, $0.tokens.total) }
        } else {
            source = snapshot.dailyUsage
                .filter { $0.date >= range.startDate && $0.date <= now }
                .map { ($0.date, $0.tokens.total) }
        }

        var cumulative = 0
        var points = [UsageChartPoint(date: range.startDate, tokens: 0, kind: .actual)]
        for item in source.sorted(by: { $0.0 < $1.0 }) {
            cumulative = Self.saturatedAdd(cumulative, Self.clampedInt(item.1))
            let pointDate = range == .today
                ? Calendar.current.date(byAdding: .hour, value: 1, to: item.0) ?? item.0
                : item.0
            points.append(UsageChartPoint(date: min(pointDate, now), tokens: cumulative, kind: .actual))
        }

        if range == .today, cumulative > 0, let forecastTokens {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: range.startDate) ?? now
            points.append(UsageChartPoint(date: now, tokens: cumulative, kind: .forecast))
            points.append(UsageChartPoint(date: tomorrow, tokens: forecastTokens, kind: .forecast))
        }
        return points
    }

    private func tokenTotal(inPreviousRangeOf snapshot: LocalUsageSnapshot) -> Int {
        let start = range.startDate
        let duration: TimeInterval
        switch range {
        case .today: duration = 86_400
        case .sevenDays: duration = 7 * 86_400
        case .thirtyDays: duration = 30 * 86_400
        }
        let previousStart = start.addingTimeInterval(-duration)
        let total = snapshot.hourlyUsage
            .filter { $0.date >= previousStart && $0.date < start }
            .reduce(Int64(0)) { Self.saturatedAdd($0, $1.tokens.total) }
        return Self.clampedInt(total)
    }

    private static func quotaTitle(minutes: Int?, fallbackIndex: Int) -> String {
        guard let minutes, minutes > 0 else {
            return fallbackIndex == 0 ? "主要滚动额度" : "次要滚动额度"
        }
        if minutes % 10_080 == 0 { return "\(minutes / 10_080 * 7) 天滚动额度" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440) 天滚动额度" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时滚动额度" }
        return "\(minutes) 分钟滚动额度"
    }

    private static func progressLabel(_ progress: LocalScanProgress) -> String {
        switch progress.phase {
        case .locatingDatabase: "正在定位 Codex 数据"
        case .readingThreads: "正在读取会话索引"
        case .scanningRollouts:
            progress.total > 0 ? "正在分析 \(progress.completed)/\(progress.total)" : "正在分析会话"
        case .aggregating: "正在汇总项目"
        case .finished: "正在完成"
        }
    }

    private static func later(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (left?, right?): max(left, right)
        case let (left?, nil): left
        case let (nil, right?): right
        case (nil, nil): nil
        }
    }

    private static func clampedInt(_ value: Int64) -> Int {
        if value > Int64(Int.max) { return Int.max }
        if value < 0 { return 0 }
        return Int(value)
    }

    private static func clampedInt(_ value: UInt64) -> Int {
        value > UInt64(Int.max) ? Int.max : Int(value)
    }

    private static func saturatedAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : result
    }

    private static func saturatedAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : result
    }
}
