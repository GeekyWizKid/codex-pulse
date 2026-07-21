import SwiftUI

struct ContentView: View {
    @ObservedObject var store: AppStore
    @SceneStorage("sidebar.selection") private var selectionRawValue = SidebarDestination.overview.rawValue

    private var selection: Binding<SidebarDestination?> {
        Binding(
            get: { SidebarDestination(rawValue: selectionRawValue) ?? .overview },
            set: { selectionRawValue = ($0 ?? .overview).rawValue }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: selection)
                .frame(width: 232)

            Divider()
                .overlay(PulseTheme.border)

            Group {
                switch selection.wrappedValue ?? .overview {
                case .overview:
                    OverviewView(store: store)
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
        }
        .frame(minWidth: 1_060, minHeight: 700)
        .preferredColorScheme(.dark)
        .task {
            await store.startMonitoringIfNeeded()
        }
    }
}
