import Charts
import SwiftUI

struct OverviewView: View {
    @ObservedObject var store: AppStore
    @Binding var selectedQuotaIndex: Int

    init(store: AppStore, selectedQuotaIndex: Binding<Int> = .constant(0)) {
        self.store = store
        _selectedQuotaIndex = selectedQuotaIndex
    }

    private var selectedQuota: DashboardQuota? {
        let quotas = store.displayQuotas
        guard quotas.indices.contains(selectedQuotaIndex) else {
            return quotas.first
        }
        return quotas[selectedQuotaIndex]
    }

    private var runway: QuotaRunwaySnapshot? {
        selectedQuota.flatMap { store.quotaRunway(for: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                if let runway {
                    QuotaRunwayChart(runway: runway)
                } else {
                    ContentUnavailableView {
                        Label("等待 Codex 额度", systemImage: "gauge.with.dots.needle.0percent")
                    } description: {
                        Text(accountPlaceholder)
                    } actions: {
                        Button("重试") {
                            Task { await store.refreshAll(force: true) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 34)
            .padding(.top, 22)
            .padding(.bottom, 20)

            statusStrip
        }
        .background(PulseTheme.detailBackground)
        .accessibilityIdentifier("overview")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 28) {
            Text(headline)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.primary)

            if let remaining = selectedQuota?.remainingPercent {
                HStack(spacing: 5) {
                    Text("剩余")
                        .foregroundStyle(.secondary)
                    Text("\(Int(remaining.rounded()))%")
                        .foregroundStyle(quotaColor(for: remaining))
                        .monospacedDigit()
                }
                .font(.title3)
            }

            if let resetAt = selectedQuota?.resetAt {
                Text("\(resetAt.formatted(.dateTime.weekday(.short).hour().minute())) 重置")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()
        }
        .padding(.horizontal, 34)
        .padding(.top, 38)
    }

    private var statusStrip: some View {
        HStack(spacing: 10) {
            Text("当前")
                .foregroundStyle(.secondary)
            Text(activeProjectName)
            Text("·")
                .foregroundStyle(.tertiary)
            Text("\(store.usage.activeSessions) 个任务运行")
            Text("·")
                .foregroundStyle(.tertiary)
            Text("今日 \(PulseFormatters.tokens(store.todayTokens)) tokens")

            Circle()
                .fill(store.usage.activeSessions > 0 ? PulseTheme.success : Color.secondary)
                .frame(width: 7, height: 7)
                .padding(.leading, 2)
            Text(store.usage.activeSessions > 0 ? "运行" : "监控中")
                .foregroundStyle(store.usage.activeSessions > 0 ? PulseTheme.success : .secondary)

            Spacer(minLength: 20)

            Text(currentModelSummary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.callout)
        .padding(.horizontal, 34)
        .frame(height: 72)
        .overlay(alignment: .top) {
            Divider()
                .padding(.horizontal, 34)
        }
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        guard let remaining = selectedQuota?.remainingPercent else {
            return "等待额度数据"
        }
        switch remaining {
        case 50...:
            return "运行空间充足"
        case 25..<50:
            return "使用节奏稳定"
        case 10..<25:
            return "额度正在收紧"
        default:
            return "额度接近上限"
        }
    }

    private var accountPlaceholder: String {
        switch store.accountStatus {
        case .degraded(let message, _):
            return message
        case .loading(let message):
            return message
        case .idle:
            return "正在连接本机 Codex 服务"
        case .ready:
            return "当前账户没有返回可显示的额度窗口"
        }
    }

    private var activeProjectName: String {
        let value = store.usage.projects.first(where: \.isActive)?.name
            ?? store.usage.projects.first?.name
            ?? "暂无项目"
        return value.count <= 34 ? value : String(value.prefix(31)) + "…"
    }

    private var currentModelSummary: String {
        let activeModel = store.usage.projects
            .first(where: \.isActive)?
            .models
            .first
        let row = activeModel.flatMap { model in
            store.usage.models.first(where: { $0.model == model })
        } ?? store.usage.models.first

        guard let row else {
            return "CodexRadar · 等待模型数据"
        }
        let score = row.liveIQ.isFinite
            ? "IQ \(row.liveIQ.formatted(.number.precision(.fractionLength(1))))"
            : "IQ —"
        return "\(row.model) \(row.effort) · \(score)"
    }

    private func quotaColor(for remaining: Double) -> Color {
        let threshold = UserDefaults.standard.object(forKey: "quotaWarningThreshold") as? Double ?? 20
        if remaining <= 10 {
            return PulseTheme.danger
        }
        if remaining <= threshold {
            return PulseTheme.warning
        }
        return PulseTheme.accent
    }
}

private struct QuotaRunwayChart: View {
    let runway: QuotaRunwaySnapshot

    private var forecast: [QuotaRunwayPoint] {
        [
            QuotaRunwayPoint(date: runway.observedAt, percent: runway.usedPercent),
            QuotaRunwayPoint(date: runway.resetAt, percent: runway.forecastPercent)
        ]
    }

    private var ideal: [QuotaRunwayPoint] {
        [
            QuotaRunwayPoint(date: runway.startAt, percent: 0),
            QuotaRunwayPoint(date: runway.resetAt, percent: runway.idealPercent)
        ]
    }

    private var xAxisDates: [Date] {
        let duration = runway.resetAt.timeIntervalSince(runway.startAt)
        return (1..<8).map { index in
            runway.startAt.addingTimeInterval(duration * Double(index) / 8)
        }
    }

    var body: some View {
        Chart {
            ForEach(ideal) { point in
                LineMark(
                    x: .value("时间", point.date),
                    y: .value("理想节奏", point.percent),
                    series: .value("序列", "理想节奏")
                )
                .foregroundStyle(Color.secondary.opacity(0.75))
                .lineStyle(StrokeStyle(lineWidth: 1))
            }

            ForEach(runway.actual) { point in
                LineMark(
                    x: .value("时间", point.date),
                    y: .value("实际使用", point.percent),
                    series: .value("序列", "实际使用")
                )
                .foregroundStyle(PulseTheme.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }

            ForEach(forecast) { point in
                LineMark(
                    x: .value("时间", point.date),
                    y: .value("预计", point.percent),
                    series: .value("序列", "预计")
                )
                .foregroundStyle(PulseTheme.accent)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [7, 7]))
            }

            PointMark(
                x: .value("当前时间", runway.observedAt),
                y: .value("实际使用", runway.usedPercent)
            )
            .foregroundStyle(PulseTheme.accent)
            .symbolSize(45)
            .annotation(position: .bottom, alignment: .leading, spacing: 14) {
                Text("实际使用 \(runway.usedPercent.formatted(.number.precision(.fractionLength(0))))%")
                    .foregroundStyle(PulseTheme.accent)
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
            }

            RuleMark(x: .value("重置", runway.resetAt))
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 6]))
                .annotation(position: .top, alignment: .center, spacing: 8) {
                    VStack(spacing: 2) {
                        Text("重置")
                            .font(.callout.weight(.medium))
                        Text(runway.resetAt.formatted(.dateTime.month().day().hour().minute()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

            PointMark(
                x: .value("重置时间", runway.resetAt),
                y: .value("预计", runway.forecastPercent)
            )
            .foregroundStyle(PulseTheme.accent)
            .symbolSize(38)
            .annotation(position: .trailing, alignment: .center, spacing: 12) {
                Text("预计 \(runway.forecastPercent.formatted(.number.precision(.fractionLength(0))))%")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(PulseTheme.accent)
                    .monospacedDigit()
            }

            PointMark(
                x: .value("重置时间", runway.resetAt),
                y: .value("理想节奏", runway.idealPercent)
            )
            .foregroundStyle(Color.secondary)
            .symbolSize(0)
            .annotation(position: .trailing, alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("理想节奏")
                    Text("\(runway.idealPercent.formatted(.number.precision(.fractionLength(0))))%")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .chartXScale(domain: runway.startAt...runway.resetAt)
        .chartYScale(domain: 0...100)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                    .foregroundStyle(PulseTheme.grid)
                AxisValueLabel {
                    if let percent = value.as(Int.self) {
                        Text("\(percent)%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisDates) { value in
                AxisGridLine()
                    .foregroundStyle(Color.clear)
                AxisTick()
                    .foregroundStyle(PulseTheme.border)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(xAxisLabel(date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.trailing, 84)
        .help("官方额度百分比；曲线形态由本机 Codex 活动构成，预测按当前节奏外推。")
        .accessibilityLabel("额度运行空间图")
        .accessibilityValue(
            "已使用 \(runway.usedPercent.formatted(.number.precision(.fractionLength(0))))%，预计重置时 \(runway.forecastPercent.formatted(.number.precision(.fractionLength(0))))%"
        )
    }

    private func xAxisLabel(_ date: Date) -> String {
        if runway.resetAt.timeIntervalSince(runway.startAt) <= 48 * 3_600 {
            return date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(.dateTime.month().day())
    }
}
