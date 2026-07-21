import Foundation

enum PulseFormatters {
    static let compactNumber: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static func tokens(_ value: Int) -> String {
        let magnitude = abs(value)
        if magnitude >= 1_000_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000)
        }
        if magnitude >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return value.formatted()
    }

    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 分钟" }
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 { return "\(hours) 小时 \(minutes) 分" }
        if hours > 0 { return "\(hours) 小时" }
        return "\(max(minutes, 1)) 分钟"
    }

    static func countdown(to date: Date?, now: Date = Date()) -> String {
        guard let date else { return "未知" }
        let remaining = max(0, Int(date.timeIntervalSince(now)))
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        return "\(minutes) 分钟"
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh-Hans")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
