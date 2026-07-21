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

        let hostingView = NSHostingView(rootView: renderedView)
        hostingView.frame = CGRect(x: 0, y: 0, width: 1_440, height: 1_024)
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
        try await Task.sleep(nanoseconds: 1_000_000_000)
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
}
