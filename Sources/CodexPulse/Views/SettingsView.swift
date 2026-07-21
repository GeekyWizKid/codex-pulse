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
            Form {
                Section("刷新") {
                    Picker("本地数据", selection: $localRefreshInterval) {
                        Text("5 秒").tag(5.0)
                        Text("10 秒").tag(10.0)
                        Text("30 秒").tag(30.0)
                        Text("1 分钟").tag(60.0)
                    }
                    Text("CodexRadar 固定每 60 秒刷新；窗口退到后台时暂停。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("显示") {
                    Toggle("在菜单栏显示剩余百分比", isOn: $showMenuBarPercentage)
                    Toggle("显示按当前速度的用量预测", isOn: $enableForecast)
                    HStack {
                        Text("低额度提示")
                        Slider(value: $quotaWarningThreshold, in: 5...50, step: 5)
                        Text("\(Int(quotaWarningThreshold))%")
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                }

                Section {
                    Button("立即刷新") {
                        Task { await store.refreshAll(force: true) }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gearshape") }

            Form {
                Section("本地数据源") {
                    LabeledContent("目录", value: "~/.codex")
                    LabeledContent("模式", value: "只读 · 增量扫描")
                    LabeledContent("提示词与回复", value: "永不读取")
                    LabeledContent("认证文件", value: "永不读取")
                    Button("在 Finder 中显示 ~/.codex") {
                        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }

                Section("网络") {
                    LabeledContent("Codex 官方额度", value: "本机 app-server")
                    LabeledContent("模型智商", value: "api.codexradar.com")
                    Text("只下载公共榜单，不会上传项目名、路径、会话 ID 或个人用量。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("隐私", systemImage: "hand.raised.fill") }

            VStack(spacing: 15) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(PulseTheme.mint)
                Text("Codex Pulse")
                    .font(.title2.weight(.semibold))
                Text("版本 1.0.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("本地优先的 Codex 用量、时间与模型能力控制台。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Link("查看 CodexRadar", destination: URL(string: "https://codexradar.com")!)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(30)
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 410)
        .preferredColorScheme(.dark)
    }
}
