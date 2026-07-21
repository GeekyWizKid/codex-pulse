import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarDestination?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(PulseTheme.mint)
                    .symbolEffect(.variableColor.iterative, options: .repeating.speed(0.25))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex Pulse")
                        .font(.title3.weight(.semibold))
                    Text("Command Center")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 14)

            List(selection: $selection) {
                ForEach(SidebarDestination.allCases) { destination in
                    Label(destination.title, systemImage: destination.systemImage)
                        .tag(destination)
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("sidebar.\(destination.rawValue)")
                }

                SettingsLink {
                    Label("设置", systemImage: "gearshape")
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.clear)

            VStack(spacing: 10) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(PulseTheme.mint)
                        .frame(width: 7, height: 7)
                    Text("数据仅在本机分析")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Image(systemName: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("不读取提示词、回复或认证文件")
                }
            }
            .padding(16)
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        .background(PulseTheme.background)
    }
}
