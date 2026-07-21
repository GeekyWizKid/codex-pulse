import AppKit
import SwiftUI
import XCTest
@testable import CodexPulse

final class VisualSnapshotTests: XCTestCase {
    @MainActor
    func testRenderLiveDashboardWhenRequested() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment["CODEX_PULSE_SNAPSHOT_PATH"],
              !outputPath.isEmpty else {
            throw XCTSkip("Set CODEX_PULSE_SNAPSHOT_PATH to render the live dashboard.")
        }

        let store = AppStore()
        await store.refreshAll(force: true)

        let renderedView = ContentView(store: store)
            .frame(width: 1_440, height: 1_024)
            .background(PulseTheme.background)
            .environment(\.colorScheme, .dark)

        try await render(renderedView, to: outputPath, size: CGSize(width: 1_440, height: 1_024))
    }

    @MainActor
    func testRenderReadmeScreenshotsWhenRequested() async throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment["CODEX_PULSE_README_SCREENSHOT_DIR"],
              !outputDirectory.isEmpty else {
            throw XCTSkip("Set CODEX_PULSE_README_SCREENSHOT_DIR to render README screenshots.")
        }

        let store = AppStore()
        store.usage = Self.readmeUsage()
        store.status = .ready(Date())
        store.radarStatus = .ready(Date())
        store.accountStatus = .ready(Date())

        let size = CGSize(width: 1_440, height: 900)
        let requestedDestination = ProcessInfo.processInfo.environment["CODEX_PULSE_README_SCREENSHOT_DESTINATION"]
        if requestedDestination == nil || requestedDestination == SidebarDestination.projects.rawValue {
            try await render(
                dashboardShell(destination: .projects, store: store),
                to: URL(fileURLWithPath: outputDirectory).appendingPathComponent("projects.png").path,
                size: size
            )
        }
        if requestedDestination == nil || requestedDestination == SidebarDestination.modelIntelligence.rawValue {
            try await render(
                dashboardShell(destination: .modelIntelligence, store: store),
                to: URL(fileURLWithPath: outputDirectory).appendingPathComponent("model-intelligence.png").path,
                size: size
            )
        }
    }

    @MainActor
    private func dashboardShell(destination: SidebarDestination, store: AppStore) -> some View {
        let selection = Binding<SidebarDestination?>(
            get: { destination },
            set: { _ in }
        )

        return HStack(spacing: 0) {
            SidebarView(selection: selection)
                .frame(width: 232)

            Divider()
                .overlay(PulseTheme.border)

            Group {
                switch destination {
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
        .frame(width: 1_440, height: 900)
        .background(PulseTheme.background)
        .preferredColorScheme(.dark)
    }

    @MainActor
    private func render<V: View>(_ renderedView: V, to outputPath: String, size: CGSize) async throws {
        let hostingView = NSHostingView(rootView: renderedView)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.wantsLayer = true
        hostingView.appearance = NSAppearance(named: .darkAqua)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 600_000_000)
        hostingView.layoutSubtreeIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            XCTFail("Could not render the SwiftUI dashboard")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode the SwiftUI dashboard")
            return
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try png.write(to: outputURL, options: .atomic)
        XCTAssertGreaterThan(png.count, 30_000)
        window.close()
    }

    private static func readmeUsage() -> DashboardUsage {
        let now = Date()
        var usage = DashboardUsage()
        usage.generatedAt = now
        usage.tokens = 286_420
        usage.inputTokens = 121_900
        usage.cachedTokens = 88_400
        usage.outputTokens = 51_320
        usage.reasoningTokens = 24_800
        usage.activeDuration = 15_180
        usage.sessions = 31
        usage.activeSessions = 1
        usage.dataSourceLabel = "本地 Codex 日志"
        usage.projects = [
            DashboardProject(
                id: "codex-pulse",
                name: "codex-pulse",
                activeDuration: 6_780,
                sessions: 12,
                tokens: 126_780,
                inputTokens: 55_200,
                cachedTokens: 39_100,
                outputTokens: 22_480,
                reasoningTokens: 10_000,
                share: 0.443,
                isActive: true,
                lastActiveAt: now.addingTimeInterval(-80),
                models: ["gpt-5.6-sol", "gpt-5.6-terra"]
            ),
            DashboardProject(
                id: "swift-agent-lab",
                name: "swift-agent-lab",
                activeDuration: 4_260,
                sessions: 8,
                tokens: 74_210,
                inputTokens: 31_400,
                cachedTokens: 22_100,
                outputTokens: 14_710,
                reasoningTokens: 6_000,
                share: 0.259,
                isActive: false,
                lastActiveAt: now.addingTimeInterval(-2_400),
                models: ["gpt-5.6-sol"]
            ),
            DashboardProject(
                id: "docs-automation",
                name: "docs-automation",
                activeDuration: 2_820,
                sessions: 6,
                tokens: 52_430,
                inputTokens: 21_900,
                cachedTokens: 16_500,
                outputTokens: 9_830,
                reasoningTokens: 4_200,
                share: 0.183,
                isActive: false,
                lastActiveAt: now.addingTimeInterval(-7_800),
                models: ["gpt-5.6-terra"]
            ),
            DashboardProject(
                id: "api-benchmarks",
                name: "api-benchmarks",
                activeDuration: 1_320,
                sessions: 5,
                tokens: 33_000,
                inputTokens: 13_400,
                cachedTokens: 10_700,
                outputTokens: 6_300,
                reasoningTokens: 2_600,
                share: 0.115,
                isActive: false,
                lastActiveAt: now.addingTimeInterval(-18_000),
                models: ["gpt-5.6-sol"]
            )
        ]
        usage.models = [
            DashboardModel(model: "gpt-5.6-sol", effort: "max", liveIQ: 101.8, recentIQ: 100.7, longTermIQ: 99.9, coverage: 0.94, samples: 112, meanDuration: 96, meanCost: 0.041),
            DashboardModel(model: "gpt-5.6-terra", effort: "ultra", liveIQ: 99.1, recentIQ: 98.7, longTermIQ: 98.2, coverage: 0.91, samples: 109, meanDuration: 82, meanCost: 0.032),
            DashboardModel(model: "gpt-5.6-terra", effort: "max", liveIQ: 99.1, recentIQ: 98.2, longTermIQ: 97.8, coverage: 0.89, samples: 108, meanDuration: 74, meanCost: 0.028),
            DashboardModel(model: "gpt-5.6-sol", effort: "ultra", liveIQ: 97.8, recentIQ: 97.3, longTermIQ: 96.9, coverage: 0.87, samples: 106, meanDuration: 68, meanCost: 0.025),
            DashboardModel(model: "gpt-5.6-luna", effort: "max", liveIQ: 97.8, recentIQ: 96.8, longTermIQ: 96.2, coverage: 0.84, samples: 102, meanDuration: 61, meanCost: 0.021),
            DashboardModel(model: "gpt-5.5-codex", effort: "high", liveIQ: 95.4, recentIQ: 95.0, longTermIQ: 94.6, coverage: 0.81, samples: 98, meanDuration: 57, meanCost: 0.019)
        ]
        return usage
    }
}
