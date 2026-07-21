import SwiftUI

struct OverviewView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                GeometryReader { geometry in
                    let quotaWidth = min(350, max(300, geometry.size.width * 0.29))
                    let chartWidth = max(0, geometry.size.width - quotaWidth - 12)

                    HStack(alignment: .top, spacing: 12) {
                        UsageChartView(
                            title: chartTitle,
                            points: store.usage.chartPoints,
                            totalTokens: store.usage.tokens,
                            forecastTokens: store.forecastTokens,
                            comparisonText: store.comparisonText
                        )
                        .frame(width: chartWidth, height: 440)

                        quotaColumn
                            .frame(width: quotaWidth)
                    }
                }
                .frame(height: 440)

                GeometryReader { geometry in
                    let rankingWidth = min(420, max(340, geometry.size.width * 0.36))
                    let projectWidth = max(0, geometry.size.width - rankingWidth - 12)

                    HStack(alignment: .top, spacing: 12) {
                        ProjectUsagePanel(projects: store.usage.projects, totalTokens: store.usage.tokens)
                            .frame(width: projectWidth)
                        ModelRankingPanel(models: store.usage.models, sourceStatus: store.radarStatus.conciseLabel)
                            .frame(width: rankingWidth)
                    }
                }
                .frame(height: 405)

                footer
            }
            .padding(22)
        }
        .accessibilityIdentifier("overview.scroll")
    }

    private var chartTitle: String {
        switch store.range {
        case .today: "今日累计 Token 使用量"
        case .sevenDays: "近 7 天累计 Token 使用量"
        case .thirtyDays: "近 30 天累计 Token 使用量"
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Text("总览")
                .font(.system(size: 30, weight: .bold))
            LiveStatusLabel(
                isLive: !store.status.isLoading,
                title: store.status.conciseLabel
            )

            Spacer()

            Picker("时间范围", selection: $store.range) {
                ForEach(DashboardRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .accessibilityIdentifier("overview.range")

            Button {
                Task { await store.refreshAll(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("r", modifiers: .command)
            .disabled(store.status.isLoading)
            .help("立即刷新（⌘R）")
            .accessibilityIdentifier("overview.refresh")

            Text(Date.now, format: .dateTime.year().month().day().weekday(.abbreviated))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var quotaColumn: some View {
        VStack(spacing: 12) {
            ForEach(store.displayQuotas.prefix(2)) { quota in
                QuotaRingView(
                    title: quota.title,
                    usedPercent: quota.usedPercent,
                    resetDate: quota.resetAt,
                    detail: quota.remainingPercent.map { "剩余 \(Int($0.rounded()))%" } ?? "官方额度暂不可用",
                    accent: quota.id == store.displayQuotas.first?.id ? PulseTheme.mint : PulseTheme.amber
                )
            }

            if store.displayQuotas.count == 1 {
                AccountSummaryPanel(
                    lifetimeTokens: store.usage.lifetimeTokens,
                    streakDays: store.usage.currentStreakDays,
                    activeSessions: store.usage.activeSessions,
                    accountStatus: store.accountStatus.conciseLabel
                )
            }

            if store.displayQuotas.isEmpty {
                QuotaRingView(
                    title: "Codex 额度",
                    usedPercent: nil,
                    resetDate: nil,
                    detail: "正在连接本地 Codex 服务",
                    accent: PulseTheme.mint
                )
                QuotaRingView(
                    title: "长期额度",
                    usedPercent: nil,
                    resetDate: nil,
                    detail: "历史日志不会冒充实时额度",
                    accent: PulseTheme.amber
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Label(store.usage.dataSourceLabel, systemImage: "externaldrive")
            Spacer()
            if let generatedAt = store.usage.generatedAt {
                Text("最后更新：\(generatedAt.formatted(date: .omitted, time: .standard))")
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 4)
    }
}

private struct AccountSummaryPanel: View {
    let lifetimeTokens: Int?
    let streakDays: Int?
    let activeSessions: Int
    let accountStatus: String

    var body: some View {
        PulsePanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("账户累计")
                        .font(.headline)
                    Spacer()
                    LiveStatusLabel(isLive: true, title: accountStatus)
                }

                HStack(spacing: 0) {
                    accountMetric(lifetimeTokens.map(PulseFormatters.tokens) ?? "—", label: "Lifetime Tokens")
                    Divider().frame(height: 44)
                    accountMetric(streakDays.map { "\($0) 天" } ?? "—", label: "连续使用")
                    Divider().frame(height: 44)
                    accountMetric(activeSessions.formatted(), label: "运行中")
                }

                Label("来自 Codex 本机 app-server", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
    }

    private func accountMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
