// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class TimerColorScaleTests: XCTestCase {
    private let scale = TimerColorScale(
        onTimeHex: "34C759",
        stops: [
            TimerColorStop(value: 25, unit: .percent, colorHex: "FFD60A"),
            TimerColorStop(value: 30, unit: .seconds, colorHex: "FF9500")
        ],
        overtimeHex: "CC1717"
    )

    func testColorFollowsTheNearestReachedStop() {
        // A 5:00 item: 25% is 75 s, so yellow from 75 s left, orange from 30 s, red past zero.
        XCTAssertEqual(scale.colorHex(remainingSeconds: 200, lengthSeconds: 300), "34C759")
        XCTAssertEqual(scale.colorHex(remainingSeconds: 75, lengthSeconds: 300), "FFD60A")
        XCTAssertEqual(scale.colorHex(remainingSeconds: 30, lengthSeconds: 300), "FF9500")
        XCTAssertEqual(scale.colorHex(remainingSeconds: 0, lengthSeconds: 300), "FF9500")
        XCTAssertEqual(scale.colorHex(remainingSeconds: -1, lengthSeconds: 300), "CC1717")
    }

    func testStandardKeepsNormalTextUntilOvertime() {
        XCTAssertNil(TimerColorScale.standard.colorHex(remainingSeconds: 5, lengthSeconds: 300))
        XCTAssertEqual(TimerColorScale.standard.colorHex(remainingSeconds: -3, lengthSeconds: 300), "CC1717")
        XCTAssertTrue(TimerColorScale.standard.isStandard)
    }

    func testPercentThresholdsScaleWithItemLength() {
        // 25% of 30:00 is 450 s.
        XCTAssertEqual(scale.colorHex(remainingSeconds: 500, lengthSeconds: 1800), "34C759")
        XCTAssertEqual(scale.colorHex(remainingSeconds: 450, lengthSeconds: 1800), "FFD60A")
        XCTAssertEqual(scale.colorHex(remainingSeconds: 20, lengthSeconds: 1800), "FF9500")
    }

    func testEmptyJSONDecodesAsTheStandardScale() throws {
        let decoded = try JSONDecoder().decode(TimerColorScale.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, .standard)
    }

    func testItemOverrideBeatsWaypointBeatsGlobal() throws {
        let engine = CueEngine()
        engine.timerColorScale = TimerColorScale(onTimeHex: "111111")
        let waypoint = try XCTUnwrap(engine.addWaypoint(name: "Color Test \(UUID().uuidString.prefix(8))"))
        engine.importFlow(title: nil, items: [PCOTimerItem(id: "a", title: "A", itemType: "Item", lengthInSeconds: 60, waypointIds: [waypoint.id])])
        let item = engine.planItems[0]
        XCTAssertEqual(engine.timerColorScale(for: item).onTimeHex, "111111")

        engine.setWaypointTimerColors(id: waypoint.id, TimerColorScale(onTimeHex: "222222"))
        XCTAssertEqual(engine.timerColorScale(for: engine.planItems[0]).onTimeHex, "222222")

        engine.setItemTimerColors(id: "a", TimerColorScale(onTimeHex: "333333"))
        XCTAssertEqual(engine.timerColorScale(for: engine.planItems[0]).onTimeHex, "333333")
        XCTAssertEqual(engine.timerColorHex(for: engine.planItems[0]), "333333")

        engine.setItemTimerColors(id: "a", nil)
        engine.setWaypointTimerColors(id: waypoint.id, nil)
        XCTAssertEqual(engine.timerColorScale(for: engine.planItems[0]).onTimeHex, "111111")
    }

    func testOnlyCustomizedScalesGoToPagers() {
        let engine = CueEngine()
        engine.importFlow(title: nil, items: [PCOTimerItem(id: "a", title: "A", itemType: "Item", lengthInSeconds: 60)])
        XCTAssertNil(engine.pagerTimerColors)
        engine.setTimerColorScale(scale)
        XCTAssertEqual(engine.pagerTimerColors, scale)
        let packet = CuePacket(type: .timerUpdate, senderId: "x", timerItem: engine.planItems[0])
        var withColors = packet
        withColors.timerColors = scale
        let decoded = try? JSONDecoder().decode(CuePacket.self, from: JSONEncoder().encode(withColors))
        XCTAssertEqual(decoded?.timerColors, scale)
        XCTAssertNil(try? JSONDecoder().decode(CuePacket.self, from: JSONEncoder().encode(packet)).timerColors)
    }

    func testScaleSurvivesADocumentRoundTripAndTheControlAPI() throws {
        let engine = CueEngine()
        engine.setTimerColorScale(scale)
        let data = try JSONEncoder().encode(engine.makeDocument())
        XCTAssertEqual(try JSONDecoder().decode(ProducerDocument.self, from: data).settings.timerColors, scale)

        let apiEngine = CueEngine()
        let router = ControlAPIRouter(engine: apiEngine)
        let body = try JSONEncoder().encode(["timerColors": scale])
        let reply = router.handle(HTTPRequest(method: "PUT", path: "/v1/settings", body: body))
        XCTAssertEqual(reply.status, 200)
        XCTAssertEqual(apiEngine.timerColorScale, scale)
        let bad = router.handle(HTTPRequest(method: "PUT", path: "/v1/settings", body: Data(#"{"timerColors":{"overtimeHex":"nope"}}"#.utf8)))
        XCTAssertEqual(bad.status, 400)
    }
}
