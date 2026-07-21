import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: AppStore
    @Environment(\.openWindow) private var openWindow

    private var primaryQuota: DashboardQuota? {
        store.displayQuotas.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(PulseTheme.mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex Pulse")
                        .font(.headline)
                    Text(store.status.conciseLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.status.isLoading {
                    ProgressView().controlSize(.small)
                }
            }

            if let quota = primaryQuota {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(quota.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("剩余 \(Int((quota.remainingPercent ?? 0).rounded()))%")
                            .font(.callout.weight(.semibold).monospacedDigit())
                    }
                    ProgressView(value: quota.remainingPercent ?? 0, total: 100)
                        .tint((quota.remainingPercent ?? 0) < 20 ? PulseTheme.danger : PulseTheme.mint)
                    Text("\(PulseFormatters.countdown(to: quota.resetAt))后重置")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("正在连接 Codex 官方额度服务", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                menuMetric(PulseFormatters.tokens(store.usage.tokens), "Tokens")
                Divider().frame(height: 34)
                menuMetric(PulseFormatters.duration(store.usage.activeDuration), "活跃")
                Divider().frame(height: 34)
                menuMetric(store.usage.activeSessions.formatted(), "运行中")
            }

            if !store.usage.projects.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("高消耗项目")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(store.usage.projects.prefix(3)) { project in
                        HStack {
                            Image(systemName: project.isActive ? "terminal.fill" : "folder")
                                .foregroundStyle(project.isActive ? PulseTheme.mint : .secondary)
                                .frame(width: 16)
                            Text(shortTitle(project.name))
                                .lineLimit(1)
                            Spacer()
                            Text(PulseFormatters.tokens(project.tokens))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }

            Divider()

            HStack {
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("打开控制台", systemImage: "rectangle.on.rectangle")
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
        .padding(16)
        .frame(width: 320)
        .preferredColorScheme(.dark)
        .task {
            await store.startMonitoringIfNeeded()
        }
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
        value.count <= 30 ? value : String(value.prefix(27)) + "…"
    }
}
