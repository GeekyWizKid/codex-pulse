import Charts
import SwiftUI

struct TimeAnalyticsView: View {
    @ObservedObject var store: AppStore

    private var plotPoints: [TimePlotPoint] {
        if store.range == .today {
            let calendar = Calendar.current
            let day = calendar.startOfDay(for: Date())
            return store.hourlyTokens.enumerated().map { hour, tokens in
                TimePlotPoint(
                    date: calendar.date(byAdding: .hour, value: hour, to: day) ?? day,
                    tokens: tokens
                )
            }
        }

        return store.dailyUsage.map {
            TimePlotPoint(date: $0.date, tokens: $0.tokens)
        }
    }

    private var hasUsage: Bool {
        plotPoints.contains { $0.tokens > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            summary
                .padding(.vertical, 18)

            Divider()

            chart
                .padding(.top, 20)

            Divider()
                .padding(.top, 20)

            context
                .padding(.vertical, 16)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("时间")
                .font(.title2.weight(.semibold))
            Text("只统计真实活跃时间；等待网络与用户输入不会计入。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 18)
    }

    private var summary: some View {
        HStack(spacing: 0) {
            TimeReadout(
                title: "活跃时长",
                value: PulseFormatters.duration(store.usage.activeDuration)
            )
            readoutDivider
            TimeReadout(
                title: "会话",
                value: store.usage.sessions.formatted()
            )
            readoutDivider
            TimeReadout(
                title: "平均会话",
                value: PulseFormatters.duration(store.averageSessionDuration)
            )
            readoutDivider
            TimeReadout(
                title: "连续使用",
                value: store.usage.currentStreakDays.map { "\($0) 天" } ?? "—"
            )
        }
    }

    private var readoutDivider: some View {
        Divider()
            .frame(height: 34)
            .padding(.horizontal, 22)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.range == .today ? "每小时 Token" : "每日 Token")
                    .font(.headline)
                Spacer()
                Text(store.comparisonText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if hasUsage {
                Chart(plotPoints) { point in
                    BarMark(
                        x: .value("时间", point.date),
                        y: .value("Token", point.tokens)
                    )
                    .foregroundStyle(PulseTheme.cyan.opacity(0.82))
                    .cornerRadius(2)
                }
                .chartLegend(.hidden)
                .chartXAxis {
                    if store.range == .today {
                        AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                            AxisGridLine().foregroundStyle(PulseTheme.grid)
                            AxisValueLabel(format: .dateTime.hour())
                        }
                    } else {
                        AxisMarks(values: .automatic(desiredCount: store.range == .thirtyDays ? 8 : 7)) { _ in
                            AxisGridLine().foregroundStyle(PulseTheme.grid)
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine().foregroundStyle(PulseTheme.grid)
                        AxisValueLabel {
                            if let amount = value.as(Int.self) {
                                Text(PulseFormatters.tokens(amount))
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .frame(minHeight: 260)
            } else {
                ContentUnavailableView(
                    "还没有时间数据",
                    systemImage: "clock.badge.questionmark",
                    description: Text("完成一个 Codex 回合后，这里会显示真实的 Token 时间分布。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 260)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var context: some View {
        HStack(spacing: 24) {
            Label {
                Text("常用时段 \(store.peakHourLabel)")
            } icon: {
                Image(systemName: "clock")
            }

            Label {
                Text("最长项目 \(shortened(store.longestProjectLabel))")
            } icon: {
                Image(systemName: "folder")
            }

            Label {
                Text("\(store.usage.activeSessions) 个会话运行中")
            } icon: {
                Image(systemName: "bolt.horizontal")
            }

            Spacer()

            Label("增量 · 只读", systemImage: "externaldrive.badge.checkmark")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func shortened(_ value: String) -> String {
        value.count <= 34 ? value : String(value.prefix(31)) + "…"
    }
}

private struct TimePlotPoint: Identifiable {
    let date: Date
    let tokens: Int

    var id: Date { date }
}

private struct TimeReadout: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
