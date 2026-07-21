import Foundation

enum SidebarDestination: String, CaseIterable, Identifiable, Hashable {
    case overview
    case projects
    case time
    case modelIntelligence

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "总览"
        case .projects: "项目"
        case .time: "时间"
        case .modelIntelligence: "模型智商"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "house"
        case .projects: "folder"
        case .time: "clock"
        case .modelIntelligence: "brain"
        }
    }
}

enum DashboardRange: String, CaseIterable, Identifiable {
    case today
    case sevenDays
    case thirtyDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今天"
        case .sevenDays: "7 天"
        case .thirtyDays: "30 天"
        }
    }

    var startDate: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        switch self {
        case .today:
            return today
        case .sevenDays:
            return calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .thirtyDays:
            return calendar.date(byAdding: .day, value: -29, to: today) ?? today
        }
    }
}

struct UsageChartPoint: Identifiable, Hashable {
    let date: Date
    let tokens: Int
    let kind: Kind

    var id: String { "\(kind.rawValue)-\(date.timeIntervalSince1970)" }

    enum Kind: String, Hashable {
        case actual
        case forecast
    }
}

enum DataFreshness: Equatable {
    case loading
    case fresh(Date)
    case stale(Date, message: String)
    case unavailable(String)
}
