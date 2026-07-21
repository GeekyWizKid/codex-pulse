import Foundation

/// The ChatGPT plan reported by `codex app-server`.
///
/// `other` intentionally preserves values introduced by newer Codex versions so an
/// older CodexPulse build can keep displaying useful account data.
public enum CodexPlanType: Hashable, Sendable {
    case free
    case go
    case plus
    case pro
    case prolite
    case team
    case selfServeBusinessUsageBased
    case business
    case enterpriseCBPUsageBased
    case enterprise
    case edu
    case unknown
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "free": self = .free
        case "go": self = .go
        case "plus": self = .plus
        case "pro": self = .pro
        case "prolite": self = .prolite
        case "team": self = .team
        case "self_serve_business_usage_based": self = .selfServeBusinessUsageBased
        case "business": self = .business
        case "enterprise_cbp_usage_based": self = .enterpriseCBPUsageBased
        case "enterprise": self = .enterprise
        case "edu": self = .edu
        case "unknown": self = .unknown
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .free: "free"
        case .go: "go"
        case .plus: "plus"
        case .pro: "pro"
        case .prolite: "prolite"
        case .team: "team"
        case .selfServeBusinessUsageBased: "self_serve_business_usage_based"
        case .business: "business"
        case .enterpriseCBPUsageBased: "enterprise_cbp_usage_based"
        case .enterprise: "enterprise"
        case .edu: "edu"
        case .unknown: "unknown"
        case let .other(value): value
        }
    }
}

extension CodexPlanType: Codable {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A rolling quota window returned by `account/rateLimits/read`.
public struct CodexQuotaWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let windowDurationMins: Int?
    public let resetsAt: Date?

    public init(usedPercent: Double, windowDurationMins: Int?, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }

    /// Remaining quota, clamped for display even if an upstream value is briefly
    /// below zero or above 100 while the service reconciles usage.
    public var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }

    public var windowDuration: TimeInterval? {
        windowDurationMins.map { TimeInterval($0) * 60 }
    }

    private enum CodingKeys: String, CodingKey {
        case usedPercent
        case windowDurationMins
        case resetsAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try container.decode(Double.self, forKey: .usedPercent)
        windowDurationMins = try container.decodeIfPresent(Int.self, forKey: .windowDurationMins)
        resetsAt = try container.decodeIfPresent(TimeInterval.self, forKey: .resetsAt)
            .map(Date.init(timeIntervalSince1970:))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(usedPercent, forKey: .usedPercent)
        try container.encodeIfPresent(windowDurationMins, forKey: .windowDurationMins)
        try container.encodeIfPresent(resetsAt?.timeIntervalSince1970, forKey: .resetsAt)
    }

    /// Applies a sparse notification without erasing window metadata omitted by
    /// the notification.
    public func merging(_ sparseUpdate: CodexQuotaWindow) -> CodexQuotaWindow {
        CodexQuotaWindow(
            usedPercent: sparseUpdate.usedPercent,
            windowDurationMins: sparseUpdate.windowDurationMins ?? windowDurationMins,
            resetsAt: sparseUpdate.resetsAt ?? resetsAt
        )
    }
}

public struct CodexCreditsSnapshot: Codable, Equatable, Sendable {
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: String?

    public init(hasCredits: Bool, unlimited: Bool, balance: String?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }

    public func merging(_ sparseUpdate: CodexCreditsSnapshot) -> CodexCreditsSnapshot {
        CodexCreditsSnapshot(
            hasCredits: sparseUpdate.hasCredits,
            unlimited: sparseUpdate.unlimited,
            balance: sparseUpdate.balance ?? balance
        )
    }
}

public struct CodexSpendControlLimit: Codable, Equatable, Sendable {
    public let limit: String
    public let used: String
    public let remainingPercent: Double
    public let resetsAt: Date

    public init(limit: String, used: String, remainingPercent: Double, resetsAt: Date) {
        self.limit = limit
        self.used = used
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }

