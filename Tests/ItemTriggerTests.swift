// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class ItemTriggerTests: XCTestCase {
    private func makeEngine(followByDefault: Bool, secondTrigger: ItemTrigger? = nil, firstTrigger: ItemTrigger? = nil) -> CueEngine {
        let engine = CueEngine()
        engine.importFlow(title: "Sunday", items: [
            PCOTimerItem(id: "a", title: "Song", itemType: "Item", lengthInSeconds: 60, trigger: firstTrigger),
            PCOTimerItem(id: "b", title: "Talk", itemType: "Item", lengthInSeconds: 300, trigger: secondTrigger),
            PCOTimerItem(id: "c", title: "Close", itemType: "Item", lengthInSeconds: 120)
        ])
        engine.followByDefault = followByDefault
        return engine
    }

    private func runToZero(_ engine: CueEngine) {
        engine.evaluateTrigger()
        engine.activeTimerItem?.elapsedSeconds = engine.activeTimerItem?.lengthInSeconds ?? 0
        engine.evaluateTrigger()
    }

    func testNextItemFollowingStartsWhenPriorEnds() {
        let engine = makeEngine(followByDefault: true)
        runToZero(engine)
        XCTAssertEqual(engine.activeTimerItem?.id, "b")
        XCTAssertEqual(engine.activeTimerItem?.isRunning, true)
    }

    func testNextItemWaitingHoldsAtZero() {
        let engine = makeEngine(followByDefault: false)
        runToZero(engine)
        XCTAssertEqual(engine.activeTimerItem?.id, "a")
    }

    func testTheNextItemsOwnTriggerDecides() {
        let follow = makeEngine(followByDefault: false, secondTrigger: .follow)
        runToZero(follow)
        XCTAssertEqual(follow.activeTimerItem?.id, "b")
        let go = makeEngine(followByDefault: true, secondTrigger: .go)
        runToZero(go)
        XCTAssertEqual(go.activeTimerItem?.id, "a")
    }

    func testTheRunningItemsOwnTriggerDoesNotMatterToItsEnd() {
        let engine = makeEngine(followByDefault: false, secondTrigger: .follow, firstTrigger: .go)
        runToZero(engine)
        XCTAssertEqual(engine.activeTimerItem?.id, "b")
    }

    func testChainFollowsThenWaits() {
        let engine = makeEngine(followByDefault: true)
        engine.setItemTrigger(id: "c", .go)
        runToZero(engine)
        XCTAssertEqual(engine.activeTimerItem?.id, "b")
        runToZero(engine)
        XCTAssertEqual(engine.activeTimerItem?.id, "b")
    }

    func testItemAlreadyOverdueDoesNotSkipOnStart() {
        let engine = makeEngine(followByDefault: true)
        engine.activeTimerItem?.elapsedSeconds = 90
        engine.evaluateTrigger()
        XCTAssertEqual(engine.activeTimerItem?.id, "a")
    }

    func testPausedItemDoesNotAdvance() {
        let engine = makeEngine(followByDefault: true)
        engine.evaluateTrigger()
        engine.activeTimerItem?.elapsedSeconds = 60
        engine.activeTimerItem?.isRunning = false
        engine.evaluateTrigger()
        XCTAssertEqual(engine.activeTimerItem?.id, "a")
    }

    func testLastItemHasNothingToStart() {
        let engine = makeEngine(followByDefault: true)
        runToZero(engine)
        runToZero(engine)
        XCTAssertEqual(engine.activeTimerItem?.id, "c")
        runToZero(engine)
        XCTAssertEqual(engine.activeTimerItem?.id, "c")
    }

    func testOnlyTheFirstRealItemStartsThePlan() {
        let engine = makeEngine(followByDefault: true)
        XCTAssertTrue(engine.isFirstPlanItem(id: "a"))
        XCTAssertFalse(engine.isFirstPlanItem(id: "b"))
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
        let item = PCOTimerItem(title: "x", trigger: .go)
        let back = try JSONDecoder().decode(PCOTimerItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(back.trigger, .go)
        let legacy = try JSONDecoder().decode(PCOTimerItem.self, from: JSONEncoder().encode(PCOTimerItem(title: "y")))
        XCTAssertNil(legacy.trigger)
    }
}
