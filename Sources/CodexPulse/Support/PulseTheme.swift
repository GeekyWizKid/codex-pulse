import SwiftUI

enum PulseTheme {
    // Graphite Instrument: a quiet system-first palette with one blue accent.
    static let background = Color(red: 0.055, green: 0.063, blue: 0.073)
    static let detailBackground = Color(red: 0.065, green: 0.073, blue: 0.083)
    static let panel = Color.white.opacity(0.035)
    static let panelHighlight = Color.white.opacity(0.065)
    static let border = Color.white.opacity(0.12)
    static let grid = Color.white.opacity(0.085)
    static let accent = Color(red: 0.25, green: 0.53, blue: 1.0)
    static let success = Color(red: 0.18, green: 0.78, blue: 0.48)
    static let warning = Color(red: 0.96, green: 0.66, blue: 0.18)
    static let danger = Color(red: 0.96, green: 0.35, blue: 0.33)

    // Compatibility aliases for the few legacy components that remain available.
    static let mint = success
    static let cyan = accent
    static let violet = Color(red: 0.58, green: 0.48, blue: 0.96)
    static let amber = warning
}

struct PulsePanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(PulseTheme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .fill(isLive ? PulseTheme.success : PulseTheme.warning)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(isLive ? PulseTheme.success : .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
