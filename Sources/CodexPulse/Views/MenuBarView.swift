import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @AppStorage("quotaWarningThreshold") private var lowQuotaThreshold = 20.0

    private var primaryQuota: DashboardQuota? {
        store.displayQuotas.first
    }

    private var remainingPercent: Double? {
        primaryQuota?.remainingPercent
    }

    private var activeProject: DashboardProject? {
        store.usage.projects.first(where: \.isActive) ?? store.usage.projects.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            quota

            Divider()

            usage

            if let activeProject {
                Divider()

                HStack(spacing: 8) {
                    Image(systemName: activeProject.isActive ? "terminal.fill" : "folder")
                        .foregroundStyle(activeProject.isActive ? PulseTheme.cyan : .secondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeProject.isActive ? "当前项目" : "最近项目")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(shortTitle(activeProject.name))
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(PulseFormatters.tokens(activeProject.tokens))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            controls
        }
        .padding(14)
        .frame(width: 310)
        .preferredColorScheme(.dark)
        .task {
            await store.startMonitoringIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform.path.ecg")
                .font(.title3.weight(.semibold))
                .foregroundStyle(PulseTheme.cyan)

            VStack(alignment: .leading, spacing: 1) {
                Text("Codex Pulse")
                    .font(.headline)
                Text(store.status.conciseLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.status.isLoading || store.accountStatus.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var quota: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(primaryQuota?.title ?? "Codex 额度")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(remainingPercent.map { "剩余 \(Int($0.rounded()))%" } ?? "剩余 —")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(quotaColor)
            }

            if let remainingPercent {
                ProgressView(value: remainingPercent, total: 100)
                    .tint(quotaColor)
            }

            Text(resetDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var quotaColor: Color {
        guard let remainingPercent else { return .secondary }
        return remainingPercent <= lowQuotaThreshold ? PulseTheme.danger : PulseTheme.cyan
    }

    private var resetDescription: String {
        if let resetAt = primaryQuota?.resetAt {
            return "\(PulseFormatters.countdown(to: resetAt))后重置"
        }
        return store.accountStatus.conciseLabel
    }

    private var usage: some View {
        HStack(spacing: 0) {
            menuMetric(PulseFormatters.tokens(store.usage.tokens), "Token")
            Divider().frame(height: 32)
            menuMetric(PulseFormatters.duration(store.usage.activeDuration), "活跃")
            Divider().frame(height: 32)
            menuMetric(store.usage.activeSessions.formatted(), "运行中")
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("打开", systemImage: "macwindow")
            }
            .keyboardShortcut("o", modifiers: .command)

            Spacer()

            Button {
                Task { await store.refreshAll(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("刷新")
            .disabled(store.status.isLoading)

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("设置")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("退出")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func menuMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func shortTitle(_ value: String) -> String {
        value.count <= 32 ? value : String(value.prefix(29)) + "…"
    }
}
