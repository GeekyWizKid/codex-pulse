import Foundation
import XCTest
@testable import CodexPulse

final class CodexAppServerClientTests: XCTestCase {
    @MainActor
    func testHandshakeAndRefreshUseStableWireMethodsAndDecodeFixtures() async throws {
        let transport = FixtureTransport(mode: .successful)
        let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let client = makeClient(transport: transport, now: observedAt)

        try await client.connect()
        let snapshot = try await client.refresh()

        XCTAssertEqual(client.connectionState, .connected)
        XCTAssertNil(client.lastError)
        XCTAssertEqual(snapshot.rateLimits?.planType, .pro)
        XCTAssertEqual(snapshot.rateLimits?.primary?.usedPercent, 72.5)
        XCTAssertEqual(snapshot.rateLimits?.primary?.remainingPercent, 27.5)
        XCTAssertEqual(snapshot.rateLimits?.primary?.windowDurationMins, 300)
        XCTAssertEqual(
            snapshot.rateLimits?.primary?.resetsAt,
            Date(timeIntervalSince1970: 1_800_003_600)
        )
        XCTAssertEqual(snapshot.rateLimits?.secondary?.windowDurationMins, 10_080)
        XCTAssertEqual(snapshot.rateLimits?.credits?.balance, "$12.34")
        XCTAssertEqual(snapshot.summary?.lifetimeTokens, 9_876_543)
        XCTAssertEqual(snapshot.summary?.peakDailyTokens, 321_000)
        XCTAssertEqual(snapshot.summary?.currentStreakDays, 4)
        XCTAssertEqual(snapshot.dailyUsageBuckets.count, 2)
        XCTAssertEqual(snapshot.dailyUsageBuckets.last?.tokens, 22_222)
        XCTAssertEqual(snapshot.lastUpdatedAt, observedAt)

        let sent = transport.sentObjects
        XCTAssertEqual(sent.compactMap(\.method), [
            "initialize",
            "initialized",
            "account/rateLimits/read",
            "account/usage/read"
        ])
        XCTAssertEqual(sent[0].id, 1)
        XCTAssertEqual(sent[0].clientName, "codex_pulse")
        XCTAssertNil(sent[0].jsonrpc, "app-server intentionally omits the JSON-RPC header on the wire")
        XCTAssertNil(sent[1].id, "initialized is a notification")
        XCTAssertNil(sent[2].params, "account/rateLimits/read has undefined params")
        XCTAssertNil(sent[3].params, "account/usage/read has undefined params")

        client.disconnect()
        XCTAssertEqual(client.connectionState, .disconnected)
        XCTAssertEqual(transport.stopCount, 1)
    }

    @MainActor
    func testSparseRateLimitNotificationPreservesMetadataAndMergesUsage() async throws {
        let transport = FixtureTransport(mode: .successful)
        let client = makeClient(transport: transport)
        try await client.connect()
        _ = try await client.refresh()

        transport.emitSparseRateLimitUpdate(usedPercent: 81)
        await eventually {
            client.snapshot.rateLimits?.primary?.usedPercent == 81
        }

        let rateLimits = try XCTUnwrap(client.snapshot.rateLimits)
        XCTAssertEqual(rateLimits.primary?.remainingPercent, 19)
        XCTAssertEqual(rateLimits.primary?.windowDurationMins, 300)
        XCTAssertEqual(rateLimits.primary?.resetsAt, Date(timeIntervalSince1970: 1_800_003_600))
        XCTAssertEqual(rateLimits.limitName, "Codex")
        XCTAssertEqual(rateLimits.planType, .pro)
        XCTAssertEqual(rateLimits.credits?.balance, "$12.34")
        XCTAssertEqual(client.snapshot.rateLimitsByLimitID["codex"]?.primary?.usedPercent, 81)
    }

    @MainActor
    func testInitializeTimeoutFailsDeterministicallyAndStopsTransport() async {
        let transport = FixtureTransport(mode: .neverRespondToInitialize)
        let client = makeClient(transport: transport, timeout: 0.01)

        do {
            try await client.connect()
            XCTFail("Expected initialize to time out")
        } catch {
            XCTAssertEqual(
                error as? CodexAppServerClientError,
                .requestTimedOut(method: "initialize")
            )
        }

        XCTAssertEqual(client.connectionState, .failed)
        XCTAssertEqual(client.lastError, .requestTimedOut(method: "initialize"))
        XCTAssertEqual(transport.stopCount, 1)
    }

