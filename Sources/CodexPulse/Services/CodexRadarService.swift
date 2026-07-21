import Combine
import Foundation

@MainActor
final class CodexRadarService: ObservableObject {
    nonisolated static let defaultEndpoint = URL(string: "https://api.codexradar.com/api/v1/table")!
    nonisolated static let defaultRefreshInterval: TimeInterval = 60

    @Published private(set) var snapshot: RadarSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    let endpoint: URL
    let refreshInterval: TimeInterval

    var isLoading: Bool { isRefreshing }
    var lastSuccessfulRefreshAt: Date? { snapshot?.fetchedAt }

    private let session: URLSession
    private var lastRefreshAttemptAt: Date?
    private var autoRefreshTask: Task<Void, Never>?

    init(
        endpoint: URL = CodexRadarService.defaultEndpoint,
        session: URLSession? = nil,
        refreshInterval: TimeInterval = CodexRadarService.defaultRefreshInterval
    ) {
        self.endpoint = endpoint
        self.refreshInterval = max(1, refreshInterval)
        self.session = session ?? Self.makeUncachedSession()
    }

    deinit {
        autoRefreshTask?.cancel()
    }

    /// Starts a single in-memory polling loop. Calling this repeatedly is safe.
    func startAutoRefresh(immediately: Bool = true) {
        guard autoRefreshTask == nil else { return }

        autoRefreshTask = Task { [weak self] in
            if immediately {
                _ = await self?.refresh(force: true)
            }

            while !Task.isCancelled {
                guard let self else { return }
                let nanoseconds = UInt64(self.refreshInterval * 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                _ = await self.refresh(force: true)
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    /// Fetches and aggregates the table unless a non-forced request was made
    /// within the refresh interval. Failures leave the last good snapshot intact.
    @discardableResult
    func refresh(force: Bool = false) async -> RadarSnapshot? {
        let now = Date()
        if !force,
           let lastRefreshAttemptAt,
           now.timeIntervalSince(lastRefreshAttemptAt) < refreshInterval {
            return snapshot
        }
        if isRefreshing { return snapshot }

        lastRefreshAttemptAt = now
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            var request = URLRequest(
                url: endpoint,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 30
            )
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw CodexRadarError.invalidResponse
            }
            guard (200..<300).contains(response.statusCode) else {
                throw CodexRadarError.httpStatus(response.statusCode)
            }

            let decoded = try Self.decodeSnapshot(
                from: data,
                fetchedAt: Date(),
                sourceURL: endpoint
            )
            snapshot = decoded
            lastError = nil
            return decoded
        } catch is CancellationError {
            return snapshot
        } catch {
            lastError = Self.errorMessage(for: error)
            return snapshot
        }
    }

    /// Pure decode + aggregate entry point, kept separate for deterministic tests
    /// and previews. The returned value contains no contributor identity fields.
    nonisolated static func decodeSnapshot(
        from data: Data,
        fetchedAt: Date = Date(),
        sourceURL: URL = CodexRadarService.defaultEndpoint
    ) throws -> RadarSnapshot {
        let payload = try JSONDecoder().decode(RadarTablePayload.self, from: data)
        return aggregate(payload, fetchedAt: fetchedAt, sourceURL: sourceURL)
    }

    private nonisolated static func aggregate(
        _ payload: RadarTablePayload,
        fetchedAt: Date,
        sourceURL: URL
    ) -> RadarSnapshot {
        let taskIDs = uniqueNonempty(payload.tasks.compactMap(\.id))

        var comboKeys = Set<String>()
        let combos: [(model: String, effort: RadarEffort)] = payload.combos.compactMap { combo in
            guard let model = combo.model?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !model.isEmpty,
                  let effort = combo.effort,
                  !effort.rawValue.isEmpty else {
                return nil
            }
            let key = "\(model)|\(effort.rawValue)"
            guard comboKeys.insert(key).inserted else { return nil }
            return (model, effort)
        }

        var unrankedRows: [ModelIntelligence] = []
        unrankedRows.reserveCapacity(combos.count)

        for combo in combos {
            var livePasses = 0
            var liveSamples = 0
            var recentPasses = 0
            var recentSamples = 0
            var longTermPasses = 0
            var longTermSamples = 0
            var coveredTasks = 0
            var durationTotal = 0.0
            var durationSamples = 0
            var costTotal = 0.0
            var costSamples = 0
            var reportedCostSamples = 0
            var tokenCostSamples = 0
            var unverifiedCostSamples = 0

            for taskID in taskIDs {
                let cellKey = "\(taskID)|\(combo.model)|\(combo.effort.rawValue)"
                guard let cell = payload.cells[cellKey] else { continue }

                var hasScoredSample = false

                // The API orders ran_by newest first. Do not fall back to an older
                // runner when the latest entry is incomplete: that would make the
                // live score stale without saying so.
                if let latestRunner = cell.runners.first,
                   let passed = latestRunner.passed {
                    liveSamples += 1
                    livePasses += passed ? 1 : 0
                    hasScoredSample = true
                }

                if let samples = cell.recentSampleCount,
                   let passes = cell.recentPassCount,
                   samples > 0,
                   passes >= 0,
                   passes <= samples {
                    recentSamples += samples
                    recentPasses += passes
                    hasScoredSample = true
                }

                if let samples = cell.totalSampleCount,
                   let passes = cell.totalPassCount,
                   samples > 0,
                   passes >= 0,
                   passes <= samples {
                    longTermSamples += samples
                    longTermPasses += passes
                    hasScoredSample = true
                }

                if hasScoredSample { coveredTasks += 1 }

                for runner in cell.runners {
                    if let duration = runner.durationSeconds,
                       duration.isFinite,
                       duration > 0 {
                        durationTotal += duration
                        durationSamples += 1
                    }

                    if let cost = runner.actualCostUSD,
                       cost.isFinite,
                       cost >= 0 {
                        costTotal += cost
                        costSamples += 1
                        switch runner.costSource {
                        case .reported?: reportedCostSamples += 1
                        case .tokens?: tokenCostSamples += 1
                        case .unknown?, nil: unverifiedCostSamples += 1
                        }
                    }
                }
            }

            let quality: RadarCostQuality
            if costSamples == 0 {
                quality = .unavailable
            } else if unverifiedCostSamples > 0 {
                quality = .unverified
            } else if reportedCostSamples == costSamples {
                quality = .reported
            } else if tokenCostSamples == costSamples {
                quality = .estimated
            } else {
                quality = .mixed
            }

            unrankedRows.append(
                ModelIntelligence(
                    rank: 0,
                    model: combo.model,
                    effort: combo.effort,
                    liveIQ: iq(passCount: livePasses, sampleCount: liveSamples),
                    recentIQ: iq(passCount: recentPasses, sampleCount: recentSamples),
                    longTermIQ: iq(passCount: longTermPasses, sampleCount: longTermSamples),
                    coverage: taskIDs.isEmpty ? 0 : Double(coveredTasks) / Double(taskIDs.count),
                    coveredTaskCount: coveredTasks,
                    taskCount: taskIDs.count,
                    liveSampleCount: liveSamples,
                    recentSampleCount: recentSamples,
                    longTermSampleCount: longTermSamples,
                    meanRecentDurationSeconds: durationSamples > 0 ? durationTotal / Double(durationSamples) : nil,
                    durationSampleCount: durationSamples,
                    meanRecentCostUSD: costSamples > 0 ? costTotal / Double(costSamples) : nil,
                    costSampleCount: costSamples,
                    reportedCostSampleCount: reportedCostSamples,
                    costQuality: quality
                )
            )
        }

        unrankedRows.sort(by: ranksBefore)
        let rows = unrankedRows.enumerated().map { offset, row in
            ModelIntelligence(
                rank: offset + 1,
                model: row.model,
                effort: row.effort,
                liveIQ: row.liveIQ,
                recentIQ: row.recentIQ,
                longTermIQ: row.longTermIQ,
                coverage: row.coverage,
                coveredTaskCount: row.coveredTaskCount,
                taskCount: row.taskCount,
                liveSampleCount: row.liveSampleCount,
                recentSampleCount: row.recentSampleCount,
                longTermSampleCount: row.longTermSampleCount,
                meanRecentDurationSeconds: row.meanRecentDurationSeconds,
                durationSampleCount: row.durationSampleCount,
                meanRecentCostUSD: row.meanRecentCostUSD,
                costSampleCount: row.costSampleCount,
                reportedCostSampleCount: row.reportedCostSampleCount,
                costQuality: row.costQuality
            )
        }

        let metadata = RadarMetadata(
            schema: payload.schema,
            fetchedAt: fetchedAt,
            sourceURL: sourceURL,
            baselineGeneratedAt: payload.baselineGeneratedAt,
            discriminationGeneratedAt: payload.discriminationGeneratedAt,
            discriminationMethod: payload.discriminationMethod,
            reopenAfterHours: finiteNonnegative(payload.reopenAfterHours),
            onlineVolunteers: max(0, payload.onlineVolunteers ?? 0),
            k: finiteNonnegative(payload.k),
            tierWindowsUSD: payload.tierWindowsUSD.filter { $0.value.isFinite && $0.value >= 0 },
            taskCount: taskIDs.count,
            comboCount: combos.count,
            cellCount: payload.cells.count
        )
        return RadarSnapshot(metadata: metadata, rows: rows)
    }

    private nonisolated static func uniqueNonempty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }

    private nonisolated static func iq(passCount: Int, sampleCount: Int) -> Double? {
        guard sampleCount > 0, passCount >= 0, passCount <= sampleCount else { return nil }
        return Double(passCount) / Double(sampleCount) * 150
    }

    private nonisolated static func finiteNonnegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private nonisolated static func ranksBefore(_ lhs: ModelIntelligence, _ rhs: ModelIntelligence) -> Bool {
        for pair in [(lhs.liveIQ, rhs.liveIQ), (lhs.recentIQ, rhs.recentIQ), (lhs.longTermIQ, rhs.longTermIQ)] {
            switch pair {
            case let (left?, right?) where left != right:
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                continue
            }
        }

        if lhs.coverage != rhs.coverage { return lhs.coverage > rhs.coverage }
        if lhs.model != rhs.model { return lhs.model.localizedStandardCompare(rhs.model) == .orderedAscending }
        return lhs.effort.sortOrder < rhs.effort.sortOrder
    }

    private nonisolated static func makeUncachedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        configuration.httpAdditionalHeaders = ["Cache-Control": "no-cache"]
        return URLSession(configuration: configuration)
    }

    private nonisolated static func errorMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

private enum CodexRadarError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "CodexRadar 返回了无法识别的响应"
        case let .httpStatus(status):
            "CodexRadar 请求失败（HTTP \(status)）"
        }
    }
}
