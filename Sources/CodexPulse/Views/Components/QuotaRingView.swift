import SwiftUI

struct QuotaRingView: View {
    let title: String
    let usedPercent: Double?
    let resetDate: Date?
    let detail: String
    let accent: Color

    private var normalized: Double {
        min(max((usedPercent ?? 0) / 100, 0), 1)
    }

    var body: some View {
        PulsePanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("额度由 Codex 官方本地服务提供")
                }

                HStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.10), lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: normalized)
                            .stroke(accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(usedPercent.map { "\(Int($0.rounded()))%" } ?? "—")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .frame(width: 104, height: 104)
                    .accessibilityLabel("\(title)已使用")
                    .accessibilityValue(usedPercent.map { "\(Int($0.rounded()))%" } ?? "不可用")

                    VStack(alignment: .leading, spacing: 7) {
                        Text("已使用")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(usedPercent.map { "\(Int($0.rounded()))%" } ?? "等待数据")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(accent)
                            .monospacedDigit()
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Label("重置倒计时  \(PulseFormatters.countdown(to: resetDate))", systemImage: "stopwatch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(18)
        }
    }
}
