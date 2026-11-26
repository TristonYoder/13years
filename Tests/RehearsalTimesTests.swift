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

    func testPlanProgressCountsFinishedItemsAndTheActiveOnesElapsedTime() {
        let engine = CueEngine()
        XCTAssertEqual(engine.planProgress, 0)
        engine.importFlow(title: nil, items: [
            PCOTimerItem(id: "a", title: "A", itemType: "Item", lengthInSeconds: 60),
            PCOTimerItem(id: "b", title: "B", itemType: "Item", lengthInSeconds: 120),
            PCOTimerItem(id: "c", title: "C", itemType: "Item", lengthInSeconds: 120)
        ])
        XCTAssertEqual(engine.planProgress, 0, accuracy: 0.001)
        engine.nextPlanItem(startTimer: false)
        XCTAssertEqual(engine.planProgress, 60.0 / 300.0, accuracy: 0.001)
    }
}