    private enum CodingKeys: String, CodingKey {
        case limit
        case used
        case remainingPercent
        case resetsAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limit = try container.decode(String.self, forKey: .limit)
        used = try container.decode(String.self, forKey: .used)
        remainingPercent = try container.decode(Double.self, forKey: .remainingPercent)
        resetsAt = Date(timeIntervalSince1970: try container.decode(TimeInterval.self, forKey: .resetsAt))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(limit, forKey: .limit)
        try container.encode(used, forKey: .used)
        try container.encode(remainingPercent, forKey: .remainingPercent)
        try container.encode(resetsAt.timeIntervalSince1970, forKey: .resetsAt)
    }
}

public struct CodexRateLimitSnapshot: Codable, Equatable, Sendable {
    public let limitID: String?
    public let limitName: String?
    public let primary: CodexQuotaWindow?
    public let secondary: CodexQuotaWindow?
    public let credits: CodexCreditsSnapshot?
    public let individualLimit: CodexSpendControlLimit?
    public let planType: CodexPlanType?
    public let rateLimitReachedType: String?

    public init(
        limitID: String? = nil,
        limitName: String? = nil,
        primary: CodexQuotaWindow? = nil,
        secondary: CodexQuotaWindow? = nil,
        credits: CodexCreditsSnapshot? = nil,
        individualLimit: CodexSpendControlLimit? = nil,
        planType: CodexPlanType? = nil,
        rateLimitReachedType: String? = nil
    ) {
        self.limitID = limitID
        self.limitName = limitName
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.individualLimit = individualLimit
        self.planType = planType
        self.rateLimitReachedType = rateLimitReachedType
    }

    private enum CodingKeys: String, CodingKey {
        case limitID = "limitId"
        case limitName
        case primary
        case secondary
        case credits
        case individualLimit
        case planType
        case rateLimitReachedType
    }

    /// `account/rateLimits/updated` is explicitly sparse. Nil values therefore
    /// mean "not supplied" and must not erase a value from the latest full read.
    public func merging(_ sparseUpdate: CodexRateLimitSnapshot) -> CodexRateLimitSnapshot {
        CodexRateLimitSnapshot(
            limitID: sparseUpdate.limitID ?? limitID,
            limitName: sparseUpdate.limitName ?? limitName,
            primary: Self.merge(primary, sparseUpdate.primary),
            secondary: Self.merge(secondary, sparseUpdate.secondary),
            credits: Self.merge(credits, sparseUpdate.credits),
            individualLimit: sparseUpdate.individualLimit ?? individualLimit,
            planType: sparseUpdate.planType ?? planType,
            rateLimitReachedType: sparseUpdate.rateLimitReachedType ?? rateLimitReachedType
        )
    }

    private static func merge(
        _ current: CodexQuotaWindow?,
        _ update: CodexQuotaWindow?
    ) -> CodexQuotaWindow? {
        guard let update else { return current }
        return current?.merging(update) ?? update
    }

    private static func merge(
        _ current: CodexCreditsSnapshot?,
        _ update: CodexCreditsSnapshot?
    ) -> CodexCreditsSnapshot? {
        guard let update else { return current }
        return current?.merging(update) ?? update
    }
}

public struct CodexRateLimitResetCredit: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let resetType: String
    public let status: String
    public let grantedAt: Date
    public let expiresAt: Date?
    public let title: String?
    public let description: String?

    private enum CodingKeys: String, CodingKey {
        case id, resetType, status, grantedAt, expiresAt, title, description
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        resetType = try container.decode(String.self, forKey: .resetType)
        status = try container.decode(String.self, forKey: .status)
        grantedAt = Date(timeIntervalSince1970: try container.decode(TimeInterval.self, forKey: .grantedAt))
        expiresAt = try container.decodeIfPresent(TimeInterval.self, forKey: .expiresAt)
            .map(Date.init(timeIntervalSince1970:))
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(resetType, forKey: .resetType)
        try container.encode(status, forKey: .status)
        try container.encode(grantedAt.timeIntervalSince1970, forKey: .grantedAt)
        try container.encodeIfPresent(expiresAt?.timeIntervalSince1970, forKey: .expiresAt)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
    }
}

public struct CodexRateLimitResetCreditsSummary: Codable, Equatable, Sendable {
    public let availableCount: UInt64
    public let credits: [CodexRateLimitResetCredit]?
}

