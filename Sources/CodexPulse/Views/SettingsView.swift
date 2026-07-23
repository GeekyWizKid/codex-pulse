import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @AppStorage("localRefreshInterval") private var localRefreshInterval = 10.0
    @AppStorage("showMenuBarPercentage") private var showMenuBarPercentage = true
    @AppStorage("enableForecast") private var enableForecast = true
    @AppStorage("quotaWarningThreshold") private var quotaWarningThreshold = 20.0

    var body: some View {
        TabView {
            general
                .tabItem { Label("通用", systemImage: "gearshape") }

            privacy
                .tabItem { Label("隐私", systemImage: "hand.raised") }

            about
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 550, height: 400)
        .preferredColorScheme(.dark)
    }

    private var general: some View {
        Form {
            Section("更新") {
                Picker("本地数据刷新", selection: $localRefreshInterval) {
                    Text("5 秒").tag(5.0)
                    Text("10 秒").tag(10.0)
                    Text("30 秒").tag(30.0)
                    Text("1 分钟").tag(60.0)
                }

                LabeledContent("公共模型榜单", value: "每 60 秒")

                Button("立即刷新") {
                    Task { await store.refreshAll(force: true) }
                }
                .disabled(store.status.isLoading)
            }

            Section("菜单栏与预测") {
                Toggle("在菜单栏显示剩余百分比", isOn: $showMenuBarPercentage)
                Toggle("显示当前速度预测", isOn: $enableForecast)

                LabeledContent("低额度提醒阈值") {
                    HStack(spacing: 10) {
                        Slider(value: $quotaWarningThreshold, in: 5...50, step: 5)
                            .frame(width: 170)
                        Text("\(Int(quotaWarningThreshold))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }

            Section {
                Text("刷新频率会用于本地增量扫描；提醒阈值会同步到菜单栏额度状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var privacy: some View {
        Form {
            Section("本地数据") {
                LabeledContent("目录", value: "~/.codex")
                LabeledContent("读取方式", value: "只读 · 增量")
                LabeledContent("提示词与回复", value: "不读取")
                LabeledContent("认证文件", value: "不读取")

                Button("在 Finder 中显示") {
                    let url = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".codex")
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }

            Section("网络访问") {
                LabeledContent("Codex 官方额度", value: "本机 app-server")
                LabeledContent("模型智商", value: "api.codexradar.com")

                Text("CodexRadar 只下载公共榜单。项目名、路径、会话 ID 与个人用量不会上传。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        Form {
            Section {
                LabeledContent {
                    Text(versionLabel)
                        .foregroundStyle(.secondary)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Codex Pulse")
                                .font(.headline)
                            Text("本地优先的 Codex 用量控制台")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundStyle(PulseTheme.cyan)
                    }
                }
            }

            Section("数据说明") {
                Text("用量与时间来自本机 Codex 数据；模型智能来自 CodexRadar 公共榜单。")
                    .foregroundStyle(.secondary)

                Link("打开 CodexRadar", destination: URL(string: "https://codexradar.com")!)
                Link(
                    "查看模型智能 API",
                    destination: URL(string: "https://api.codexradar.com/api/v1/table")!
                )
            }
        }
        .formStyle(.grouped)
    }

    private var versionLabel: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "开发版"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        guard let build, !build.isEmpty else {
            return "版本 \(version)"
        }

        return "版本 \(version) (\(build))"
    }
}
