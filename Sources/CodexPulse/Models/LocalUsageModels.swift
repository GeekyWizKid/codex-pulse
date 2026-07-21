import Foundation

/// A privacy-safe token breakdown. Cached-input and reasoning tokens are
/// subsets of input and output respectively, so `total` is kept independently
/// instead of being recomputed by summing every field.
public struct LocalTokenUsage: Codable, Equatable, Sendable {
    public var input: Int64
    public var cachedInput: Int64
    public var output: Int64
    public var reasoning: Int64
    public var total: Int64

    public init(
        input: Int64 = 0,
        cachedInput: Int64 = 0,
        output: Int64 = 0,
        reasoning: Int64 = 0,
        total: Int64 = 0
    ) {
        self.input = max(0, input)
        self.cachedInput = max(0, cachedInput)
        self.output = max(0, output)
        self.reasoning = max(0, reasoning)
        self.total = max(0, total)
    }
}

public struct LocalSessionUsageSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let threadID: String
    public let projectName: String
    public let startedAt: Date?
    public let endedAt: Date?
    public let lastEventAt: Date?
    public let actualTaskDuration: TimeInterval
    public let completedTaskCount: Int
    public let abortedTaskCount: Int
    public let isActive: Bool
    public let tokens: LocalTokenUsage

    public init(
        id: String,
        threadID: String,
        projectName: String,
        startedAt: Date?,
        endedAt: Date?,
        lastEventAt: Date?,
        actualTaskDuration: TimeInterval,
        completedTaskCount: Int,
        abortedTaskCount: Int,
        isActive: Bool,
        tokens: LocalTokenUsage
    ) {
        self.id = id
        self.threadID = threadID
        self.projectName = projectName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lastEventAt = lastEventAt
        self.actualTaskDuration = max(0, actualTaskDuration)
        self.completedTaskCount = max(0, completedTaskCount)
        self.abortedTaskCount = max(0, abortedTaskCount)
        self.isActive = isActive
        self.tokens = tokens
    }
}

public struct LocalThreadUsageSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let projectName: String
    public let createdAt: Date
    public let updatedAt: Date
    public let model: String?
    public let isArchived: Bool
    public let databaseTokenCount: Int64
    public let tokens: LocalTokenUsage
    public let actualTaskDuration: TimeInterval
    public let sessions: [LocalSessionUsageSummary]
    public let isActive: Bool

    public init(
        id: String,
        projectName: String,
        createdAt: Date,
        updatedAt: Date,
        model: String?,
        isArchived: Bool,
        databaseTokenCount: Int64,
        tokens: LocalTokenUsage,
        actualTaskDuration: TimeInterval,
        sessions: [LocalSessionUsageSummary],
        isActive: Bool
    ) {
        self.id = id
        self.projectName = projectName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.model = model
        self.isArchived = isArchived
        self.databaseTokenCount = max(0, databaseTokenCount)
        self.tokens = tokens
        self.actualTaskDuration = max(0, actualTaskDuration)
        self.sessions = sessions
        self.isActive = isActive
    }
}

public struct LocalProjectUsageSummary: Codable, Equatable, Identifiable, Sendable {
    /// Projects are intentionally grouped only by the final component of cwd.
    /// This avoids surfacing the user's full directory hierarchy to the UI.
    public var id: String { name }

    public let name: String
    public let threadCount: Int
    public let sessionCount: Int
    public let activeThreadCount: Int
    public let models: [String]
    public let latestActivityAt: Date?
    public let actualTaskDuration: TimeInterval
    public let tokens: LocalTokenUsage

    public init(
        name: String,
        threadCount: Int,
        sessionCount: Int,
        activeThreadCount: Int,
        models: [String],
        latestActivityAt: Date?,
        actualTaskDuration: TimeInterval,
        tokens: LocalTokenUsage
    ) {
        self.name = name
        self.threadCount = max(0, threadCount)
        self.sessionCount = max(0, sessionCount)
        self.activeThreadCount = max(0, activeThreadCount)
        self.models = models
        self.latestActivityAt = latestActivityAt
        self.actualTaskDuration = max(0, actualTaskDuration)
        self.tokens = tokens
    }
}

/// A calendar-day bucket made only from timestamps carried by usage/task
/// events. Thread `updated_at` is deliberately never used for this timeline.
public struct LocalDailyUsageBucket: Codable, Equatable, Identifiable, Sendable {
    public var id: Date { date }

    /// Start of day in the scanner's current calendar/time zone.
    public let date: Date
    public let tokens: LocalTokenUsage
    public let actualTaskDuration: TimeInterval

    public init(date: Date, tokens: LocalTokenUsage, actualTaskDuration: TimeInterval) {
        self.date = date
        self.tokens = tokens
        self.actualTaskDuration = max(0, actualTaskDuration)
    }
}

/// An absolute local-clock hour bucket suitable for honest today/7d/30d
/// filtering. It is not an hour-of-day histogram.
public struct LocalHourlyUsageBucket: Codable, Equatable, Identifiable, Sendable {
    public var id: Date { date }

    /// Start of the represented hour in the scanner's current calendar.
    public let date: Date
    public let tokens: LocalTokenUsage
    public let actualTaskDuration: TimeInterval

    public init(date: Date, tokens: LocalTokenUsage, actualTaskDuration: TimeInterval) {
        self.date = date
        self.tokens = tokens
        self.actualTaskDuration = max(0, actualTaskDuration)
    }
}

