import SwiftUI

struct ContentView: View {
    @ObservedObject var store: AppStore
    @SceneStorage("sidebar.selection") private var selectionRawValue = SidebarDestination.overview.rawValue
    @State private var selectedQuotaIndex = 0

    private var selection: Binding<SidebarDestination?> {
        Binding(
            get: { SidebarDestination(rawValue: selectionRawValue) ?? .overview },
            set: { selectionRawValue = ($0 ?? .overview).rawValue }
        )
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: selection)
        } detail: {
            Group {
                switch selection.wrappedValue ?? .overview {
                case .overview:
                    OverviewView(store: store, selectedQuotaIndex: $selectedQuotaIndex)
                case .projects:
                    ProjectsView(store: store)
                case .time:
                    TimeAnalyticsView(store: store)
                case .modelIntelligence:
                    ModelIntelligenceView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PulseTheme.detailBackground)
            .navigationTitle("Codex Pulse")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if selection.wrappedValue == .overview {
                        quotaPicker
                    } else if selection.wrappedValue == .projects || selection.wrappedValue == .time {
                        rangePicker
                    }

                    Text(freshnessLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Button {
                        Task { await store.refreshAll(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(store.status.isLoading || store.accountStatus.isLoading)
                    .help("立即刷新（⌘R）")
                    .accessibilityIdentifier("toolbar.refresh")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 980, minHeight: 650)
        .preferredColorScheme(.dark)
        .tint(PulseTheme.accent)
        .task {
            await store.startMonitoringIfNeeded()
        }
        .onChange(of: store.displayQuotas.count) { _, count in
            if count > 0, selectedQuotaIndex >= count {
                selectedQuotaIndex = 0
            }
        }
    }

    private var quotaPicker: some View {
        Picker("额度窗口", selection: $selectedQuotaIndex) {
            ForEach(quotaSegments, id: \.index) { segment in
                Text(segment.title).tag(segment.index)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 186)
        .disabled(store.displayQuotas.count < 2)
        .accessibilityIdentifier("overview.quota-window")
    }

    private var quotaSegments: [(index: Int, title: String)] {
        let quotas = Array(store.displayQuotas.prefix(2))
        guard !quotas.isEmpty else {
            return [(0, "5 小时"), (1, "7 天")]
        }
        return quotas.enumerated().map { index, quota in
            (index, compactTitle(for: quota, fallback: index))
        }
    }

    private var rangePicker: some View {
        Picker("时间范围", selection: $store.range) {
            ForEach(DashboardRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 210)
        .accessibilityIdentifier("toolbar.range")
    }

    private var freshnessLabel: String {
        let status = selection.wrappedValue == .overview ? store.accountStatus : store.status
        if status.isLoading {
            return "正在更新"
        }
        if let date = status.updatedAt {
            return "更新于 \(date.formatted(date: .numeric, time: .shortened))"
        }
        switch status {
        case .degraded:
            return "数据延迟"
        case .idle:
            return "等待数据"
        case .loading, .ready:
            return "正在更新"
        }
    }

    private func compactTitle(for quota: DashboardQuota, fallback index: Int) -> String {
        guard let minutes = quota.windowMinutes, minutes > 0 else {
            return index == 0 ? "主要" : "次要"
        }
        if minutes % 10_080 == 0 {
            return "\(minutes / 10_080 * 7) 天"
        }
        if minutes % 1_440 == 0 {
            return "\(minutes / 1_440) 天"
        }
        if minutes % 60 == 0 {
            return "\(minutes / 60) 小时"
        }
        return "\(minutes) 分钟"
    }
}
