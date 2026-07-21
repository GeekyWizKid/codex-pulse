import Foundation
import XCTest
@testable import CodexPulse

final class CodexRadarTests: XCTestCase {
    func testFixtureAggregationRanksRowsAndFiltersInvalidRunnerFields() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = try CodexRadarService.decodeSnapshot(
            from: Self.tableFixture,
            fetchedAt: fetchedAt,
            sourceURL: URL(string: "https://example.test/table")!
        )

        XCTAssertEqual(snapshot.metadata.schema, 1)
        XCTAssertEqual(snapshot.metadata.fetchedAt, fetchedAt)
        XCTAssertEqual(snapshot.metadata.taskCount, 3)
        XCTAssertEqual(snapshot.metadata.comboCount, 2)
        XCTAssertEqual(snapshot.metadata.cellCount, 5)
        XCTAssertEqual(snapshot.metadata.onlineVolunteers, 7)
        XCTAssertEqual(snapshot.metadata.tierWindowsUSD["plus"], 97.25)
        XCTAssertNil(snapshot.metadata.tierWindowsUSD["invalid"])
        XCTAssertNotNil(snapshot.metadata.baselineGeneratedAt)
        XCTAssertNotNil(snapshot.metadata.discriminationGeneratedAt)

        XCTAssertEqual(snapshot.rows.map(\.rank), [1, 2])
        XCTAssertEqual(snapshot.rows.first?.model, "beta")
        XCTAssertEqual(snapshot.rows.first?.effort, .unknown("experimental"))

        let alpha = try XCTUnwrap(snapshot.rows.first { $0.model == "alpha" })
        XCTAssertEqual(try XCTUnwrap(alpha.liveIQ), 75, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(alpha.recentIQ), 112.5, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(alpha.longTermIQ), 90, accuracy: 0.000_001)
        XCTAssertEqual(alpha.liveSampleCount, 2)
        XCTAssertEqual(alpha.recentSampleCount, 4)
        XCTAssertEqual(alpha.longTermSampleCount, 10)
        XCTAssertEqual(alpha.coveredTaskCount, 2)
        XCTAssertEqual(alpha.coverage, 2.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(alpha.meanRecentDurationSeconds), 15, accuracy: 0.000_001)
        XCTAssertEqual(alpha.durationSampleCount, 2)
        XCTAssertEqual(try XCTUnwrap(alpha.meanRecentCostUSD), 2, accuracy: 0.000_001)
        XCTAssertEqual(alpha.costSampleCount, 2)
        XCTAssertEqual(alpha.reportedCostSampleCount, 1)
        XCTAssertEqual(alpha.costQuality, .mixed)

        let beta = try XCTUnwrap(snapshot.rows.first { $0.model == "beta" })
        XCTAssertEqual(try XCTUnwrap(beta.liveIQ), 150, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(beta.recentIQ), 150, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(beta.longTermIQ), 150, accuracy: 0.000_001)
        XCTAssertEqual(beta.coverage, 1.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(beta.costQuality, .unavailable)
    }

    func testMissingFieldsUnknownEnumsAndMalformedCellsDoNotFailTableDecode() throws {
        let data = Data(
            """
            {
              "schema": "1",
              "combos": [
                {"model": "future-model", "effort": 99},
                {},
                "malformed-combo"
              ],
              "tasks": [{}, {"id": ""}],
              "cells": {"not-a-real-cell": "malformed-cell"},
              "baseline_generated_at": null,
              "online_volunteers": "4"
            }
            """.utf8
        )

        let snapshot = try CodexRadarService.decodeSnapshot(from: data)

        XCTAssertEqual(snapshot.metadata.schema, 1)
        XCTAssertEqual(snapshot.metadata.onlineVolunteers, 4)
        XCTAssertEqual(snapshot.metadata.taskCount, 0)
        XCTAssertEqual(snapshot.rows.count, 1)
        XCTAssertEqual(snapshot.rows[0].effort, .unknown("99"))
        XCTAssertNil(snapshot.rows[0].liveIQ)
        XCTAssertNil(snapshot.rows[0].recentIQ)
        XCTAssertNil(snapshot.rows[0].longTermIQ)
        XCTAssertEqual(snapshot.rows[0].coverage, 0)
    }

    func testEncodedSnapshotNeverContainsContributorIdentity() throws {
        let snapshot = try CodexRadarService.decodeSnapshot(from: Self.tableFixture)
        let encoded = try JSONEncoder().encode(snapshot)
        let string = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertFalse(string.contains("private-login"))
        XCTAssertFalse(string.contains("private-nickname"))
        XCTAssertFalse(string.contains("avatars.example.test"))
    }

