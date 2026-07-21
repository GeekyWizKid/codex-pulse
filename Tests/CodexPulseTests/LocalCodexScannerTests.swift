import Foundation
import SQLite3
import XCTest
@testable import CodexPulse

@available(macOS 14.0, *)
final class LocalCodexScannerTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    func testLocateLatestStateDatabaseUsesNumericSuffix() throws {
        let root = try makeTemporaryDirectory()
        for filename in ["state_2.sqlite", "state_10.sqlite", "state_old.sqlite", "state_11.sqlite-wal"] {
            XCTAssertTrue(FileManager.default.createFile(
                atPath: root.appendingPathComponent(filename).path,
                contents: Data()
            ))
        }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("state_99.sqlite"),
            withIntermediateDirectories: false
        )

        let located = LocalCodexScanner.locateLatestStateDatabase(in: root)

        XCTAssertEqual(located?.lastPathComponent, "state_10.sqlite")
    }

    func testStreamsDetailedUsageGroupsProjectsAndTracksActiveWork() async throws {
        let fixture = try makeFixture()
        let scanner = LocalCodexScanner(
            codexHomeURL: fixture.codexHome,
            cacheDirectoryURL: fixture.cacheDirectory,
            readChunkSize: 4_096
        )

        let snapshot = try await scanner.scan()

        XCTAssertEqual(snapshot.stateDatabaseName, "state_7.sqlite")
        XCTAssertEqual(snapshot.threads.count, 3)
        XCTAssertEqual(snapshot.projects.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(snapshot.sessionCount, 2)
        XCTAssertEqual(snapshot.scannedJSONLCount, 2)
        XCTAssertEqual(snapshot.cacheHitCount, 0)
        XCTAssertEqual(snapshot.skippedJSONLCount, 1)

        XCTAssertEqual(snapshot.tokens.input, 177)
        XCTAssertEqual(snapshot.tokens.cachedInput, 35)
        XCTAssertEqual(snapshot.tokens.output, 32)
        XCTAssertEqual(snapshot.tokens.reasoning, 8)
        XCTAssertEqual(snapshot.tokens.total, 249)
        XCTAssertEqual(snapshot.actualTaskDuration, 8.35, accuracy: 0.001)

        let alpha = try XCTUnwrap(snapshot.projects.first { $0.name == "Alpha" })
        XCTAssertEqual(alpha.threadCount, 2)
        XCTAssertEqual(alpha.sessionCount, 1)
        XCTAssertEqual(alpha.activeThreadCount, 0)
        XCTAssertEqual(alpha.models, ["gpt-test"])
        XCTAssertEqual(alpha.tokens.total, 240)
        XCTAssertEqual(alpha.actualTaskDuration, 8.35, accuracy: 0.001)

        let beta = try XCTUnwrap(snapshot.projects.first { $0.name == "Beta" })
        XCTAssertEqual(beta.threadCount, 1)
        XCTAssertEqual(beta.sessionCount, 1)
        XCTAssertEqual(beta.activeThreadCount, 1)
        XCTAssertEqual(beta.models, ["gpt-active"])
        XCTAssertEqual(beta.tokens.total, 9)

        XCTAssertEqual(snapshot.dailyUsage.count, 1)
        XCTAssertEqual(snapshot.dailyUsage.first?.tokens.total, 209)
        XCTAssertEqual(snapshot.dailyUsage.first?.actualTaskDuration ?? -1, 8.35, accuracy: 0.001)
        XCTAssertEqual(snapshot.hourlyUsage.count, 1)
        XCTAssertEqual(snapshot.hourlyUsage.first?.tokens.total, 209)
        XCTAssertEqual(snapshot.hourlyUsage.first?.actualTaskDuration ?? -1, 8.35, accuracy: 0.001)
        XCTAssertEqual(snapshot.hourlyTokenTotals.count, 24)
        XCTAssertEqual(snapshot.hourlyTokenTotals.reduce(0, +), 209)
        let fixtureHour = Calendar.current.component(
            .hour,
            from: Date(timeIntervalSince1970: 1_767_225_602)
        )
        XCTAssertEqual(snapshot.hourlyTokenTotals[fixtureHour], 209)

        let detailedThread = try XCTUnwrap(snapshot.threads.first { $0.id == "thread-detailed" })
        XCTAssertEqual(detailedThread.databaseTokenCount, 999)
        XCTAssertEqual(detailedThread.tokens, LocalTokenUsage(
            input: 170,
            cachedInput: 35,
            output: 30,
            reasoning: 8,
            total: 200
        ))
        XCTAssertEqual(detailedThread.actualTaskDuration, 8.35, accuracy: 0.001)
        XCTAssertEqual(detailedThread.sessions.first?.completedTaskCount, 1)
        XCTAssertEqual(detailedThread.sessions.first?.abortedTaskCount, 1)
        XCTAssertEqual(detailedThread.sessions.first?.isActive, false)

        let fallbackThread = try XCTUnwrap(snapshot.threads.first { $0.id == "thread-fallback" })
        XCTAssertEqual(fallbackThread.tokens, LocalTokenUsage(total: 40))
        XCTAssertTrue(fallbackThread.sessions.isEmpty)

        XCTAssertTrue(snapshot.currentActivity.isActive)
        XCTAssertEqual(snapshot.currentActivity.activeThreadCount, 1)
        XCTAssertEqual(snapshot.currentActivity.activeThreadIDs, ["thread-active"])
        XCTAssertEqual(snapshot.currentActivity.activeProjectNames, ["Beta"])
    }

    func testUnchangedRolloutsUseMetadataOnlyPersistentCache() async throws {
        let fixture = try makeFixture()
        let firstScanner = LocalCodexScanner(
            codexHomeURL: fixture.codexHome,
            cacheDirectoryURL: fixture.cacheDirectory,
            readChunkSize: 4_096
        )
        let first = try await firstScanner.scan()
        XCTAssertEqual(first.scannedJSONLCount, 2)

        let secondScanner = LocalCodexScanner(
            codexHomeURL: fixture.codexHome,
            cacheDirectoryURL: fixture.cacheDirectory,
            readChunkSize: 4_096
        )
        let second = try await secondScanner.scan()

        XCTAssertEqual(second.cacheHitCount, 2)
        XCTAssertEqual(second.scannedJSONLCount, 0)
        XCTAssertEqual(second.tokens, first.tokens)
        XCTAssertEqual(second.actualTaskDuration, first.actualTaskDuration, accuracy: 0.001)

        let cacheURL = fixture.cacheDirectory.appendingPathComponent("local-usage-cache.json")
        let cacheHandle = try FileHandle(forReadingFrom: cacheURL)
        defer { try? cacheHandle.close() }
        let cacheData = try XCTUnwrap(try cacheHandle.readToEnd())
        let cacheText = try XCTUnwrap(String(data: cacheData, encoding: .utf8))
        XCTAssertFalse(cacheText.contains("PRIVATE_TITLE_SENTINEL"))
        XCTAssertFalse(cacheText.contains("PRIVATE_PREVIEW_SENTINEL"))
        XCTAssertFalse(cacheText.contains("PRIVATE_MESSAGE_SENTINEL"))
        XCTAssertFalse(cacheText.contains(String(repeating: "x", count: 128)))

        let detailedURL = fixture.codexHome
            .appendingPathComponent("sessions/detailed.jsonl")
        let writer = try FileHandle(forWritingTo: detailedURL)
        try writer.seekToEnd()
        try writer.write(contentsOf: Data("\n".utf8))
        try writer.close()

        let thirdScanner = LocalCodexScanner(
            codexHomeURL: fixture.codexHome,
            cacheDirectoryURL: fixture.cacheDirectory,
            readChunkSize: 4_096
        )
        let third = try await thirdScanner.scan()
        XCTAssertEqual(third.scannedJSONLCount, 1)
        XCTAssertEqual(third.cacheHitCount, 1)
    }
}

