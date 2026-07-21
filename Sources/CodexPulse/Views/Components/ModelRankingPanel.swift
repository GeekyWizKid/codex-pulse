import SwiftUI

struct ModelRankingPanel: View {
    let models: [DashboardModel]
    let sourceStatus: String

    var body: some View {
        PulsePanel {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("模型智商")
                            .font(.headline)
                        Text("CodexRadar · \(sourceStatus)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("IQ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(18)

                Divider().opacity(0.5)

                if models.isEmpty {
                    ContentUnavailableView(
                        "榜单暂不可用",
                        systemImage: "brain.head.profile",
                        description: Text("CodexRadar 恢复后会自动重试")
                    )
                    .frame(maxWidth: .infinity, minHeight: 210)
                } else {
                    ForEach(Array(models.prefix(5).enumerated()), id: \.element.id) { index, model in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.callout.weight(.bold).monospacedDigit())
                                .foregroundStyle(rankColor(index))
                                .frame(width: 18)

                            Image(systemName: "cpu")
                                .font(.caption)
                                .foregroundStyle(rankColor(index))
                                .frame(width: 22, height: 22)
                                .background(rankColor(index).opacity(0.12), in: RoundedRectangle(cornerRadius: 5))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.model)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                Text(model.effort)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(model.liveIQ, format: .number.precision(.fractionLength(1)))
                                .font(.callout.weight(.semibold).monospacedDigit())
                                .foregroundStyle(rankColor(index))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)

                        if index < min(models.count, 5) - 1 {
                            Divider().opacity(0.4).padding(.leading, 18)
                        }
                    }
                }

                Divider().opacity(0.5)
                Link(destination: URL(string: "https://codexradar.com")!) {
                    Label("打开 CodexRadar", systemImage: "arrow.up.right.square")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(PulseTheme.cyan)
                .padding(14)
            }
        }
    }

    private func rankColor(_ index: Int) -> Color {
        switch index {
        case 0: PulseTheme.mint
        case 1: PulseTheme.cyan
        case 2: PulseTheme.violet
        default: .secondary
        }
    }
}