    @MainActor
    func testRefreshThrottlesForSixtySecondsAndPreservesLastGoodSnapshot() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RadarStubURLProtocol.self]
        configuration.urlCache = URLCache(memoryCapacity: 1_024, diskCapacity: 0)
        let session = URLSession(configuration: configuration)

        RadarStubURLProtocol.reset(
            responses: [
                RadarStubResponse(statusCode: 200, data: Self.tableFixture),
                RadarStubResponse(statusCode: 503, data: Data("{}".utf8))
            ]
        )
        defer { RadarStubURLProtocol.reset() }

        let service = CodexRadarService(
            endpoint: URL(string: "https://example.test/table")!,
            session: session
        )
        XCTAssertEqual(service.refreshInterval, 60)

        let firstResult = await service.refresh(force: true)
        let goodSnapshot = try XCTUnwrap(firstResult)
        XCTAssertEqual(RadarStubURLProtocol.requests.count, 1)
        let firstRequest = try XCTUnwrap(RadarStubURLProtocol.requests.first)
        XCTAssertEqual(firstRequest.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(firstRequest.value(forHTTPHeaderField: "Cache-Control"), "no-cache")

        let throttledResult = await service.refresh()
        let throttledSnapshot = try XCTUnwrap(throttledResult)
        XCTAssertEqual(throttledSnapshot, goodSnapshot)
        XCTAssertEqual(RadarStubURLProtocol.requests.count, 1)

        let failedResult = await service.refresh(force: true)
        let preservedSnapshot = try XCTUnwrap(failedResult)
        XCTAssertEqual(RadarStubURLProtocol.requests.count, 2)
        XCTAssertEqual(preservedSnapshot, goodSnapshot)
        XCTAssertEqual(service.snapshot, goodSnapshot)
        XCTAssertEqual(service.lastError, "CodexRadar 请求失败（HTTP 503）")
    }

    private static let tableFixture = Data(
        """
        {
          "schema": 1,
          "combos": [
            {"model": "alpha", "effort": "high"},
            {"model": "beta", "effort": "experimental"},
            {"model": "alpha", "effort": "high"},
            {"effort": "low"}
          ],
          "tier_windows_usd": {"plus": "97.25", "invalid": "not-a-number"},
          "tasks": [
            {"id": "t1", "title": "One"},
            {"id": "t2", "title": "Two"},
            {"id": "t3", "title": "Three"},
            {"id": "t1"},
            {}
          ],
          "cells": {
            "t1|alpha|high": {
              "st": "open",
              "n": 2,
              "p": 2,
              "total_n": 4,
              "total_p": 3,
              "last_graded_at": "2026-07-21T17:00:59.767296+00:00",
              "ran_by": [
                {
                  "login": "private-login",
                  "avatar_url": "https://avatars.example.test/user",
                  "passed": true,
                  "graded_at": "2026-07-21T17:00:59.767296+00:00",
                  "duration_sec": 10,
                  "actual_cost_usd": 1,
                  "cost_source": "reported"
                },
                {
                  "nickname": "private-nickname",
                  "passed": false,
                  "graded_at": "2026-07-21T16:00:00+00:00",
                  "duration_sec": -4,
                  "actual_cost_usd": "invalid",
                  "cost_source": "new-source"
                }
              ]
            },
            "t2|alpha|high": {
              "st": "future-state",
              "n": "2",
              "p": "1",
              "total_n": 6,
              "total_p": 3,
              "ran_by": [
                {
                  "passed": false,
                  "graded_at": "2026-07-21T17:00:59Z",
                  "duration_sec": "20",
                  "actual_cost_usd": "3",
                  "cost_source": "tokens"
                }
              ]
            },
            "t3|alpha|high": {
              "n": 2,
              "p": 3,
              "total_n": -1,
              "total_p": 0,
              "ran_by": [
                {"duration_sec": -1, "actual_cost_usd": -2}
              ]
            },
            "t1|beta|experimental": {
              "n": 1,
              "p": 1,
              "total_n": 1,
              "total_p": 1,
              "ran_by": [
                {"passed": true, "duration_sec": 12.5}
              ]
            },
            "unused|beta|experimental": {
              "n": 100,
              "p": 0,
              "total_n": 100,
              "total_p": 0,
              "ran_by": [{"passed": false}]
            }
          },
          "baseline_generated_at": "2026-07-21T17:00:59.767296+00:00",
          "discrimination_generated_at": "2026-07-20T20:10:08+00:00",
          "discrimination_method": "task-discrimination-v2",
          "reopen_after_hours": 18,
          "online_volunteers": 7,
          "k": 1
        }
        """.utf8
    )
}

private struct RadarStubResponse {
    let statusCode: Int
    let data: Data
}

private final class RadarStubState: @unchecked Sendable {
    private let lock = NSLock()
    private var queuedResponses: [RadarStubResponse] = []
    private var recordedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    func reset(responses: [RadarStubResponse] = []) {
        lock.withLock {
            queuedResponses = responses
            recordedRequests = []
        }
    }

    func consume(request: URLRequest) throws -> (HTTPURLResponse, Data) {
        try lock.withLock {
            recordedRequests.append(request)
            guard !queuedResponses.isEmpty else { throw URLError(.resourceUnavailable) }
            let stub = queuedResponses.removeFirst()
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: stub.statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badServerResponse)
            }
            return (response, stub.data)
        }
    }
}

private final class RadarStubURLProtocol: URLProtocol {
    private static let state = RadarStubState()

    static var requests: [URLRequest] { state.requests }

    static func reset(responses: [RadarStubResponse] = []) {
        state.reset(responses: responses)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.state.consume(request: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