@available(macOS 14.0, *)
private extension LocalCodexScannerTests {
    struct Fixture {
        let codexHome: URL
        let cacheDirectory: URL
    }

    func makeFixture() throws -> Fixture {
        let root = try makeTemporaryDirectory()
        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome.appendingPathComponent("sessions", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

        let detailedURL = sessions.appendingPathComponent("detailed.jsonl")
        let activeURL = sessions.appendingPathComponent("active.jsonl")
        try writeJSONLLines(detailedFixtureLines(), to: detailedURL)
        try writeJSONLLines(activeFixtureLines(), to: activeURL)

        let databaseURL = codexHome.appendingPathComponent("state_7.sqlite")
        try createDatabase(
            at: databaseURL,
            rows: [
                (
                    id: "thread-detailed",
                    rolloutPath: detailedURL.path,
                    cwd: "/private/work/Alpha",
                    createdAt: 1_767_225_600,
                    updatedAt: 1_767_225_613,
                    tokens: 999,
                    archived: 0,
                    model: "gpt-test"
                ),
                (
                    id: "thread-fallback",
                    rolloutPath: sessions.appendingPathComponent("missing.jsonl").path,
                    cwd: "/another/location/Alpha",
                    createdAt: 1_767_225_500,
                    updatedAt: 1_767_225_510,
                    tokens: 40,
                    archived: 1,
                    model: nil
                ),
                (
                    id: "thread-active",
                    rolloutPath: activeURL.path,
                    cwd: "/private/work/Beta",
                    createdAt: 1_767_225_700,
                    updatedAt: Int64(Date().timeIntervalSince1970),
                    tokens: 9,
                    archived: 0,
                    model: "gpt-active"
                )
            ]
        )
        return Fixture(codexHome: codexHome, cacheDirectory: cache)
    }

    func detailedFixtureLines() -> [String] {
        let largeIrrelevantLine = "{\"type\":\"response_item\",\"payload\":{\"blob\":\""
            + String(repeating: "x", count: 200_000)
            + "\"}}"
        return [
            largeIrrelevantLine,
            #"{"timestamp":"2026-01-01T00:00:00.000Z","type":"turn_context","payload":{"model":"gpt-test"}}"#,
            #"{"timestamp":"2026-01-01T00:00:41.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"one","started_at":1767225601}}"#,
            #"{"timestamp":"2026-01-01T00:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10,"reasoning_output_tokens":4,"total_tokens":110}}}}"#,
            #"{"timestamp":"2026-01-01T00:00:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10,"reasoning_output_tokens":4,"total_tokens":110}}}}"#,
            #"{"timestamp":"2026-01-01T00:00:04.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":150,"cached_input_tokens":30,"output_tokens":25,"reasoning_output_tokens":8,"total_tokens":175}}}}"#,
            #"{"timestamp":"2026-01-01T00:00:56.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"one","started_at":1767225601,"completed_at":1767225606,"duration_ms":5250}}"#,
            #"{"timestamp":1767225650000,"type":"task_started","payload":{"task_id":"two","started_at":1767225610}}"#,
            #"{"timestamp":"1767225611000","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":"20","cached_input_tokens":"5","output_tokens":"5","reasoning_output_tokens":null,"total_tokens":"25"}}}}"#,
            #"{"timestamp":1767225693000000,"type":"event_msg","payload":{"type":"turn_aborted","task_id":"two","started_at":1767225610,"completed_at":1767225613,"duration_ms":"3100"}}"#,
            #"{"type":"response_item","payload":{"type":"message","content":"PRIVATE_MESSAGE_SENTINEL token_count"}}"#
        ]
    }

    func activeFixtureLines() -> [String] {
        [
            #"{"timestamp":1767225700,"type":"turn_context","payload":{}}"#,
            #"{"timestamp":"2026-01-01T00:01:41Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-01-01T00:01:42Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":7,"cached_input_tokens":null,"output_tokens":2,"total_tokens":9}}}}"#
        ]
    }

    func writeJSONLLines(_ lines: [String], to url: URL) throws {
        let data = try XCTUnwrap((lines.joined(separator: "\n") + "\n").data(using: .utf8))
        try data.write(to: url)
    }

    func createDatabase(
        at url: URL,
        rows: [(
            id: String,
            rolloutPath: String,
            cwd: String,
            createdAt: Int64,
            updatedAt: Int64,
            tokens: Int64,
            archived: Int64,
            model: String?
        )]
    ) throws {
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &connection), SQLITE_OK)
        let database = try XCTUnwrap(connection)
        defer { sqlite3_close_v2(database) }

