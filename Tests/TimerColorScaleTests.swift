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

    func testStandardIsYellowAtTenPercentThenRedFlickerThenPulse() {
        let standard = TimerColorScale.standard
        XCTAssertNil(standard.colorHex(remainingSeconds: 200, lengthSeconds: 300))
        XCTAssertEqual(standard.style(remainingSeconds: 30, lengthSeconds: 300).colorHex, "FFD60A")
        XCTAssertEqual(standard.style(remainingSeconds: 30, lengthSeconds: 300).effect, TimerEffect.none)
        XCTAssertEqual(standard.style(remainingSeconds: -1, lengthSeconds: 300).colorHex, "CC1717")
        XCTAssertEqual(standard.style(remainingSeconds: -1, lengthSeconds: 300).effect, .flicker)
        XCTAssertEqual(standard.style(remainingSeconds: -3, lengthSeconds: 300).effect, .pulse)
        XCTAssertTrue(standard.isStandard)
    }

    func testPercentThresholdsScaleWithItemLength() {
        // 25% of 30:00 is 450 s.
        XCTAssertEqual(scale.colorHex(remainingSeconds: 500, lengthSeconds: 1800), "34C759")
        XCTAssertEqual(scale.colorHex(remainingSeconds: 450, lengthSeconds: 1800), "FFD60A")
        XCTAssertEqual(scale.colorHex(remainingSeconds: 20, lengthSeconds: 1800), "FF9500")
    }

    func testStopsAndOvertimeCarryEffectsAndOlderScalesDefaultToNone() throws {
        let scale = TimerColorScale(
            stops: [TimerColorStop(value: 20, unit: .seconds, colorHex: "FFD60A", effect: .blink)],
            overtimeHex: "CC1717",
            overtimeEffect: .glitch
        )
        XCTAssertEqual(scale.style(remainingSeconds: 10, lengthSeconds: 300).effect, .blink)
        XCTAssertEqual(scale.style(remainingSeconds: 100, lengthSeconds: 300).effect, .none)
        XCTAssertEqual(scale.style(remainingSeconds: -1, lengthSeconds: 300).effect, .glitch)

        let decoded = try JSONDecoder().decode(TimerColorScale.self, from: JSONEncoder().encode(scale))
        XCTAssertEqual(decoded.stops.first?.effect, .blink)
        XCTAssertEqual(decoded.overtimeEffect, .glitch)

        let old = #"{"stops":[{"id":"a","value":30,"unit":"seconds","colorHex":"FFD60A"}],"overtimeHex":"CC1717"}"#
        let legacy = try JSONDecoder().decode(TimerColorScale.self, from: Data(old.utf8))
        XCTAssertEqual(legacy.stops.first?.effect, TimerEffect.none)
        XCTAssertEqual(legacy.overtimeEffect, TimerEffect.none)
        // A scale whose effects are None must not read back as the default flicker.
        let quiet = TimerColorScale(stops: [], overtimeHex: "CC1717", overtimeEffect: .none)
        XCTAssertEqual(try JSONDecoder().decode(TimerColorScale.self, from: JSONEncoder().encode(quiet)), quiet)
        XCTAssertEqual(try JSONDecoder().decode(TimerColorScale.self, from: JSONEncoder().encode(TimerColorScale.standard)), .standard)
    }

    func testOvertimeLevelsTakeOverTheDeeperTheItemRuns() throws {
        let scale = TimerColorScale(
            stops: [
                TimerColorStop(phase: .overtime, value: 60, unit: .seconds, colorHex: "FF3B30", effect: .blink),
                TimerColorStop(phase: .overtime, value: 50, unit: .percent, colorHex: "8E0000", effect: .glitch)
            ],
            overtimeHex: "CC1717"
        )
        // 5:00 item: 50% over is 150 s.
        XCTAssertEqual(scale.style(remainingSeconds: -10, lengthSeconds: 300).colorHex, "CC1717")
        XCTAssertEqual(scale.style(remainingSeconds: -60, lengthSeconds: 300).colorHex, "FF3B30")
        XCTAssertEqual(scale.style(remainingSeconds: -60, lengthSeconds: 300).effect, .blink)
        XCTAssertEqual(scale.style(remainingSeconds: -150, lengthSeconds: 300).colorHex, "8E0000")
        XCTAssertEqual(scale.style(remainingSeconds: -150, lengthSeconds: 300).effect, .glitch)
        // Lead-up behaviour is untouched by overtime levels.
        XCTAssertNil(scale.colorHex(remainingSeconds: 5, lengthSeconds: 300))

        let decoded = try JSONDecoder().decode(TimerColorScale.self, from: JSONEncoder().encode(scale))
        XCTAssertEqual(decoded.stops.map(\.phase), [.overtime, .overtime])
    }

    func testEmptyJSONDecodesAsTheStandardScale() throws {
        let decoded = try JSONDecoder().decode(TimerColorScale.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, .standard)
        let emptyLists = try JSONDecoder().decode(TimerColorScale.self, from: Data(#"{"stops":[]}"#.utf8))
        XCTAssertTrue(emptyLists.stops.isEmpty)
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

final class PagerTimerColorTests: XCTestCase {
    private func state(item: PCOTimerItem, colors: TimerColorScale? = nil) -> PagerPresentationState {
        PagerPresentationState(
            roles: [], planItems: [item], activeItemIndex: 0, activeTimerItem: item, recentMessages: [],
            selectedRoleId: "host", isProducerLive: true, isLANConnected: true, connectedMasterName: nil,
            hourFormatThreshold: .never, clockFormat: .twelveHour, timerColors: colors
        )
    }

    func testPagersWithNoScaleUseTheStandardOvertimeRed() {
        let over = PCOTimerItem(id: "a", title: "A", itemType: "Item", lengthInSeconds: 60, elapsedSeconds: 70)
        let under = PCOTimerItem(id: "a", title: "A", itemType: "Item", lengthInSeconds: 60, elapsedSeconds: 10)
        XCTAssertEqual(state(item: over).timerColorHex, "CC1717")
        XCTAssertNil(state(item: under).timerColorHex)
    }

    func testAnOverridingScaleReplacesTheStandardOne() {
        let over = PCOTimerItem(id: "a", title: "A", itemType: "Item", lengthInSeconds: 60, elapsedSeconds: 70)
        XCTAssertEqual(state(item: over, colors: TimerColorScale(overtimeHex: "FF00FF")).timerColorHex, "FF00FF")
    }
}
