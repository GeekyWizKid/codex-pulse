import Charts
import SwiftUI

struct ModelIntelligenceView: View {
    @ObservedObject var store: AppStore
    @State private var metric: IQMetric = .live
    @State private var searchText = ""

    private var visibleModels: [DashboardModel] {
        let filtered = searchText.isEmpty
            ? store.usage.models
            : store.usage.models.filter {
                $0.model.localizedCaseInsensitiveContains(searchText)
                    || $0.effort.localizedCaseInsensitiveContains(searchText)
            }
        return Array(filtered.prefix(30))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Text("模型智商")
                                .font(.system(size: 30, weight: .bold))
                            LiveStatusLabel(
                                isLive: store.radarStatus.isReady,
                                title: store.radarStatus.conciseLabel
                            )
                        }
                        Text("公共编码任务通过率换算为 IQ；个人用量不会发送给 CodexRadar")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("指标", selection: $metric) {
                        ForEach(IQMetric.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 270)
                    Link(destination: URL(string: "https://api.codexradar.com/api/v1/table")!) {
                        Label("API", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                }

                PulsePanel {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("智商排行")
                                .font(.headline)
                            Spacer()
                            Text(store.radarMetadata)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if visibleModels.isEmpty {
                            ContentUnavailableView(
                                "模型榜单暂不可用",
                                systemImage: "network.slash",
                                description: Text(store.radarStatus.conciseLabel)
                            )
                            .frame(maxWidth: .infinity, minHeight: 300)
                        } else {
                            Chart(visibleModels.prefix(12)) { model in
                                BarMark(
                                    x: .value("IQ", metric.value(for: model)),
                                    y: .value("模型", "\(model.model) · \(model.effort)")
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [PulseTheme.mint, PulseTheme.cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(4)
                                .annotation(position: .trailing) {
                                    Text(metric.value(for: model), format: .number.precision(.fractionLength(1)))
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(PulseTheme.mint)
                                }
                            }
                            .chartLegend(.hidden)
                            .chartXAxis {
                                AxisMarks { _ in
                                    AxisGridLine().foregroundStyle(PulseTheme.grid)
                                    AxisValueLabel()
                                }
                            }
                            .frame(minHeight: 360)
                        }
                    }
                    .padding(18)
                }

                ModelIQTable(models: visibleModels, metric: metric)
            }
            .padding(22)
        }
        .searchable(text: $searchText, prompt: "搜索模型或努力等级")
    }
}

private enum IQMetric: String, CaseIterable, Identifiable {
    case live
    case recent
    case longTerm

    var id: String { rawValue }
    var title: String {
        switch self {
        case .live: "实时"
        case .recent: "近期"
        case .longTerm: "长期"
        }
    }

    func value(for model: DashboardModel) -> Double {
        switch self {
        case .live: model.liveIQ
        case .recent: model.recentIQ
        case .longTerm: model.longTermIQ
        }
    }
}

private struct ModelIQTable: View {
    let models: [DashboardModel]
    let metric: IQMetric

    var body: some View {
        PulsePanel {
            VStack(spacing: 0) {
                HStack {
                    Text("模型 / 努力等级")
                    Spacer()
                    Text("实时 IQ").frame(width: 90, alignment: .trailing)
                    Text("近期 IQ").frame(width: 90, alignment: .trailing)
                    Text("长期 IQ").frame(width: 90, alignment: .trailing)
                    Text("覆盖").frame(width: 86, alignment: .trailing)
                    Text("样本").frame(width: 70, alignment: .trailing)
                    Text("平均耗时").frame(width: 100, alignment: .trailing)
                    Text("成本").frame(width: 80, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(16)

                Divider().opacity(0.5)

                ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                    HStack {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(index < 3 ? PulseTheme.mint : .secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.model).font(.callout.weight(.medium))
                            Text(model.effort).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        iq(model.liveIQ, selected: metric == .live)
                        iq(model.recentIQ, selected: metric == .recent)
                        iq(model.longTermIQ, selected: metric == .longTerm)
                        Text(model.coverage, format: .percent.precision(.fractionLength(0)))
                            .frame(width: 86, alignment: .trailing)
                        Text(model.samples.formatted())
                            .frame(width: 70, alignment: .trailing)
                        Text(model.meanDuration.map { PulseFormatters.duration($0) } ?? "—")
                            .frame(width: 100, alignment: .trailing)
                        Text(model.meanCost.map { String(format: "$%.3f", $0) } ?? "—")
                            .frame(width: 80, alignment: .trailing)
                    }
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    if index < models.count - 1 {
                        Divider().opacity(0.35).padding(.leading, 16)
                    }
                }
            }
        }
    }

    private func iq(_ value: Double, selected: Bool) -> some View {
        Text(value, format: .number.precision(.fractionLength(1)))
            .fontWeight(selected ? .semibold : .regular)
            .foregroundStyle(selected ? PulseTheme.mint : Color.primary)
            .frame(width: 90, alignment: .trailing)
    }
}

private extension LoadStatus {
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}
