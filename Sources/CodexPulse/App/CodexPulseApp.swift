import AppKit
import OSLog
import SwiftUI

private let appLogger = Logger(subsystem: "com.codexpulse.monitor", category: "Lifecycle")

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        appLogger.info("Application launched")
    }
}

@main
struct CodexPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("Codex Pulse", id: "main") {
            ContentView(store: store)
        }
        .defaultSize(width: 1_380, height: 900)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandMenu("监控") {
                Button("刷新全部") {
                    Task { await store.refreshAll(force: true) }
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("打开 CodexRadar") {
                    NSWorkspace.shared.open(URL(string: "https://codexradar.com")!)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarView(store: store)
        } label: {
            Label(store.menuBarTitle, systemImage: "waveform.path.ecg")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}
