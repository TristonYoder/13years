// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class RehearsalTimesTests: XCTestCase {
    func testManualRehearsalTimesKeepTheirNamesAndFeedRehearsalMode() throws {
        let engine = CueEngine()
        let added = try XCTUnwrap(engine.addRehearsalTime(name: " Band Rehearsal ", day: .weekday(6), startTime: TimeOfDay(hour: 19, minute: 0)))
        XCTAssertEqual(engine.rehearsalPlanTimes.map(\.name), ["Band Rehearsal"])
        XCTAssertTrue(engine.setRehearsalMode(true, planTimeId: added.id))
        XCTAssertTrue(engine.isRehearsalMode)
        XCTAssertEqual(engine.rehearsalLabel, "Rehearsal \u{00B7} Band Rehearsal")
        engine.removeRehearsalTime(id: added.id)
        XCTAssertFalse(engine.isRehearsalMode)
        XCTAssertTrue(engine.rehearsalPlanTimes.isEmpty)
    }

    func testManualRehearsalTimesSurviveADocumentRoundTrip() throws {
        let engine = CueEngine()
        engine.addRehearsalTime(name: "Tech", day: nil, startTime: TimeOfDay(hour: 18, minute: 30))
        let data = try JSONEncoder().encode(engine.makeDocument())
        let decoded = try JSONDecoder().decode(ProducerDocument.self, from: data)
        XCTAssertEqual(decoded.rehearsalTimes?.first?.name, "Tech")
    }

    func testItemProgressFollowsTheActiveItemAndCapsAtFull() {
        let engine = CueEngine()
        XCTAssertEqual(engine.itemProgress, 0)
        engine.importFlow(title: nil, items: [
            PCOTimerItem(id: "a", title: "A", itemType: "Item", lengthInSeconds: 60),
            PCOTimerItem(id: "b", title: "B", itemType: "Item", lengthInSeconds: 120)
        ])
        XCTAssertEqual(engine.itemProgress, 0, accuracy: 0.001)
        engine.activeTimerItem?.elapsedSeconds = 30
        XCTAssertEqual(engine.itemProgress, 0.5, accuracy: 0.001)
        engine.activeTimerItem?.elapsedSeconds = 90
        XCTAssertEqual(engine.itemProgress, 1, accuracy: 0.001)
        engine.nextPlanItem(startTimer: false)
        XCTAssertEqual(engine.itemProgress, 0, accuracy: 0.001)
    }

    func testRehearsalTimeCommandsBuildTheExpectedRequests() {
        let create = RemoteCommand.rehearsalTimeCreate(name: "Tech", day: nil, startTime: "18:30").request
        XCTAssertEqual(create.method, "POST")
        XCTAssertEqual(create.path, "/v1/rehearsal-times")
        let delete = RemoteCommand.rehearsalTimeDelete(id: "x y").request
        XCTAssertEqual(delete.method, "DELETE")
        XCTAssertEqual(delete.path, "/v1/rehearsal-times/x%20y")
    }

    func testRehearsalTimesAreManagedThroughTheControlAPI() throws {
        let engine = CueEngine()
        let router = ControlAPIRouter(engine: engine)
        func call(_ method: String, _ path: String, _ json: String? = nil) -> HTTPResponse {
            router.handle(HTTPRequest(method: method, path: path, body: Data((json ?? "").utf8)))
        }

        let created = call("POST", "/v1/rehearsal-times", #"{"name":"Band","day":"Friday","startTime":"19:00"}"#)
        XCTAssertEqual(created.status, 201)
        let entry = try XCTUnwrap(JSONSerialization.jsonObject(with: created.body) as? [String: Any])
        let id = try XCTUnwrap(entry["id"] as? String)
        XCTAssertEqual(engine.manualRehearsalTimes.map(\.name), ["Band"])

        XCTAssertEqual(call("PATCH", "/v1/rehearsal-times/\(id)", #"{"name":"Full Band"}"#).status, 200)
        XCTAssertEqual(engine.manualRehearsalTimes.first?.name, "Full Band")
        XCTAssertEqual(engine.manualRehearsalTimes.first?.startTime?.string, "19:00")

        XCTAssertEqual(call("GET", "/v1/rehearsal-times").status, 200)
        XCTAssertEqual(call("DELETE", "/v1/rehearsal-times/\(id)").status, 200)
        XCTAssertTrue(engine.manualRehearsalTimes.isEmpty)
        XCTAssertEqual(call("GET", "/v1/rehearsal-times/\(id)").status, 404)
    }
}
