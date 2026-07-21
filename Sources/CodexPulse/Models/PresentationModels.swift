import Foundation

struct DashboardProject: Identifiable, Hashable {
    let id: String
    let name: String
    let activeDuration: TimeInterval
    let sessions: Int
    let tokens: Int
    let inputTokens: Int
    let cachedTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let share: Double
    let isActive: Bool
    let lastActiveAt: Date?
    let models: [String]
}

struct DashboardModel: Identifiable, Hashable {
    var id: String { "\(model)|\(effort)" }
    let model: String
    let effort: String
    let liveIQ: Double
    let recentIQ: Double
    let longTermIQ: Double
    let coverage: Double
    let samples: Int
    let meanDuration: TimeInterval?
    let meanCost: Double?
}

struct DashboardQuota: Identifiable, Hashable {
    let id: String
    let title: String
    let usedPercent: Double?
    let windowMinutes: Int?
    let resetAt: Date?

    var remainingPercent: Double? {
        usedPercent.map { max(0, min(100, 100 - $0)) }
    }
}

struct DashboardUsage {
    var generatedAt: Date?
    var tokens: Int = 0
    var inputTokens: Int = 0
    var cachedTokens: Int = 0
    var outputTokens: Int = 0
    var reasoningTokens: Int = 0
    var activeDuration: TimeInterval = 0
    var sessions: Int = 0
    var activeSessions: Int = 0
    var projects: [DashboardProject] = []
    var chartPoints: [UsageChartPoint] = []
    var models: [DashboardModel] = []
    var quotas: [DashboardQuota] = []
    var lifetimeTokens: Int?
    var currentStreakDays: Int?
    var dataSourceLabel: String = "本地 Codex 日志"
}

struct DailyUsagePoint: Identifiable, Hashable {
    let date: Date
    let tokens: Int
    let activeDuration: TimeInterval

    var id: Date { date }
}

enum LoadStatus: Equatable {
    case idle
    case loading(String)
    case ready(Date)
    case degraded(String, Date?)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var conciseLabel: String {
        switch self {
        case .idle: "尚未加载"
        case .loading(let message): message
        case .ready: "实时"
        case .degraded(let message, _): message
        }
    }
}
