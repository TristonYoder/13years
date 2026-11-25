// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class AutoAdvanceTests: XCTestCase {
    private func makeEngine(defaultOn: Bool, itemOverride: Bool? = nil) -> CueEngine {
        let engine = CueEngine()
        engine.importFlow(title: "Sunday", items: [
            PCOTimerItem(id: "a", title: "Song", itemType: "Item", lengthInSeconds: 60, autoAdvance: itemOverride),
            PCOTimerItem(id: "b", title: "Talk", itemType: "Item", lengthInSeconds: 300)
        ])
        engine.autoAdvanceByDefault = defaultOn
        return engine
    }

    private func runToZero(_ engine: CueEngine) {
        engine.evaluateAutoAdvance()
        engine.activeTimerItem?.elapsedSeconds = 60
        engine.evaluateAutoAdvance()
    }

    func testPlanDefaultAdvancesAtZero() {
        let engine = makeEngine(defaultOn: true)
        runToZero(engine)
        XCTAssertEqual(engine.activeTimerItem?.id, "b")
        XCTAssertEqual(engine.activeTimerItem?.isRunning, true)
    }

    func testOffByDefaultStaysOnItem() {
        let engine = makeEngine(defaultOn: false)
        runToZero(engine)
        XCTAssertEqual(engine.activeTimerItem?.id, "a")
    }

    func testItemOverrideBeatsPlanDefault() {
        let on = makeEngine(defaultOn: false, itemOverride: true)
        runToZero(on)
        XCTAssertEqual(on.activeTimerItem?.id, "b")
        let off = makeEngine(defaultOn: true, itemOverride: false)
        runToZero(off)
        XCTAssertEqual(off.activeTimerItem?.id, "a")
    }

    func testItemAlreadyOverdueDoesNotSkipOnStart() {
        let engine = makeEngine(defaultOn: true)
        engine.activeTimerItem?.elapsedSeconds = 90
        engine.evaluateAutoAdvance()
        XCTAssertEqual(engine.activeTimerItem?.id, "a")
    }

    func testPausedItemDoesNotAdvance() {
        let engine = makeEngine(defaultOn: true)
        engine.evaluateAutoAdvance()
        engine.activeTimerItem?.elapsedSeconds = 60
        engine.activeTimerItem?.isRunning = false
        engine.evaluateAutoAdvance()
        XCTAssertEqual(engine.activeTimerItem?.id, "a")
    }

    func testLastItemHasNowhereToAdvance() {
        let engine = makeEngine(defaultOn: true)
        runToZero(engine)
        engine.activeTimerItem?.elapsedSeconds = 0
        engine.evaluateAutoAdvance()
        engine.activeTimerItem?.elapsedSeconds = 300
        engine.evaluateAutoAdvance()
        XCTAssertEqual(engine.activeTimerItem?.id, "b")
    }

    func testEndEqualsStartPlusLength() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let entry = RunSheetSchedule.Entry(
            itemId: "a", position: .during, isHeader: false, isExcluded: false, isSkipped: false,
            length: 1800, plannedStart: start, projectedStart: start.addingTimeInterval(120),
            actualStart: nil, actualLength: nil, isActualComplete: false, pcoActualStart: nil, pcoActualLength: nil
        )
        XCTAssertEqual(entry.plannedEnd, start.addingTimeInterval(1800))
        XCTAssertEqual(entry.projectedEnd, start.addingTimeInterval(1920))
    }

    func testSettingsRoundTrip() throws {
        var layout = RunSheetLayoutSettings()
        XCTAssertFalse(layout.displaysEndTimes)
        layout.showsEndTimes = true
        let decoded = try JSONDecoder().decode(RunSheetLayoutSettings.self, from: JSONEncoder().encode(layout))
        XCTAssertTrue(decoded.displaysEndTimes)
        let item = PCOTimerItem(title: "x", autoAdvance: false)
        let back = try JSONDecoder().decode(PCOTimerItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(back.autoAdvance, false)
        let legacy = try JSONDecoder().decode(PCOTimerItem.self, from: JSONEncoder().encode(PCOTimerItem(title: "y")))
        XCTAssertNil(legacy.autoAdvance)
    }
}