/// Full response from `account/rateLimits/read`.
public struct CodexAccountRateLimitsResponse: Codable, Equatable, Sendable {
    public let rateLimits: CodexRateLimitSnapshot
    public let rateLimitsByLimitID: [String: CodexRateLimitSnapshot]?
    public let rateLimitResetCredits: CodexRateLimitResetCreditsSummary?

    private enum CodingKeys: String, CodingKey {
        case rateLimits
        case rateLimitsByLimitID = "rateLimitsByLimitId"
        case rateLimitResetCredits
    }
}

public struct CodexAccountUsageSummary: Codable, Equatable, Sendable {
    public let lifetimeTokens: UInt64?
    public let peakDailyTokens: UInt64?
    public let longestRunningTurnSec: UInt64?
    public let currentStreakDays: UInt64?
    public let longestStreakDays: UInt64?

    public init(
        lifetimeTokens: UInt64? = nil,
        peakDailyTokens: UInt64? = nil,
        longestRunningTurnSec: UInt64? = nil,
        currentStreakDays: UInt64? = nil,
        longestStreakDays: UInt64? = nil
    ) {
        self.lifetimeTokens = lifetimeTokens
        self.peakDailyTokens = peakDailyTokens
        self.longestRunningTurnSec = longestRunningTurnSec
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
    }
}

public struct CodexDailyUsageBucket: Codable, Equatable, Sendable, Identifiable {
    /// ISO calendar day (`YYYY-MM-DD`) as returned by Codex.
    public let startDate: String
    public let tokens: UInt64

    public var id: String { startDate }

    public init(startDate: String, tokens: UInt64) {
        self.startDate = startDate
        self.tokens = tokens
    }

    public var date: Date? {
        guard startDate.count == 10 else { return nil }
        let parts = startDate.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

/// Full response from `account/usage/read`.
public struct CodexAccountUsageResponse: Codable, Equatable, Sendable {
    public let summary: CodexAccountUsageSummary
    public let dailyUsageBuckets: [CodexDailyUsageBucket]?
}

public struct AccountUsageSnapshot: Equatable, Sendable {
    public var rateLimits: CodexRateLimitSnapshot?
    public var rateLimitsByLimitID: [String: CodexRateLimitSnapshot]
    public var rateLimitResetCredits: CodexRateLimitResetCreditsSummary?
    public var summary: CodexAccountUsageSummary?
    public var dailyUsageBuckets: [CodexDailyUsageBucket]
    public var lastUpdatedAt: Date?

    public init(
        rateLimits: CodexRateLimitSnapshot? = nil,
        rateLimitsByLimitID: [String: CodexRateLimitSnapshot] = [:],
        rateLimitResetCredits: CodexRateLimitResetCreditsSummary? = nil,
        summary: CodexAccountUsageSummary? = nil,
        dailyUsageBuckets: [CodexDailyUsageBucket] = [],
        lastUpdatedAt: Date? = nil
    ) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitID = rateLimitsByLimitID
        self.rateLimitResetCredits = rateLimitResetCredits
        self.summary = summary
        self.dailyUsageBuckets = dailyUsageBuckets
        self.lastUpdatedAt = lastUpdatedAt
    }

    public static let empty = AccountUsageSnapshot()

    public mutating func apply(
        rateLimits response: CodexAccountRateLimitsResponse,
        usage: CodexAccountUsageResponse,
        observedAt: Date
    ) {
        rateLimits = response.rateLimits
        rateLimitsByLimitID = response.rateLimitsByLimitID ?? [:]
        rateLimitResetCredits = response.rateLimitResetCredits
        summary = usage.summary
        dailyUsageBuckets = usage.dailyUsageBuckets ?? []
        lastUpdatedAt = observedAt
    }

    public mutating func mergeSparseRateLimitUpdate(
        _ update: CodexRateLimitSnapshot,
        observedAt: Date
    ) {
        let resolvedLimitID = update.limitID ?? rateLimits?.limitID
        rateLimits = rateLimits?.merging(update) ?? update

        if let limitID = resolvedLimitID {
            rateLimitsByLimitID[limitID] = rateLimitsByLimitID[limitID]?.merging(update) ?? update
        }
        lastUpdatedAt = observedAt
    }
}
