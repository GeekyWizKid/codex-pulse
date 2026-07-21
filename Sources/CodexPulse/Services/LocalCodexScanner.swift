import Foundation
import SQLite3

/// Reads Codex's local metadata without touching conversation titles, previews,
/// prompts, authentication files, or any network service.
@available(macOS 14.0, *)
public actor LocalCodexScanner {
    public typealias ProgressHandler = @Sendable (LocalScanProgress) -> Void

    private let codexHomeURL: URL
    private let cacheURL: URL
    private let readChunkSize: Int
    private let maximumLineSize = 8 * 1_024 * 1_024
    private var cacheLoaded = false
    private var rolloutCache: [RolloutCacheKey: ParsedRollout] = [:]

    public init(
        codexHomeURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true),
        cacheDirectoryURL: URL? = nil,
        readChunkSize: Int = 128 * 1_024
    ) {
        self.codexHomeURL = codexHomeURL.standardizedFileURL
        let defaultCacheDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("CodexPulse", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("CodexPulse", isDirectory: true)
        self.cacheURL = (cacheDirectoryURL ?? defaultCacheDirectory)
            .appendingPathComponent("local-usage-cache.json", isDirectory: false)
        self.readChunkSize = max(4_096, readChunkSize)
    }

    /// Finds `state_N.sqlite` by numeric N, not lexicographic filename order.
    public nonisolated static func locateLatestStateDatabase(
        in codexHomeURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    ) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: codexHomeURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return entries.compactMap { url -> (version: Int, url: URL)? in
            let filename = url.lastPathComponent
            guard filename.hasPrefix("state_"), filename.hasSuffix(".sqlite") else {
                return nil
            }
            let start = filename.index(filename.startIndex, offsetBy: "state_".count)
            let end = filename.index(filename.endIndex, offsetBy: -".sqlite".count)
            guard start < end, let version = Int(filename[start..<end]) else {
                return nil
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
                return nil
            }
            return (version, url)
        }
        .max { lhs, rhs in
            lhs.version == rhs.version
                ? lhs.url.lastPathComponent < rhs.url.lastPathComponent
                : lhs.version < rhs.version
        }?
        .url
    }

    /// The intended AppStore entrypoint. The synchronous disk work runs on this
    /// actor rather than the main actor, while progress can be forwarded to UI.
    public func scan(progress: ProgressHandler? = nil) async throws -> LocalUsageSnapshot {
        progress?(LocalScanProgress(phase: .locatingDatabase, completed: 0, total: 0))
        try Task.checkCancellation()

        guard let databaseURL = Self.locateLatestStateDatabase(in: codexHomeURL) else {
            throw LocalCodexScannerError.stateDatabaseNotFound
        }

        progress?(LocalScanProgress(phase: .readingThreads, completed: 0, total: 0))
        let databaseThreads = try readThreads(from: databaseURL)
        try loadCacheIfNeeded()

        var parsedByThreadID: [String: ParsedRollout] = [:]
        var currentCache: [RolloutCacheKey: ParsedRollout] = [:]
        var parsedThisScan: [RolloutCacheKey: ParsedRollout] = [:]
        var cacheHitCount = 0
        var scannedJSONLCount = 0
        var skippedJSONLCount = 0

        progress?(LocalScanProgress(
            phase: .scanningRollouts,
            completed: 0,
            total: databaseThreads.count
        ))

        for (index, thread) in databaseThreads.enumerated() {
            try Task.checkCancellation()

            guard let rollout = permittedRolloutURL(from: thread.rolloutPath),
                  let key = rolloutCacheKey(for: rollout) else {
                skippedJSONLCount += 1
                progress?(LocalScanProgress(
                    phase: .scanningRollouts,
                    completed: index + 1,
                    total: databaseThreads.count
                ))
                continue
            }

            let parsed: ParsedRollout?
            if let alreadyParsed = parsedThisScan[key] {
                parsed = alreadyParsed
                cacheHitCount += 1
            } else if let cached = rolloutCache[key] {
                parsed = cached
                parsedThisScan[key] = cached
                cacheHitCount += 1
            } else {
                do {
                    let fresh = try parseRollout(at: rollout)
                    parsed = fresh
                    parsedThisScan[key] = fresh
                    scannedJSONLCount += 1
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    parsed = nil
                    skippedJSONLCount += 1
                }
            }

            if let parsed {
                parsedByThreadID[thread.id] = parsed
                currentCache[key] = parsed
            }

            progress?(LocalScanProgress(
                phase: .scanningRollouts,
                completed: index + 1,
                total: databaseThreads.count
            ))
        }

        let cacheChanged = rolloutCache != currentCache
        rolloutCache = currentCache
        // Cache persistence is best-effort: read-only usage data remains useful
        // even if Application Support is temporarily unavailable.
        if cacheChanged {
            try? saveCache()
        }

        progress?(LocalScanProgress(
            phase: .aggregating,
            completed: databaseThreads.count,
            total: databaseThreads.count
        ))
        let snapshot = aggregate(
            databaseThreads: databaseThreads,
            parsedByThreadID: parsedByThreadID,
            databaseName: databaseURL.lastPathComponent,
            cacheHitCount: cacheHitCount,
            scannedJSONLCount: scannedJSONLCount,
            skippedJSONLCount: skippedJSONLCount
        )

        progress?(LocalScanProgress(
            phase: .finished,
            completed: databaseThreads.count,
            total: databaseThreads.count
        ))
        return snapshot
    }
}