public struct LocalCurrentActivitySummary: Codable, Equatable, Sendable {
    public let isActive: Bool
    public let activeThreadCount: Int
    public let activeProjectNames: [String]
    public let activeThreadIDs: [String]
    public let activeSince: Date?
    public let lastEventAt: Date?

    public init(
        isActive: Bool,
        activeThreadCount: Int,
        activeProjectNames: [String],
        activeThreadIDs: [String],
        activeSince: Date?,
        lastEventAt: Date?
    ) {
        self.isActive = isActive
        self.activeThreadCount = max(0, activeThreadCount)
        self.activeProjectNames = activeProjectNames
        self.activeThreadIDs = activeThreadIDs
        self.activeSince = activeSince
        self.lastEventAt = lastEventAt
    }
}

public struct LocalUsageSnapshot: Codable, Equatable, Sendable {
    public let scannedAt: Date
    /// Only the database filename is exposed; no home-directory path is stored.
    public let stateDatabaseName: String
    public let threads: [LocalThreadUsageSummary]
    public let projects: [LocalProjectUsageSummary]
    public let tokens: LocalTokenUsage
    public let sessionCount: Int
    public let actualTaskDuration: TimeInterval
    public let currentActivity: LocalCurrentActivitySummary
    public let dailyUsage: [LocalDailyUsageBucket]
    public let hourlyUsage: [LocalHourlyUsageBucket]
    /// All scanned event history grouped by local hour of day. Index 0 is
    /// 00:00-00:59; use `hourlyUsage` for date-range filtering.
    public let hourlyTokenTotals: [Int64]
    public let cacheHitCount: Int
    public let scannedJSONLCount: Int
    public let skippedJSONLCount: Int

    public init(
        scannedAt: Date,
        stateDatabaseName: String,
        threads: [LocalThreadUsageSummary],
        projects: [LocalProjectUsageSummary],
        tokens: LocalTokenUsage,
        sessionCount: Int,
        actualTaskDuration: TimeInterval,
        currentActivity: LocalCurrentActivitySummary,
        dailyUsage: [LocalDailyUsageBucket],
        hourlyUsage: [LocalHourlyUsageBucket],
        hourlyTokenTotals: [Int64],
        cacheHitCount: Int,
        scannedJSONLCount: Int,
        skippedJSONLCount: Int
    ) {
        self.scannedAt = scannedAt
        self.stateDatabaseName = stateDatabaseName
        self.threads = threads
        self.projects = projects
        self.tokens = tokens
        self.sessionCount = max(0, sessionCount)
        self.actualTaskDuration = max(0, actualTaskDuration)
        self.currentActivity = currentActivity
        self.dailyUsage = dailyUsage
        self.hourlyUsage = hourlyUsage
        self.hourlyTokenTotals = Array(hourlyTokenTotals.prefix(24))
            + Array(repeating: 0, count: max(0, 24 - hourlyTokenTotals.count))
        self.cacheHitCount = max(0, cacheHitCount)
        self.scannedJSONLCount = max(0, scannedJSONLCount)
        self.skippedJSONLCount = max(0, skippedJSONLCount)
    }
}

public struct LocalScanProgress: Equatable, Sendable {
    public enum Phase: String, Equatable, Sendable {
        case locatingDatabase
        case readingThreads
        case scanningRollouts
        case aggregating
        case finished
    }

    public let phase: Phase
    public let completed: Int
    public let total: Int

    public init(phase: Phase, completed: Int, total: Int) {
        self.phase = phase
        self.completed = max(0, completed)
        self.total = max(0, total)
    }
}

public enum LocalCodexScannerError: Error, Equatable, LocalizedError, Sendable {
    case stateDatabaseNotFound
    case databaseOpenFailed(String)
    case databaseQueryFailed(String)
    case cacheWriteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .stateDatabaseNotFound:
            return "No Codex state database was found."
        case .databaseOpenFailed(let message):
            return "The Codex state database could not be opened read-only: \(message)"
        case .databaseQueryFailed(let message):
            return "The Codex thread metadata query failed: \(message)"
        case .cacheWriteFailed(let message):
            return "The privacy-safe local usage cache could not be written: \(message)"
        }
    }
}

extension LocalTokenUsage {
    static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            input: lhs.input.saturatedAdding(rhs.input),
            cachedInput: lhs.cachedInput.saturatedAdding(rhs.cachedInput),
            output: lhs.output.saturatedAdding(rhs.output),
            reasoning: lhs.reasoning.saturatedAdding(rhs.reasoning),
            total: lhs.total.saturatedAdding(rhs.total)
        )
    }

    mutating func add(_ other: Self) {
        self = self + other
    }

    func delta(after previous: Self?) -> Self {
        guard let previous else { return self }
        return Self(
            input: input.delta(after: previous.input),
            cachedInput: cachedInput.delta(after: previous.cachedInput),
            output: output.delta(after: previous.output),
            reasoning: reasoning.delta(after: previous.reasoning),
            total: total.delta(after: previous.total)
        )
    }
}

private extension Int64 {
    func saturatedAdding(_ other: Int64) -> Int64 {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? Int64.max : result
    }

    /// Cumulative token counters occasionally reset between turns. A lower
    /// value therefore begins a new counter rather than becoming negative.
    func delta(after previous: Int64) -> Int64 {
        self >= previous ? self - previous : self
    }
}
