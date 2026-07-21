import SwiftUI

enum PulseTheme {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.075)
    static let detailBackground = Color(red: 0.045, green: 0.070, blue: 0.092)
    static let panel = Color(red: 0.075, green: 0.105, blue: 0.130)
    static let panelHighlight = Color(red: 0.095, green: 0.130, blue: 0.155)
    static let border = Color.white.opacity(0.10)
    static let grid = Color.white.opacity(0.075)
    static let mint = Color(red: 0.18, green: 0.88, blue: 0.70)
    static let cyan = Color(red: 0.26, green: 0.64, blue: 1.0)
    static let violet = Color(red: 0.62, green: 0.45, blue: 0.98)
    static let amber = Color(red: 1.0, green: 0.76, blue: 0.12)
    static let danger = Color(red: 1.0, green: 0.34, blue: 0.34)
}

struct PulsePanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(PulseTheme.panel.opacity(0.88), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(PulseTheme.border, lineWidth: 1)
            }
    }
}

struct LiveStatusLabel: View {
    let isLive: Bool
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isLive ? PulseTheme.mint : PulseTheme.amber)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(isLive ? PulseTheme.mint : .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