// MARK: - SQLite metadata

@available(macOS 14.0, *)
private extension LocalCodexScanner {
    struct DatabaseThread: Sendable {
        let id: String
        let rolloutPath: String
        let cwd: String
        let createdAt: Date
        let updatedAt: Date
        let databaseTokens: Int64
        let isArchived: Bool
        let model: String?
    }

    func readThreads(from databaseURL: URL) throws -> [DatabaseThread] {
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &connection, flags, nil) == SQLITE_OK,
              let connection else {
            let message = connection.flatMap { sqliteMessage($0) } ?? "unknown SQLite error"
            if let connection { sqlite3_close_v2(connection) }
            throw LocalCodexScannerError.databaseOpenFailed(message)
        }
        defer { sqlite3_close_v2(connection) }

        sqlite3_busy_timeout(connection, 750)
        guard sqlite3_exec(connection, "PRAGMA query_only = ON;", nil, nil, nil) == SQLITE_OK else {
            throw LocalCodexScannerError.databaseQueryFailed(sqliteMessage(connection))
        }

        let columns = try threadColumnNames(connection)
        let required = ["id", "rollout_path", "cwd", "created_at", "updated_at"]
        guard required.allSatisfy(columns.contains) else {
            throw LocalCodexScannerError.databaseQueryFailed("required privacy-safe columns are missing")
        }

