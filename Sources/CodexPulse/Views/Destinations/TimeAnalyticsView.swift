import Charts
import SwiftUI

struct TimeAnalyticsView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("时间")
                            .font(.system(size: 30, weight: .bold))
                        Text("看见真正活跃的工作时间，而不是把后台等待算成工作")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("时间范围", selection: $store.range) {
                        ForEach(DashboardRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }

                HStack(spacing: 12) {
                    TimeMetric(title: "活跃时长", value: PulseFormatters.duration(store.usage.activeDuration), icon: "clock.fill", tint: PulseTheme.mint)
                    TimeMetric(title: "会话", value: store.usage.sessions.formatted(), icon: "text.bubble.fill", tint: PulseTheme.cyan)
                    TimeMetric(title: "平均会话", value: PulseFormatters.duration(store.averageSessionDuration), icon: "timer", tint: PulseTheme.violet)
                    TimeMetric(title: "连续使用", value: store.usage.currentStreakDays.map { "\($0) 天" } ?? "—", icon: "flame.fill", tint: PulseTheme.amber)
                }

                PulsePanel {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("每日 Token 与活跃时长")
                                .font(.headline)
                            Spacer()
                            HStack(spacing: 14) {
                                legend("Tokens", color: PulseTheme.mint)
                                legend("活跃分钟", color: PulseTheme.violet)
                            }
                        }

                        if store.dailyUsage.isEmpty {
                            ContentUnavailableView(
                                "还没有时间数据",
                                systemImage: "clock.badge.questionmark",
                                description: Text("完成一个 Codex 回合后会显示真实 duration_ms")
                            )
                            .frame(maxWidth: .infinity, minHeight: 290)
                        } else {
                            Chart(store.dailyUsage) { point in
                                BarMark(
                                    x: .value("日期", point.date, unit: .day),
                                    y: .value("Tokens", point.tokens)
                                )
                                .foregroundStyle(PulseTheme.mint.gradient)
                                .cornerRadius(3)

                                LineMark(
                                    x: .value("日期", point.date, unit: .day),
                                    y: .value("活跃分钟", Int(point.activeDuration / 60))
                                )
                                .foregroundStyle(PulseTheme.violet)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .symbol(.circle)
                            }
                            .chartLegend(.hidden)
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: store.range == .thirtyDays ? 10 : 7)) { _ in
                                    AxisGridLine().foregroundStyle(PulseTheme.grid)
                                    AxisValueLabel(format: .dateTime.month().day())
                                }
                            }
                            .chartYAxis {
                                AxisMarks(position: .leading) { value in
                                    AxisGridLine().foregroundStyle(PulseTheme.grid)
                                    AxisValueLabel {
                                        if let amount = value.as(Int.self) {
                                            Text(PulseFormatters.tokens(amount))
                                        }
                                    }
                                }
                            }
                            .frame(minHeight: 310)
                        }
                    }
                    .padding(18)
                }

                HStack(alignment: .top, spacing: 12) {
                    PeakHoursPanel(points: store.hourlyTokens)
                    WorkRhythmPanel(store: store)
                        .frame(width: 360)
                }
            }
            .padding(22)
        }
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct TimeMetric: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        PulsePanel {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(value)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(15)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PeakHoursPanel: View {
    let points: [Int]

    private var maximum: Int { max(points.max() ?? 0, 1) }

    var body: some View {
        PulsePanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("24 小时活跃分布")
                    .font(.headline)
                Text("颜色越亮，表示该时段产生的 token 越多")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(0..<24, id: \.self) { hour in
                        let value = points.indices.contains(hour) ? points[hour] : 0
                        VStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(PulseTheme.mint.opacity(0.12 + 0.88 * Double(value) / Double(maximum)))
                                .frame(height: 24 + 84 * Double(value) / Double(maximum))
                            if hour % 3 == 0 {
                                Text("\(hour)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            } else {
                                Color.clear.frame(height: 11)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .help("\(hour):00 · \(PulseFormatters.tokens(value)) tokens")
                    }
                }
                .frame(minHeight: 130, alignment: .bottom)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WorkRhythmPanel: View {
    @ObservedObject var store: AppStore

    var body: some View {
        PulsePanel {
            VStack(alignment: .leading, spacing: 15) {
                Text("工作节奏")
                    .font(.headline)

                rhythmRow("最常用时段", store.peakHourLabel, icon: "sun.max")
                rhythmRow("最长项目", store.longestProjectLabel, icon: "folder")
                rhythmRow("当前运行", "\(store.usage.activeSessions) 个会话", icon: "bolt.horizontal")
                rhythmRow("扫描方式", "增量 · 只读", icon: "externaldrive.badge.checkmark")

                Divider()
                Label("等待网络或用户输入的时间不会计入活跃时长", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
    }

    private func rhythmRow(_ title: String, _ value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
        }
    }
}
