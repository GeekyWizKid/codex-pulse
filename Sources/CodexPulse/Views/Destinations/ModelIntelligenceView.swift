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

        return Array(filtered.sorted { lhs, rhs in
            switch (metric.value(for: lhs), metric.value(for: rhs)) {
            case let (left?, right?) where left != right:
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if lhs.model != rhs.model { return lhs.model < rhs.model }
                return lhs.effort < rhs.effort
            }
        }.prefix(100))
    }

    private var leader: DashboardModel? {
        visibleModels.first { metric.value(for: $0) != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            context
                .padding(.vertical, 16)

            Divider()

            table
                .padding(.top, 12)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .searchable(text: $searchText, prompt: "搜索模型或努力等级")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 9) {
                    Text("模型智能")
                        .font(.title2.weight(.semibold))
                    LiveStatusLabel(
                        isLive: store.radarStatus.isReady,
                        title: store.radarStatus.conciseLabel
                    )
                }
                Text("CodexRadar 公共编码任务通过率换算；不会上传个人用量。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("排序指标", selection: $metric) {
                ForEach(IQMetric.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 230)

            Link(destination: URL(string: "https://api.codexradar.com/api/v1/table")!) {
                Label("查看数据源", systemImage: "arrow.up.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.bottom, 18)
    }

    private var context: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(metric.title + "领先")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(leader.map { "\($0.model) · \($0.effort)" } ?? "—")
                    .font(.headline)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 34)
                .padding(.horizontal, 22)

            VStack(alignment: .leading, spacing: 4) {
                Text("IQ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(metric.formattedValue(for: leader))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(leader == nil ? Color.secondary : PulseTheme.cyan)
            }
            .frame(width: 100, alignment: .leading)

            Divider()
                .frame(height: 34)
                .padding(.horizontal, 22)

            VStack(alignment: .leading, spacing: 4) {
                Text("榜单")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.radarMetadata)
                    .font(.callout)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var table: some View {
        if visibleModels.isEmpty {
            ContentUnavailableView(
                "模型榜单暂不可用",
                systemImage: "network.slash",
                description: Text(store.radarStatus.conciseLabel)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(visibleModels) {
                TableColumn("模型") { model in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.model)
                            .fontWeight(.medium)
                        Text(model.effort)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 180, ideal: 250)

                TableColumn("实时 IQ") { model in
                    iqText(model.liveIQ, selected: metric == .live)
                }
                .width(min: 72, ideal: 84, max: 96)

                TableColumn("近期 IQ") { model in
                    iqText(model.recentIQ, selected: metric == .recent)
                }
                .width(min: 72, ideal: 84, max: 96)

                TableColumn("长期 IQ") { model in
                    iqText(model.longTermIQ, selected: metric == .longTerm)
                }
                .width(min: 72, ideal: 84, max: 96)

                TableColumn("覆盖") { model in
                    Text(model.coverage, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                .width(min: 60, ideal: 70, max: 82)

                TableColumn("样本") { model in
                    Text(model.samples.formatted())
                        .monospacedDigit()
                }
                .width(min: 54, ideal: 64, max: 78)

                TableColumn("平均耗时") { model in
                    Text(model.meanDuration.map(PulseFormatters.duration) ?? "—")
                        .monospacedDigit()
                }
                .width(min: 76, ideal: 88, max: 100)

                TableColumn("成本") { model in
                    Text(model.meanCost.map { String(format: "$%.3f", $0) } ?? "—")
                        .monospacedDigit()
                }
                .width(min: 62, ideal: 72, max: 84)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
        }
    }

    private func iqText(_ value: Double, selected: Bool) -> some View {
        Text(value.isFinite ? value.formatted(.number.precision(.fractionLength(1))) : "—")
            .monospacedDigit()
            .fontWeight(selected ? .semibold : .regular)
            .foregroundStyle(selected && value.isFinite ? PulseTheme.cyan : Color.primary)
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

    func value(for model: DashboardModel) -> Double? {
        let value: Double
        switch self {
        case .live: value = model.liveIQ
        case .recent: value = model.recentIQ
        case .longTerm: value = model.longTermIQ
        }
        return value.isFinite ? value : nil
    }

    func formattedValue(for model: DashboardModel?) -> String {
        guard let model, let value = value(for: model) else { return "—" }
        return value.formatted(.number.precision(.fractionLength(1)))
    }
}

private extension LoadStatus {
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}