        // This explicit allowlist is intentional. Never replace it with SELECT *:
        // title, preview, first_user_message, and auth-related data are out of scope.
        let query = """
        SELECT
            \(columnExpression("id", available: columns, fallback: "''")),
            \(columnExpression("rollout_path", available: columns, fallback: "''")),
            \(columnExpression("cwd", available: columns, fallback: "''")),
            \(columnExpression("created_at", available: columns, fallback: "0")),
            \(columnExpression("updated_at", available: columns, fallback: "0")),
            \(columnExpression("created_at_ms", available: columns, fallback: "NULL")),
            \(columnExpression("updated_at_ms", available: columns, fallback: "NULL")),
            \(columnExpression("tokens_used", available: columns, fallback: "0")),
            \(columnExpression("archived", available: columns, fallback: "0")),
            \(columnExpression("model", available: columns, fallback: "NULL"))
        FROM threads
        ORDER BY updated_at DESC, id DESC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw LocalCodexScannerError.databaseQueryFailed(sqliteMessage(connection))
        }
        defer { sqlite3_finalize(statement) }

        var result: [DatabaseThread] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else {
                throw LocalCodexScannerError.databaseQueryFailed(sqliteMessage(connection))
            }

            guard let id = sqliteText(statement, index: 0), !id.isEmpty,
                  let rolloutPath = sqliteText(statement, index: 1),
                  let cwd = sqliteText(statement, index: 2) else {
                continue
            }
            let createdSeconds = sqlite3_column_int64(statement, 3)
            let updatedSeconds = sqlite3_column_int64(statement, 4)
            let createdMilliseconds = sqliteOptionalInt64(statement, index: 5)
            let updatedMilliseconds = sqliteOptionalInt64(statement, index: 6)
            let model = sqliteText(statement, index: 9).flatMap { $0.isEmpty ? nil : $0 }

            result.append(DatabaseThread(
                id: id,
                rolloutPath: rolloutPath,
                cwd: cwd,
                createdAt: sqliteDate(seconds: createdSeconds, milliseconds: createdMilliseconds),
                updatedAt: sqliteDate(seconds: updatedSeconds, milliseconds: updatedMilliseconds),
                databaseTokens: max(0, sqlite3_column_int64(statement, 7)),
                isArchived: sqlite3_column_int64(statement, 8) != 0,
                model: model
            ))
        }
        return result
    }

    func threadColumnNames(_ connection: OpaquePointer) throws -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "PRAGMA table_info(threads);", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw LocalCodexScannerError.databaseQueryFailed(sqliteMessage(connection))
        }
        defer { sqlite3_finalize(statement) }

        var names: Set<String> = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else {
                throw LocalCodexScannerError.databaseQueryFailed(sqliteMessage(connection))
            }
            if let name = sqliteText(statement, index: 1) {
                names.insert(name)
            }
        }
        return names
    }

    func columnExpression(_ name: String, available: Set<String>, fallback: String) -> String {
        available.contains(name) ? "\"\(name)\"" : "\(fallback) AS \"\(name)\""
    }

    func sqliteText(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    func sqliteOptionalInt64(_ statement: OpaquePointer, index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, index)
    }

    func sqliteDate(seconds: Int64, milliseconds: Int64?) -> Date {
        if let milliseconds, milliseconds > 0 {
            return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
        }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    func sqliteMessage(_ connection: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(connection))
    }
}

// MARK: - Sandboxed rollout discovery and cache

@available(macOS 14.0, *)
private extension LocalCodexScanner {
    struct RolloutCacheKey: Codable, Hashable, Sendable {
        let path: String
        let size: Int64
        let modificationTimeNanoseconds: Int64
    }

    struct CacheRecord: Codable, Sendable {
        let key: RolloutCacheKey
        let value: ParsedRollout
    }

    struct CacheEnvelope: Codable, Sendable {
        let version: Int
        let records: [CacheRecord]
    }

    func permittedRolloutURL(from databasePath: String) -> URL? {
        guard !databasePath.isEmpty else { return nil }
        let candidate: URL
        if databasePath.hasPrefix("/") {
            candidate = URL(fileURLWithPath: databasePath, isDirectory: false)
        } else {
            candidate = codexHomeURL.appendingPathComponent(databasePath, isDirectory: false)
        }

        guard candidate.pathExtension.lowercased() == "jsonl" else { return nil }
        let resolvedRoot = codexHomeURL.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedCandidate.path == resolvedRoot
                || resolvedCandidate.path.hasPrefix(resolvedRoot + "/") else {
            return nil
        }

        let values = try? candidate.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else { return nil }
        return candidate.standardizedFileURL
    }

    func rolloutCacheKey(for url: URL) -> RolloutCacheKey? {
        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]), values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize,
              let modificationDate = values.contentModificationDate else {
            return nil
        }

        let nanoseconds = modificationDate.timeIntervalSince1970 * 1_000_000_000
        return RolloutCacheKey(
            path: url.standardizedFileURL.path,
            size: Int64(size),
            modificationTimeNanoseconds: nanoseconds.isFinite
                ? Int64(nanoseconds.rounded())
                : 0
        )
    }

    func loadCacheIfNeeded() throws {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }

        do {
            let handle = try FileHandle(forReadingFrom: cacheURL)
            defer { try? handle.close() }
            guard let data = try handle.readToEnd(), !data.isEmpty else { return }
            let envelope = try JSONDecoder().decode(CacheEnvelope.self, from: data)
            guard envelope.version == 2 else { return }
            rolloutCache = Dictionary(
                envelope.records.map { ($0.key, $0.value) },
                uniquingKeysWith: { _, newest in newest }
            )
        } catch {
            // A corrupt or old cache is never trusted; the source JSONL is
            // rescanned and a fresh metadata-only cache replaces it.
            rolloutCache = [:]
        }
    }

    func saveCache() throws {
        let records = rolloutCache
            .map { CacheRecord(key: $0.key, value: $0.value) }
            .sorted { lhs, rhs in lhs.key.path < rhs.key.path }
        let envelope = CacheEnvelope(version: 2, records: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)

        let directory = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: cacheURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: cacheURL.path
        )
    }
}

// MARK: - Incremental JSONL parsing

@available(macOS 14.0, *)
private extension LocalCodexScanner {
    struct ParsedRollout: Codable, Equatable, Sendable {
        var tokens = LocalTokenUsage()
        var tokenSnapshotCount = 0
        var firstEventAt: Date?
        var lastEventAt: Date?
        var endedAt: Date?
        var actualTaskDuration: TimeInterval = 0
        var completedTaskCount = 0
        var abortedTaskCount = 0
        var openTaskStarts: [String: Date?] = [:]
        var closedTerminalKeys: Set<String> = []
        var temporalSamples: [TemporalUsageSample] = []

        var isActive: Bool { !openTaskStarts.isEmpty }
        var activeSince: Date? { openTaskStarts.values.compactMap { $0 }.min() }
    }

    struct TemporalUsageSample: Codable, Equatable, Sendable {
        let timestamp: Date
        var tokens = LocalTokenUsage()
        var actualTaskDuration: TimeInterval = 0
    }

    struct TokenAccumulator {
        var aggregate = LocalTokenUsage()
        var previousCumulative = TokenFields()

        mutating func consume(cumulative: TokenFields) -> LocalTokenUsage {
            let inputDelta = cumulativeDelta(cumulative.input, previous: &previousCumulative.input)
            let cachedDelta = cumulativeDelta(
                cumulative.cachedInput,
                previous: &previousCumulative.cachedInput
            )
            let outputDelta = cumulativeDelta(cumulative.output, previous: &previousCumulative.output)
            let reasoningDelta = cumulativeDelta(
                cumulative.reasoning,
                previous: &previousCumulative.reasoning
            )
            let totalDelta: Int64
            if cumulative.total != nil {
                totalDelta = cumulativeDelta(cumulative.total, previous: &previousCumulative.total)
            } else {
                totalDelta = saturatedAdd(inputDelta, outputDelta)
            }
            let delta = LocalTokenUsage(
                input: inputDelta,
                cachedInput: cachedDelta,
                output: outputDelta,
                reasoning: reasoningDelta,
                total: totalDelta
            )
            aggregate.add(delta)
            return delta
        }

        mutating func consume(incremental: TokenFields) -> LocalTokenUsage {
            let delta = incremental.resolved
            aggregate.add(delta)
            return delta
        }

        private func cumulativeDelta(_ current: Int64?, previous: inout Int64?) -> Int64 {
            guard let current else { return 0 }
            defer { previous = current }
            guard let previous else { return current }
            return current >= previous ? current - previous : current
        }
    }

    func parseRollout(at url: URL) throws -> ParsedRollout {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var parsed = ParsedRollout()
        var tokenAccumulator = TokenAccumulator()
        var lineBuffer = Data()
        lineBuffer.reserveCapacity(min(readChunkSize, 256 * 1_024))
        var discardingOversizedLine = false

        while let chunk = try handle.read(upToCount: readChunkSize), !chunk.isEmpty {
            try Task.checkCancellation()
            consume(
                chunk: chunk,
                lineBuffer: &lineBuffer,
                discardingOversizedLine: &discardingOversizedLine,
                parsed: &parsed,
                tokenAccumulator: &tokenAccumulator
            )
        }

        if !discardingOversizedLine, !lineBuffer.isEmpty {
            consumeCandidateLine(
                lineBuffer,
                parsed: &parsed,
                tokenAccumulator: &tokenAccumulator
            )
        }
        parsed.tokens = tokenAccumulator.aggregate
        return parsed
    }

    func consume(
        chunk: Data,
        lineBuffer: inout Data,
        discardingOversizedLine: inout Bool,
        parsed: inout ParsedRollout,
        tokenAccumulator: inout TokenAccumulator
    ) {
        var segmentStart = chunk.startIndex
        while segmentStart < chunk.endIndex {
            let remaining = chunk[segmentStart..<chunk.endIndex]
            if let newline = remaining.firstIndex(of: 0x0A) {
                if discardingOversizedLine {
                    discardingOversizedLine = false
                } else {
                    let segment = chunk[segmentStart..<newline]
                    if lineBuffer.count + segment.count <= maximumLineSize {
                        lineBuffer.append(contentsOf: segment)
                        consumeCandidateLine(
                            lineBuffer,
                            parsed: &parsed,
                            tokenAccumulator: &tokenAccumulator
                        )
                    }
                }
                lineBuffer.removeAll(keepingCapacity: true)
                segmentStart = chunk.index(after: newline)
            } else {
                if !discardingOversizedLine {
                    if lineBuffer.count + remaining.count <= maximumLineSize {
                        lineBuffer.append(contentsOf: remaining)
                    } else {
                        lineBuffer.removeAll(keepingCapacity: true)
                        discardingOversizedLine = true
                    }
                }
                break
            }
        }
    }

    func consumeCandidateLine(
        _ line: Data,
        parsed: inout ParsedRollout,
        tokenAccumulator: inout TokenAccumulator
    ) {
        guard !line.isEmpty, containsCandidateMarker(line) else { return }
        guard let event = try? JSONDecoder().decode(RolloutEvent.self, from: line),
              let eventType = event.recognizedType else {
            return
        }

        let timestamp = event.eventDate
        parsed.firstEventAt = earliest(parsed.firstEventAt, timestamp)
        parsed.lastEventAt = latest(parsed.lastEventAt, timestamp)

        switch eventType {
        case "turn_context":
            break

        case "token_count":
            guard let fields = event.tokenFields, fields.hasAnyValue else { return }
            let tokenDelta: LocalTokenUsage
            if event.hasCumulativeTokenFields {
                tokenDelta = tokenAccumulator.consume(cumulative: fields)
            } else {
                tokenDelta = tokenAccumulator.consume(incremental: fields)
            }
            parsed.tokenSnapshotCount += 1
            if let timestamp, tokenDelta.hasAnyTokenValue {
                parsed.temporalSamples.append(TemporalUsageSample(
                    timestamp: timestamp,
                    tokens: tokenDelta
                ))
            }

        case "task_started":
            let taskID = event.taskIdentifier ?? "__default__"
            let terminalKey = "task:\(taskID)"
            if parsed.openTaskStarts[taskID] == nil,
               !parsed.closedTerminalKeys.contains(terminalKey) {
                parsed.openTaskStarts[taskID] = .some(event.taskStartDate)
            }

        case "task_complete", "turn_aborted":
            let requestedTaskID = event.taskIdentifier
            let terminalKey = requestedTaskID.map { "task:\($0)" }
                ?? timestamp.map { "\(eventType):\($0.timeIntervalSince1970)" }
            let isDuplicateTerminal = terminalKey.map(parsed.closedTerminalKeys.contains) ?? false
            let matchedTaskID: String?
            if let requestedTaskID, parsed.openTaskStarts.keys.contains(requestedTaskID) {
                matchedTaskID = requestedTaskID
            } else if parsed.openTaskStarts.count == 1 {
                matchedTaskID = parsed.openTaskStarts.keys.first
            } else {
                matchedTaskID = parsed.openTaskStarts
                    .sorted { lhs, rhs in
                        let left = lhs.value ?? .distantFuture
                        let right = rhs.value ?? .distantFuture
                        return left < right
                    }
                    .first?.key
            }

            var pairedDuration: TimeInterval?
            if let matchedTaskID {
                let nestedStart = parsed.openTaskStarts.removeValue(forKey: matchedTaskID)
                if let start = nestedStart ?? nil, let timestamp, timestamp >= start {
                    pairedDuration = timestamp.timeIntervalSince(start)
                }
            }
            if !isDuplicateTerminal {
                if let terminalKey { parsed.closedTerminalKeys.insert(terminalKey) }
                let duration = max(0, event.reportedTaskDuration ?? pairedDuration ?? 0)
                parsed.actualTaskDuration += duration
                if let timestamp, duration > 0 {
                    parsed.temporalSamples.append(TemporalUsageSample(
                        timestamp: timestamp,
                        actualTaskDuration: duration
                    ))
                }
                if eventType == "task_complete" {
                    parsed.completedTaskCount += 1
                } else {
                    parsed.abortedTaskCount += 1
                }
            }
            parsed.endedAt = latest(parsed.endedAt, timestamp)

        default:
            break
        }
    }

    func containsCandidateMarker(_ data: Data) -> Bool {
        // Byte-level prefiltering avoids JSON-decoding the overwhelming
        // majority of response/message lines, where prompt content can live.
        Self.candidateMarkers.contains { data.range(of: $0) != nil }
    }

    nonisolated static var candidateMarkers: [Data] {
        ["turn_context", "token_count", "task_started", "task_complete", "turn_aborted"]
            .map { Data($0.utf8) }
    }

    func earliest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (left?, right?): min(left, right)
        case let (left?, nil): left
        case let (nil, right?): right
        case (nil, nil): nil
        }
    }

    func latest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (left?, right?): max(left, right)
        case let (left?, nil): left
        case let (nil, right?): right
        case (nil, nil): nil
        }
    }
}

// MARK: - Aggregation

@available(macOS 14.0, *)
private extension LocalCodexScanner {
    struct ProjectAccumulator {
        var threadCount = 0
        var sessionCount = 0
        var activeThreadCount = 0
        var models: Set<String> = []
        var latestActivityAt: Date?
        var actualTaskDuration: TimeInterval = 0
        var tokens = LocalTokenUsage()
    }

    struct DailyAccumulator {
        var tokens = LocalTokenUsage()
        var actualTaskDuration: TimeInterval = 0
    }

    func aggregate(
        databaseThreads: [DatabaseThread],
        parsedByThreadID: [String: ParsedRollout],
        databaseName: String,
        cacheHitCount: Int,
        scannedJSONLCount: Int,
        skippedJSONLCount: Int
    ) -> LocalUsageSnapshot {
        var threadSummaries: [LocalThreadUsageSummary] = []
        var projectAccumulators: [String: ProjectAccumulator] = [:]
        var totalTokens = LocalTokenUsage()
        var totalDuration: TimeInterval = 0
        var activeThreadIDs: [String] = []
        var activeProjectNames: Set<String> = []
        var activeSince: Date?
        var activeLastEventAt: Date?
        var dailyAccumulators: [Date: DailyAccumulator] = [:]
        var hourlyAccumulators: [Date: DailyAccumulator] = [:]
        var hourlyTokenTotals = Array(repeating: Int64(0), count: 24)
        let calendar = Calendar.current

        for thread in databaseThreads {
            let projectName = projectName(for: thread.cwd)
            let parsed = parsedByThreadID[thread.id]
            let hasDetailedTokens = (parsed?.tokenSnapshotCount ?? 0) > 0
            let effectiveTokens = hasDetailedTokens
                ? (parsed?.tokens ?? LocalTokenUsage())
                : LocalTokenUsage(total: thread.databaseTokens)
            // An unmatched task_started can survive a crash or old log format.
            // Count it as live only while the thread itself has changed recently;
            // otherwise the UI would turn stale sessions into permanent work.
            let lastActivity = latest(parsed?.lastEventAt, thread.updatedAt) ?? thread.updatedAt
            let isRecentlyUpdated = Date().timeIntervalSince(lastActivity) <= 10 * 60
            let isActive = (parsed?.isActive ?? false)
                && !thread.isArchived
                && isRecentlyUpdated

            let sessions: [LocalSessionUsageSummary]
            if let parsed {
                sessions = [LocalSessionUsageSummary(
                    id: "\(thread.id):local",
                    threadID: thread.id,
                    projectName: projectName,
                    startedAt: parsed.firstEventAt ?? thread.createdAt,
                    endedAt: parsed.endedAt,
                    lastEventAt: parsed.lastEventAt,
                    actualTaskDuration: parsed.actualTaskDuration,
                    completedTaskCount: parsed.completedTaskCount,
                    abortedTaskCount: parsed.abortedTaskCount,
                    isActive: isActive,
                    tokens: effectiveTokens
                )]
            } else {
                sessions = []
            }

            let summary = LocalThreadUsageSummary(
                id: thread.id,
                projectName: projectName,
                createdAt: thread.createdAt,
                updatedAt: thread.updatedAt,
                model: thread.model,
                isArchived: thread.isArchived,
                databaseTokenCount: thread.databaseTokens,
                tokens: effectiveTokens,
                actualTaskDuration: parsed?.actualTaskDuration ?? 0,
                sessions: sessions,
                isActive: isActive
            )
            threadSummaries.append(summary)
            totalTokens.add(effectiveTokens)
            totalDuration += summary.actualTaskDuration

            var project = projectAccumulators[projectName] ?? ProjectAccumulator()
            project.threadCount += 1
            project.sessionCount += sessions.count
            project.activeThreadCount += isActive ? 1 : 0
            if let model = thread.model { project.models.insert(model) }
            project.latestActivityAt = latest(
                project.latestActivityAt,
                parsed?.lastEventAt ?? thread.updatedAt
            )
            project.actualTaskDuration += summary.actualTaskDuration
            project.tokens.add(effectiveTokens)
            projectAccumulators[projectName] = project

            if let parsed {
                for sample in parsed.temporalSamples {
                    let day = calendar.startOfDay(for: sample.timestamp)
                    var daily = dailyAccumulators[day] ?? DailyAccumulator()
                    daily.tokens.add(sample.tokens)
                    daily.actualTaskDuration += sample.actualTaskDuration
                    dailyAccumulators[day] = daily

                    if let hourStart = calendar.dateInterval(
                        of: .hour,
                        for: sample.timestamp
                    )?.start {
                        var hourly = hourlyAccumulators[hourStart] ?? DailyAccumulator()
                        hourly.tokens.add(sample.tokens)
                        hourly.actualTaskDuration += sample.actualTaskDuration
                        hourlyAccumulators[hourStart] = hourly
                    }

                    let hour = calendar.component(.hour, from: sample.timestamp)
                    if (0..<24).contains(hour) {
                        hourlyTokenTotals[hour] = saturatedAdd(
                            hourlyTokenTotals[hour],
                            sample.tokens.total
                        )
                    }
                }
            }

            if isActive {
                activeThreadIDs.append(thread.id)
                activeProjectNames.insert(projectName)
                activeSince = earliest(activeSince, parsed?.activeSince)
                activeLastEventAt = latest(activeLastEventAt, parsed?.lastEventAt)
            }
        }

        threadSummaries.sort {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
        let projects = projectAccumulators.map { name, value in
            LocalProjectUsageSummary(
                name: name,
                threadCount: value.threadCount,
                sessionCount: value.sessionCount,
                activeThreadCount: value.activeThreadCount,
                models: value.models.sorted(),
                latestActivityAt: value.latestActivityAt,
                actualTaskDuration: value.actualTaskDuration,
                tokens: value.tokens
            )
        }
        .sorted {
            if $0.tokens.total != $1.tokens.total { return $0.tokens.total > $1.tokens.total }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        let activity = LocalCurrentActivitySummary(
            isActive: !activeThreadIDs.isEmpty,
            activeThreadCount: activeThreadIDs.count,
            activeProjectNames: activeProjectNames.sorted(),
            activeThreadIDs: activeThreadIDs.sorted(),
            activeSince: activeSince,
            lastEventAt: activeLastEventAt
        )
        let dailyUsage = dailyAccumulators.map { date, value in
            LocalDailyUsageBucket(
                date: date,
                tokens: value.tokens,
                actualTaskDuration: value.actualTaskDuration
            )
        }
        .sorted { $0.date < $1.date }
        let hourlyUsage = hourlyAccumulators.map { date, value in
            LocalHourlyUsageBucket(
                date: date,
                tokens: value.tokens,
                actualTaskDuration: value.actualTaskDuration
            )
        }
        .sorted { $0.date < $1.date }
        return LocalUsageSnapshot(
            scannedAt: Date(),
            stateDatabaseName: databaseName,
            threads: threadSummaries,
            projects: projects,
            tokens: totalTokens,
            sessionCount: threadSummaries.reduce(0) { $0 + $1.sessions.count },
            actualTaskDuration: totalDuration,
            currentActivity: activity,
            dailyUsage: dailyUsage,
            hourlyUsage: hourlyUsage,
            hourlyTokenTotals: hourlyTokenTotals,
            cacheHitCount: cacheHitCount,
            scannedJSONLCount: scannedJSONLCount,
            skippedJSONLCount: skippedJSONLCount
        )
    }

    func projectName(for cwd: String) -> String {
        let component = URL(fileURLWithPath: cwd, isDirectory: true)
            .standardizedFileURL
            .lastPathComponent
        return component.isEmpty ? "Unknown Project" : component
    }
}

// MARK: - Narrow JSON decoding

private struct RolloutEvent: Decodable {
    let timestamp: FlexibleDate?
    let type: String?
    let payload: EventPayload?
    let info: TokenInfo?
    let totalTokenUsage: TokenFields?
    let lastTokenUsage: TokenFields?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case type
        case payload
        case info
        case totalTokenUsage = "total_token_usage"
        case lastTokenUsage = "last_token_usage"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try? container.decodeIfPresent(FlexibleDate.self, forKey: .timestamp)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        payload = try? container.decodeIfPresent(EventPayload.self, forKey: .payload)
        info = try? container.decodeIfPresent(TokenInfo.self, forKey: .info)
        totalTokenUsage = try? container.decodeIfPresent(TokenFields.self, forKey: .totalTokenUsage)
        lastTokenUsage = try? container.decodeIfPresent(TokenFields.self, forKey: .lastTokenUsage)
    }

    var recognizedType: String? {
        let supported = Set(["turn_context", "token_count", "task_started", "task_complete", "turn_aborted"])
        if let type, supported.contains(type) { return type }
        if let payloadType = payload?.type, supported.contains(payloadType) { return payloadType }
        return nil
    }

    var eventDate: Date? {
        switch recognizedType {
        case "task_started":
            return taskStartDate
        case "task_complete", "turn_aborted":
            return payload?.completedAt?.value
                ?? payload?.timestamp?.value
                ?? payload?.time?.value
                ?? timestamp?.value
        default:
            return timestamp?.value ?? payload?.timestamp?.value ?? payload?.time?.value
        }
    }

    var taskStartDate: Date? {
        payload?.startedAt?.value
            ?? payload?.timestamp?.value
            ?? payload?.time?.value
            ?? timestamp?.value
    }

    var reportedTaskDuration: TimeInterval? {
        if let milliseconds = payload?.durationMilliseconds?.value,
           milliseconds.isFinite, milliseconds >= 0 {
            return milliseconds / 1_000
        }
        if let start = payload?.startedAt?.value,
           let end = payload?.completedAt?.value,
           end >= start {
            return end.timeIntervalSince(start)
        }
        return nil
    }

    var taskIdentifier: String? {
        payload?.turnID ?? payload?.taskID ?? payload?.id
    }

    var hasCumulativeTokenFields: Bool {
        cumulativeTokenFields != nil
    }

    var tokenFields: TokenFields? {
        if let value = cumulativeTokenFields {
            return value
        }
        return [
            payload?.info?.lastTokenUsage,
            payload?.lastTokenUsage,
            payload?.usage,
            payload?.tokenUsage,
            info?.lastTokenUsage,
            lastTokenUsage
        ]
        .compactMap { $0 }
        .first(where: \.hasAnyValue)
    }

    private var cumulativeTokenFields: TokenFields? {
        [
            payload?.info?.totalTokenUsage,
            payload?.totalTokenUsage,
            info?.totalTokenUsage,
            totalTokenUsage
        ]
        .compactMap { $0 }
        .first(where: \.hasAnyValue)
    }
}

private struct EventPayload: Decodable {
    let type: String?
    let timestamp: FlexibleDate?
    let time: FlexibleDate?
    let startedAt: FlexibleDate?
    let completedAt: FlexibleDate?
    let durationMilliseconds: FlexibleDouble?
    let turnID: String?
    let taskID: String?
    let id: String?
    let info: TokenInfo?
    let totalTokenUsage: TokenFields?
    let lastTokenUsage: TokenFields?
    let usage: TokenFields?
    let tokenUsage: TokenFields?

    enum CodingKeys: String, CodingKey {
        case type
        case timestamp
        case time
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case durationMilliseconds = "duration_ms"
        case turnID = "turn_id"
        case taskID = "task_id"
        case id
        case info
        case totalTokenUsage = "total_token_usage"
        case lastTokenUsage = "last_token_usage"
        case usage
        case tokenUsage = "token_usage"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        timestamp = try? container.decodeIfPresent(FlexibleDate.self, forKey: .timestamp)
        time = try? container.decodeIfPresent(FlexibleDate.self, forKey: .time)
        startedAt = try? container.decodeIfPresent(FlexibleDate.self, forKey: .startedAt)
        completedAt = try? container.decodeIfPresent(FlexibleDate.self, forKey: .completedAt)
        durationMilliseconds = try? container.decodeIfPresent(
            FlexibleDouble.self,
            forKey: .durationMilliseconds
        )
        turnID = try? container.decodeIfPresent(String.self, forKey: .turnID)
        taskID = try? container.decodeIfPresent(String.self, forKey: .taskID)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        info = try? container.decodeIfPresent(TokenInfo.self, forKey: .info)
        totalTokenUsage = try? container.decodeIfPresent(TokenFields.self, forKey: .totalTokenUsage)
        lastTokenUsage = try? container.decodeIfPresent(TokenFields.self, forKey: .lastTokenUsage)
        usage = try? container.decodeIfPresent(TokenFields.self, forKey: .usage)
        tokenUsage = try? container.decodeIfPresent(TokenFields.self, forKey: .tokenUsage)
    }
}

private struct TokenInfo: Decodable {
    let totalTokenUsage: TokenFields?
    let lastTokenUsage: TokenFields?

    enum CodingKeys: String, CodingKey {
        case totalTokenUsage = "total_token_usage"
        case lastTokenUsage = "last_token_usage"
    }
}

private struct TokenFields: Codable, Equatable, Sendable {
    var input: Int64?
    var cachedInput: Int64?
    var output: Int64?
    var reasoning: Int64?
    var total: Int64?

    init(
        input: Int64? = nil,
        cachedInput: Int64? = nil,
        output: Int64? = nil,
        reasoning: Int64? = nil,
        total: Int64? = nil
    ) {
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
        self.reasoning = reasoning
        self.total = total
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case input
        case cachedInputTokens = "cached_input_tokens"
        case cachedInput = "cached_input"
        case outputTokens = "output_tokens"
        case output
        case reasoningOutputTokens = "reasoning_output_tokens"
        case reasoningTokens = "reasoning_tokens"
        case reasoning
        case totalTokens = "total_tokens"
        case total
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = Self.value(in: container, keys: [.inputTokens, .input])
        cachedInput = Self.value(in: container, keys: [.cachedInputTokens, .cachedInput])
        output = Self.value(in: container, keys: [.outputTokens, .output])
        reasoning = Self.value(
            in: container,
            keys: [.reasoningOutputTokens, .reasoningTokens, .reasoning]
        )
        total = Self.value(in: container, keys: [.totalTokens, .total])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(input, forKey: .inputTokens)
        try container.encodeIfPresent(cachedInput, forKey: .cachedInputTokens)
        try container.encodeIfPresent(output, forKey: .outputTokens)
        try container.encodeIfPresent(reasoning, forKey: .reasoningOutputTokens)
        try container.encodeIfPresent(total, forKey: .totalTokens)
    }

    var hasAnyValue: Bool {
        input != nil || cachedInput != nil || output != nil || reasoning != nil || total != nil
    }

    var resolved: LocalTokenUsage {
        let safeInput = max(0, input ?? 0)
        let safeOutput = max(0, output ?? 0)
        return LocalTokenUsage(
            input: safeInput,
            cachedInput: max(0, cachedInput ?? 0),
            output: safeOutput,
            reasoning: max(0, reasoning ?? 0),
            total: max(0, total ?? saturatedAdd(safeInput, safeOutput))
        )
    }

    private static func value(
        in container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Int64? {
        for key in keys {
            if let decoded = try? container.decode(FlexibleInt64.self, forKey: key) {
                return max(0, decoded.value)
            }
        }
        return nil
    }
}

private struct FlexibleInt64: Decodable {
    let value: Int64

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int64.self) {
            self.value = value
        } else if let value = try? container.decode(Double.self), value.isFinite {
            if value >= Double(Int64.max) {
                self.value = Int64.max
            } else if value <= Double(Int64.min) {
                self.value = Int64.min
            } else {
                self.value = Int64(value.rounded(.towardZero))
            }
        } else if let text = try? container.decode(String.self), let value = Int64(text) {
            self.value = value
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an integer token count"
            )
        }
    }
}

private struct FlexibleDouble: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self), value.isFinite {
            self.value = value
        } else if let text = try? container.decode(String.self),
                  let value = Double(text), value.isFinite {
            self.value = value
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a finite number"
            )
        }
    }
}

private struct FlexibleDate: Decodable {
    let value: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self), number.isFinite {
            value = Self.date(fromNumericTimestamp: number)
            return
        }
        if let text = try? container.decode(String.self) {
            if let number = Double(text), number.isFinite {
                value = Self.date(fromNumericTimestamp: number)
                return
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) {
                value = date
                return
            }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) {
                value = date
                return
            }
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected an ISO-8601 or Unix timestamp"
        )
    }

    private static func date(fromNumericTimestamp value: Double) -> Date {
        let magnitude = abs(value)
        if magnitude >= 1_000_000_000_000_000 {
            return Date(timeIntervalSince1970: value / 1_000_000)
        }
        if magnitude >= 1_000_000_000_000 {
            return Date(timeIntervalSince1970: value / 1_000)
        }
        return Date(timeIntervalSince1970: value)
    }
}

private func saturatedAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? Int64.max : result
}

private extension LocalTokenUsage {
    var hasAnyTokenValue: Bool {
        input != 0 || cachedInput != 0 || output != 0 || reasoning != 0 || total != 0
    }
}
