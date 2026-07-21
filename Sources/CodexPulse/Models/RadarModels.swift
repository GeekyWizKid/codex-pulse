import Foundation

/// Reasoning effort reported by CodexRadar. Unknown values are deliberately
/// preserved so a server-side rollout cannot make the entire table undecodable.
enum RadarEffort: Hashable, Sendable, Codable {
    case low
    case medium
    case high
    case xhigh
    case max
    case ultra
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "low": self = .low
        case "medium": self = .medium
        case "high": self = .high
        case "xhigh": self = .xhigh
        case "max": self = .max
        case "ultra": self = .ultra
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        case .xhigh: "xhigh"
        case .max: "max"
        case .ultra: "ultra"
        case let .unknown(value): value
        }
    }

    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "XHigh"
        case .max: "Max"
        case .ultra: "Ultra"
        case let .unknown(value): value.isEmpty ? "Unknown" : value
        }
    }

    var sortOrder: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .xhigh: 3
        case .max: 4
        case .ultra: 5
        case .unknown: 6
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self.init(rawValue: value)
        } else if let value = try? container.decode(Int.self) {
            self = .unknown(String(value))
        } else {
            self = .unknown("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum RadarCostQuality: String, Codable, Hashable, Sendable {
    /// Every usable cost was explicitly reported by a runner.
    case reported
    /// The sample contains both reported and token-derived costs.
    case mixed
    /// Every usable cost was derived from tokens.
    case estimated
    /// Costs exist, but one or more sources are absent or unknown.
    case unverified
    /// No usable cost samples exist.
    case unavailable
}

/// A privacy-safe, aggregate row for one model and reasoning-effort pair.
/// Contributor names and avatar identifiers never enter this model.
struct ModelIntelligence: Identifiable, Codable, Hashable, Sendable {
    let rank: Int
    let model: String
    let effort: RadarEffort
    let liveIQ: Double?
    let recentIQ: Double?
    let longTermIQ: Double?
    let coverage: Double
    let coveredTaskCount: Int
    let taskCount: Int
    let liveSampleCount: Int
    let recentSampleCount: Int
    let longTermSampleCount: Int
    let meanRecentDurationSeconds: TimeInterval?
    let durationSampleCount: Int
    let meanRecentCostUSD: Double?
    let costSampleCount: Int
    let reportedCostSampleCount: Int
    let costQuality: RadarCostQuality

    var id: String { "\(model)|\(effort.rawValue)" }
    var displayName: String { "\(model) · \(effort.displayName)" }

    /// Best currently available IQ signal, useful while the live window is empty.
    var bestAvailableIQ: Double? {
        liveIQ ?? recentIQ ?? longTermIQ
    }
}

struct RadarMetadata: Codable, Hashable, Sendable {
    let schema: Int?
    let fetchedAt: Date
    let sourceURL: URL
    let baselineGeneratedAt: Date?
    let discriminationGeneratedAt: Date?
    let discriminationMethod: String?
    let reopenAfterHours: Double?
    let onlineVolunteers: Int
    let k: Double?
    let tierWindowsUSD: [String: Double]
    let taskCount: Int
    let comboCount: Int
    let cellCount: Int
}

struct RadarSnapshot: Codable, Hashable, Sendable {
    let metadata: RadarMetadata
    /// Rows are ordered by live, recent, and long-term IQ, in that order.
    let rows: [ModelIntelligence]

    var fetchedAt: Date { metadata.fetchedAt }
    var onlineVolunteers: Int { metadata.onlineVolunteers }
    var taskCount: Int { metadata.taskCount }
}

// MARK: - Wire models

/// The table payload is intentionally permissive. Its aggregate representation
/// is the product API; these wire models are never persisted.
struct RadarTablePayload: Decodable {
    var schema: Int?
    var combos: [RadarComboPayload] = []
    var tierWindowsUSD: [String: Double] = [:]
    var tasks: [RadarTaskPayload] = []
    var cells: [String: RadarCellPayload] = [:]
    var baselineGeneratedAt: Date?
    var discriminationGeneratedAt: Date?
    var discriminationMethod: String?
    var reopenAfterHours: Double?
    var onlineVolunteers: Int?
    var k: Double?

    private enum CodingKeys: String, CodingKey {
        case schema
        case combos
        case tierWindowsUSD = "tier_windows_usd"
        case tasks
        case cells
        case baselineGeneratedAt = "baseline_generated_at"
        case discriminationGeneratedAt = "discrimination_generated_at"
        case discriminationMethod = "discrimination_method"
        case reopenAfterHours = "reopen_after_hours"
        case onlineVolunteers = "online_volunteers"
        case k
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        schema = container.decodeFlexibleInt(forKey: .schema)
        combos = (try? container.decode([RadarComboPayload].self, forKey: .combos)) ?? []
        tierWindowsUSD = (try? container.decode(FlexibleDoubleMap.self, forKey: .tierWindowsUSD).values) ?? [:]
        tasks = (try? container.decode([RadarTaskPayload].self, forKey: .tasks)) ?? []
        cells = (try? container.decode([String: RadarCellPayload].self, forKey: .cells)) ?? [:]
        baselineGeneratedAt = container.decodeFlexibleDate(forKey: .baselineGeneratedAt)
        discriminationGeneratedAt = container.decodeFlexibleDate(forKey: .discriminationGeneratedAt)
        discriminationMethod = try? container.decode(String.self, forKey: .discriminationMethod)
        reopenAfterHours = container.decodeFlexibleDouble(forKey: .reopenAfterHours)
        onlineVolunteers = container.decodeFlexibleInt(forKey: .onlineVolunteers)
        k = container.decodeFlexibleDouble(forKey: .k)
    }
}

struct RadarComboPayload: Decodable {
    var model: String?
    var effort: RadarEffort?

    private enum CodingKeys: String, CodingKey {
        case model
        case effort
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        model = try? container.decode(String.self, forKey: .model)
        effort = try? container.decode(RadarEffort.self, forKey: .effort)
    }
}

struct RadarTaskPayload: Decodable {
    var id: String?

    private enum CodingKeys: String, CodingKey {
        case id
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        id = try? container.decode(String.self, forKey: .id)
    }
}

struct RadarCellPayload: Decodable {
    var status: RadarCellStatus?
    var recentSampleCount: Int?
    var recentPassCount: Int?
    var totalSampleCount: Int?
    var totalPassCount: Int?
    var lastGradedAt: Date?
    var runners: [RadarRunnerPayload] = []

    private enum CodingKeys: String, CodingKey {
        case status = "st"
        case recentSampleCount = "n"
        case recentPassCount = "p"
        case totalSampleCount = "total_n"
        case totalPassCount = "total_p"
        case lastGradedAt = "last_graded_at"
        case runners = "ran_by"
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        status = try? container.decode(RadarCellStatus.self, forKey: .status)
        recentSampleCount = container.decodeFlexibleInt(forKey: .recentSampleCount)
        recentPassCount = container.decodeFlexibleInt(forKey: .recentPassCount)
        totalSampleCount = container.decodeFlexibleInt(forKey: .totalSampleCount)
        totalPassCount = container.decodeFlexibleInt(forKey: .totalPassCount)
        lastGradedAt = container.decodeFlexibleDate(forKey: .lastGradedAt)
        runners = (try? container.decode([RadarRunnerPayload].self, forKey: .runners)) ?? []
    }
}

struct RadarRunnerPayload: Decodable {
    var passed: Bool?
    var gradedAt: Date?
    var durationSeconds: Double?
    var actualCostUSD: Double?
    var costSource: RadarCostSource?

    private enum CodingKeys: String, CodingKey {
        case passed
        case gradedAt = "graded_at"
        case durationSeconds = "duration_sec"
        case actualCostUSD = "actual_cost_usd"
        case costSource = "cost_source"
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        passed = container.decodeFlexibleBool(forKey: .passed)
        gradedAt = container.decodeFlexibleDate(forKey: .gradedAt)
        durationSeconds = container.decodeFlexibleDouble(forKey: .durationSeconds)
        actualCostUSD = container.decodeFlexibleDouble(forKey: .actualCostUSD)
        costSource = try? container.decode(RadarCostSource.self, forKey: .costSource)
    }
}

enum RadarCellStatus: Hashable, Sendable, Decodable {
    case open
    case cooldown
    case leased
    case queued
    case running
    case unknown(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? ""
        switch rawValue {
        case "open": self = .open
        case "cooldown": self = .cooldown
        case "leased": self = .leased
        case "queued": self = .queued
        case "running": self = .running
        default: self = .unknown(rawValue)
        }
    }
}

enum RadarCostSource: Hashable, Sendable, Decodable {
    case reported
    case tokens
    case unknown(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? ""
        switch rawValue {
        case "reported": self = .reported
        case "tokens": self = .tokens
        default: self = .unknown(rawValue)
        }
    }
}

// MARK: - Tolerant decoding

private struct FlexibleDoubleMap: Decodable {
    let values: [String: Double]

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: AnyCodingKey.self) else {
            values = [:]
            return
        }

        var decoded: [String: Double] = [:]
        for key in container.allKeys {
            if let value = container.decodeFlexibleDouble(forKey: key), value.isFinite {
                decoded[key.stringValue] = value
            }
        }
        values = decoded
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key),
           value.isFinite,
           value.rounded(.towardZero) == value,
           let exact = Int(exactly: value) {
            return exact
        }
        if let value = try? decode(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func decodeFlexibleDouble(forKey key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? decode(String.self, forKey: key) {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func decodeFlexibleBool(forKey key: Key) -> Bool? {
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) {
            switch value {
            case 0: return false
            case 1: return true
            default: break
            }
        }
        if let value = try? decode(String.self, forKey: key) {
            switch value.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: break
            }
        }
        return nil
    }

    func decodeFlexibleDate(forKey key: Key) -> Date? {
        if let value = try? decode(String.self, forKey: key) {
            return RadarISO8601.parse(value)
        }
        if let value = decodeFlexibleDouble(forKey: key), value.isFinite {
            return Date(timeIntervalSince1970: value)
        }
        return nil
    }
}

private enum RadarISO8601 {
    private static let fractionalFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeSecondFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    static func parse(_ value: String) -> Date? {
        if let date = try? fractionalFormat.parse(value) { return date }
        return try? wholeSecondFormat.parse(value)
    }
}