        let schema = """
        CREATE TABLE threads (
            id TEXT PRIMARY KEY,
            rollout_path TEXT NOT NULL,
            cwd TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            created_at_ms INTEGER,
            updated_at_ms INTEGER,
            tokens_used INTEGER NOT NULL DEFAULT 0,
            archived INTEGER NOT NULL DEFAULT 0,
            model TEXT,
            title TEXT NOT NULL,
            preview TEXT NOT NULL,
            first_user_message TEXT NOT NULL
        );
        """
        try execute(schema, on: database)

        for row in rows {
            let modelSQL = row.model.map(sqliteQuote) ?? "NULL"
            let insert = """
            INSERT INTO threads (
                id, rollout_path, cwd, created_at, updated_at,
                created_at_ms, updated_at_ms, tokens_used, archived, model,
                title, preview, first_user_message
            ) VALUES (
                \(sqliteQuote(row.id)),
                \(sqliteQuote(row.rolloutPath)),
                \(sqliteQuote(row.cwd)),
                \(row.createdAt),
                \(row.updatedAt),
                \(row.createdAt * 1000),
                \(row.updatedAt * 1000),
                \(row.tokens),
                \(row.archived),
                \(modelSQL),
                'PRIVATE_TITLE_SENTINEL',
                'PRIVATE_PREVIEW_SENTINEL',
                'PRIVATE_MESSAGE_SENTINEL'
            );
            """
            try execute(insert, on: database)
        }
    }

    func execute(_ sql: String, on connection: OpaquePointer) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(connection, sql, nil, nil, &errorPointer)
        defer { sqlite3_free(errorPointer) }
        if status != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "SQLite error \(status)"
            throw NSError(domain: "LocalCodexScannerTests", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
    }

    func sqliteQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPulseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        temporaryDirectories.append(url)
        return url
    }
}
