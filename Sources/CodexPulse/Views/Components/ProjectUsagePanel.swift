import SwiftUI

struct ProjectUsagePanel: View {
    let projects: [DashboardProject]
    let totalTokens: Int

    var body: some View {
        PulsePanel {
            VStack(alignment: .leading, spacing: 0) {
                Text("项目使用情况")
                    .font(.headline)
                    .padding(18)

                tableHeader
                Divider().opacity(0.6)

                if projects.isEmpty {
                    ContentUnavailableView(
                        "没有找到项目数据",
                        systemImage: "folder.badge.questionmark",
                        description: Text("检查 ~/.codex 是否包含可读取的会话")
                    )
                    .frame(maxWidth: .infinity, minHeight: 210)
                } else {
                    ForEach(Array(projects.prefix(6).enumerated()), id: \.element.id) { index, project in
                        projectRow(project)
                        if index < min(projects.count, 6) - 1 {
                            Divider().opacity(0.45)
                        }
                    }
                }

                Divider().opacity(0.6)
                HStack {
                    Text("总计")
                    Spacer()
                    Text("\(projects.reduce(0) { $0 + $1.sessions }) 个会话")
                    Text(PulseFormatters.tokens(totalTokens))
                        .frame(width: 92, alignment: .trailing)
                    Text("100%")
                        .frame(width: 64, alignment: .trailing)
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
            }
            .frame(maxWidth: .infinity, minHeight: 390, alignment: .top)
        }
    }

    private var tableHeader: some View {
        HStack {
            Text("项目")
            Spacer()
            Text("活跃时长")
                .frame(width: 108, alignment: .leading)
            Text("会话")
                .frame(width: 56, alignment: .trailing)
            Text("Tokens")
                .frame(width: 92, alignment: .trailing)
            Text("占比")
                .frame(width: 64, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private func projectRow(_ project: DashboardProject) -> some View {
        HStack(spacing: 10) {
            Image(systemName: project.isActive ? "terminal.fill" : "folder")
                .foregroundStyle(project.isActive ? PulseTheme.mint : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if project.isActive {
                    LiveStatusLabel(isLive: true, title: "活跃")
                        .scaleEffect(0.86, anchor: .leading)
                }
            }

            Spacer(minLength: 8)

            Text(PulseFormatters.duration(project.activeDuration))
                .font(.caption)
                .frame(width: 108, alignment: .leading)
            Text(project.sessions.formatted())
                .font(.caption.monospacedDigit())
                .frame(width: 56, alignment: .trailing)
            Text(PulseFormatters.tokens(project.tokens))
                .font(.caption.monospacedDigit())
                .frame(width: 92, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 4) {
                Text(project.share, format: .percent.precision(.fractionLength(1)))
                    .font(.caption.monospacedDigit())
                ProgressView(value: project.share)
                    .tint(PulseTheme.mint)
                    .frame(width: 54)
            }
            .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}
