import Charts
import SwiftUI

struct UsageChartView: View {
    let title: String
    let points: [UsageChartPoint]
    let totalTokens: Int
    let forecastTokens: Int?
    let comparisonText: String

    private var actualPoints: [UsageChartPoint] {
        points.filter { $0.kind == .actual }
    }

    private var forecastPoints: [UsageChartPoint] {
        points.filter { $0.kind == .forecast }
    }

    private var usesDailyAxis: Bool {
        guard let first = points.map(\.date).min(), let last = points.map(\.date).max() else { return false }
        return last.timeIntervalSince(first) > 36 * 3_600
    }

    var body: some View {
        PulsePanel {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.headline)

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(totalTokens.formatted())
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("tokens")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 18) {
                    LegendItem(color: PulseTheme.mint, title: "实际使用")
                    if forecastTokens != nil {
                        LegendItem(color: PulseTheme.cyan, title: "预测", dashed: true)
                    }
                }

                if points.isEmpty {
                    ContentUnavailableView(
                        "还没有时间序列",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Codex 会话产生新 token 后会自动显示")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    Chart {
                        ForEach(actualPoints) { point in
                            AreaMark(
                                x: .value("时间", point.date),
                                y: .value("Tokens", point.tokens)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [PulseTheme.mint.opacity(0.34), PulseTheme.mint.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("时间", point.date),
                                y: .value("Tokens", point.tokens),
                                series: .value("系列", "实际")
                            )
                            .foregroundStyle(PulseTheme.mint)
                            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        }

                        ForEach(forecastPoints) { point in
                            LineMark(
                                x: .value("时间", point.date),
                                y: .value("Tokens", point.tokens),
                                series: .value("系列", "预测")
                            )
                            .foregroundStyle(PulseTheme.cyan)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [7, 6]))
                        }
                    }
                    .chartLegend(.hidden)
                    .chartXScale(range: .plotDimension(startPadding: 0, endPadding: 18))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 7)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                                .foregroundStyle(PulseTheme.grid)
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    if usesDailyAxis {
                                        Text(date, format: .dateTime.month().day())
                                    } else {
                                        Text(date, format: .dateTime.hour().minute())
                                    }
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                                .foregroundStyle(PulseTheme.grid)
                            AxisValueLabel {
                                if let amount = value.as(Int.self) {
                                    Text(PulseFormatters.tokens(amount))
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 225)
                }

                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(PulseTheme.mint)
                    Text(comparisonText)
                    if let forecastTokens {
                        Text("· 预计 \(PulseFormatters.tokens(forecastTokens)) tokens")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
            .padding(18)
        }
    }
}

private struct LegendItem: View {
    let color: Color
    let title: String
    var dashed = false

    var body: some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(color)
                .frame(width: 26, height: dashed ? 1 : 2)
                .overlay {
                    if dashed {
                        HStack(spacing: 3) {
                            ForEach(0..<4, id: \.self) { _ in
                                Capsule().fill(color).frame(width: 4, height: 1)
                            }
                        }
                    }
                }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