    @MainActor
    func testProcessTerminationFailsOutstandingRequest() async throws {
        let transport = FixtureTransport(mode: .terminateOnRateLimitRead(status: 17))
        let client = makeClient(transport: transport, timeout: 1)
        try await client.connect()

        do {
            _ = try await client.refresh()
            XCTFail("Expected process termination")
        } catch {
            XCTAssertEqual(
                error as? CodexAppServerClientError,
                .processTerminated(status: 17)
            )
        }

        XCTAssertEqual(client.connectionState, .failed)
        XCTAssertEqual(client.lastError, .processTerminated(status: 17))
    }

    func testParserPreservesLargeIntegerUsageAndRPCError() throws {
        let parser = JSONCodexAppServerMessageParser()
        let usageLine = Data(#"{"id":42,"result":{"summary":{"lifetimeTokens":9007199254740993,"peakDailyTokens":null,"longestRunningTurnSec":60,"currentStreakDays":3,"longestStreakDays":8},"dailyUsageBuckets":[{"startDate":"2026-07-21","tokens":9007199254740993}]}}"#.utf8)
        let message = try parser.parse(line: usageLine)
        let result = try XCTUnwrap(message.result)
        let resultData = try JSONEncoder().encode(result)
        let usage = try JSONDecoder().decode(CodexAccountUsageResponse.self, from: resultData)

        XCTAssertEqual(message.id, .integer(42))
        XCTAssertEqual(usage.summary.lifetimeTokens, 9_007_199_254_740_993)
        XCTAssertEqual(usage.dailyUsageBuckets?.first?.tokens, 9_007_199_254_740_993)

        let errorLine = Data(#"{"id":7,"error":{"code":-32000,"message":"Not initialized"}}"#.utf8)
        let errorMessage = try parser.parse(line: errorLine)
        XCTAssertEqual(
            errorMessage.error,
            CodexAppServerRPCError(code: -32_000, message: "Not initialized")
        )
    }

    func testQuotaRemainingIsClamped() {
        XCTAssertEqual(
            CodexQuotaWindow(usedPercent: -5, windowDurationMins: nil, resetsAt: nil)
                .remainingPercent,
            100
        )
        XCTAssertEqual(
            CodexQuotaWindow(usedPercent: 120, windowDurationMins: nil, resetsAt: nil)
                .remainingPercent,
            0
        )
    }

    @MainActor
    private func makeClient(
        transport: FixtureTransport,
        timeout: TimeInterval = 1,
        now: Date = Date(timeIntervalSince1970: 1_800_000_001)
    ) -> CodexAppServerClient {
        CodexAppServerClient(
            executableResolver: FixedExecutableResolver(),
            transportFactory: { _ in transport },
            requestTimeout: timeout,
            clientVersion: "1.2.3",
            now: { now }
        )
    }

    @MainActor
    private func eventually(
        attempts: Int = 100,
        condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not satisfied")
    }
}
private struct FixedExecutableResolver: CodexExecutableResolving {
    func resolveCodexExecutable() throws -> URL {
        URL(fileURLWithPath: "/usr/bin/true")
    }
}

private final class FixtureTransport: CodexAppServerTransport, @unchecked Sendable {
    enum Mode {
        case successful
        case neverRespondToInitialize
        case terminateOnRateLimitRead(status: Int32)
    }

    struct SentObject: Equatable {
        let object: [String: CodexJSONValue]

        var method: String? {
            guard case let .string(value)? = object["method"] else { return nil }
            return value
        }

        var id: Int? {
            guard let value = object["id"] else { return nil }
            switch value {
            case let .integer(value): return Int(exactly: value)
            case let .unsignedInteger(value): return Int(exactly: value)
            default: return nil
            }
        }

        var params: CodexJSONValue? { object["params"] }
        var jsonrpc: CodexJSONValue? { object["jsonrpc"] }

        var clientName: String? {
            guard case let .object(params)? = params,
                  case let .object(clientInfo)? = params["clientInfo"],
                  case let .string(name)? = clientInfo["name"]
            else { return nil }
            return name
        }
    }

    private let mode: Mode
    private let lock = NSLock()
    private var onLine: (@Sendable (Data) -> Void)?
    private var onTermination: (@Sendable (CodexAppServerTransportTermination) -> Void)?
    private var storage: [SentObject] = []
    private var stops = 0

    init(mode: Mode) {
        self.mode = mode
    }

    var sentObjects: [SentObject] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var stopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return stops
    }

    func start(
        onLine: @escaping @Sendable (Data) -> Void,
        onTermination: @escaping @Sendable (CodexAppServerTransportTermination) -> Void
    ) throws {
        lock.lock()
        self.onLine = onLine
        self.onTermination = onTermination
        lock.unlock()
    }

    func send(line: Data) throws {
        let value = try JSONDecoder().decode(CodexJSONValue.self, from: line)
        guard case let .object(object) = value else {
            throw CodexAppServerClientError.invalidResponse
        }
        let sent = SentObject(object: object)

        lock.lock()
        storage.append(sent)
        let lineCallback = onLine
        let terminationCallback = onTermination
        lock.unlock()

        guard let method = sent.method else { return }
        switch (mode, method) {
        case (.neverRespondToInitialize, "initialize"):
            return
        case let (.terminateOnRateLimitRead(status), "account/rateLimits/read"):
            terminationCallback?(.exited(status: status))
        case (_, "initialize"):
            lineCallback?(response(
                id: try XCTUnwrap(sent.id),
                result: .object([
                    "userAgent": .string("fixture"),
                    "codexHome": .string("/fixture"),
                    "platformFamily": .string("unix"),
                    "platformOs": .string("macos")
                ])
            ))
        case (_, "account/rateLimits/read"):
            lineCallback?(response(id: try XCTUnwrap(sent.id), result: Self.rateLimitsFixture))
        case (_, "account/usage/read"):
            lineCallback?(response(id: try XCTUnwrap(sent.id), result: Self.usageFixture))
        default:
            break
        }
    }

    func stop() {
        lock.lock()
        stops += 1
        lock.unlock()
    }

    func emitSparseRateLimitUpdate(usedPercent: Double) {
        lock.lock()
        let callback = onLine
        lock.unlock()
        let notification: CodexJSONValue = .object([
            "method": .string("account/rateLimits/updated"),
            "params": .object([
                "rateLimits": .object([
                    "limitId": .string("codex"),
                    "primary": .object(["usedPercent": .number(usedPercent)])
                ])
            ])
        ])
        callback?(try! JSONEncoder().encode(notification))
    }

    private func response(id: Int, result: CodexJSONValue) -> Data {
        try! JSONEncoder().encode(CodexJSONValue.object([
            "id": .integer(Int64(id)),
            "result": result
        ]))
    }

    private static let rateLimitsFixture: CodexJSONValue = .object([
        "rateLimits": .object([
            "limitId": .string("codex"),
            "limitName": .string("Codex"),
            "primary": .object([
                "usedPercent": .number(72.5),
                "windowDurationMins": .integer(300),
                "resetsAt": .integer(1_800_003_600)
            ]),
            "secondary": .object([
                "usedPercent": .integer(20),
                "windowDurationMins": .integer(10_080),
                "resetsAt": .integer(1_800_604_800)
            ]),
            "credits": .object([
                "hasCredits": .bool(true),
                "unlimited": .bool(false),
                "balance": .string("$12.34")
            ]),
            "individualLimit": .object([
                "limit": .string("$50"),
                "used": .string("$10"),
                "remainingPercent": .integer(80),
                "resetsAt": .integer(1_802_592_000)
            ]),
            "planType": .string("pro"),
            "rateLimitReachedType": .null
        ]),
        "rateLimitsByLimitId": .object([
            "codex": .object([
                "limitId": .string("codex"),
                "limitName": .string("Codex"),
                "primary": .object([
                    "usedPercent": .number(72.5),
                    "windowDurationMins": .integer(300),
                    "resetsAt": .integer(1_800_003_600)
                ]),
                "planType": .string("pro")
            ])
        ]),
        "rateLimitResetCredits": .null
    ])

    private static let usageFixture: CodexJSONValue = .object([
        "summary": .object([
            "lifetimeTokens": .integer(9_876_543),
            "peakDailyTokens": .integer(321_000),
            "longestRunningTurnSec": .integer(7_200),
            "currentStreakDays": .integer(4),
            "longestStreakDays": .integer(11)
        ]),
        "dailyUsageBuckets": .array([
            .object([
                "startDate": .string("2026-07-20"),
                "tokens": .integer(11_111)
            ]),
            .object([
                "startDate": .string("2026-07-21"),
                "tokens": .integer(22_222)
            ])
        ])
    ])
}
