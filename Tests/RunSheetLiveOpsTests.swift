// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class RunSheetLiveOpsTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var sent: [(packet: CuePacket, target: OutboundTarget)] = []

    override func setUp() {
        super.setUp()
        clearPersistedState()
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        sent = []
    }

    override func tearDown() {
        clearPersistedState()
        super.tearDown()
    }

    private func clearPersistedState() {
        for key in ["persistedFlow", "persistedRoles", "isPCOLiveSyncEnabled", "recentMessages", "waypoints", "serviceTags", "serviceSchedules"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func item(_ id: String, length: Int = 300, planId: String? = "plan1", times: [PCOItemTimeInfo] = []) -> PCOTimerItem {
        PCOTimerItem(
            id: id,
            title: "Item \(id)",
            itemType: "Item",
            lengthInSeconds: length,
            pcoServiceTypeId: planId == nil ? nil : "st",
            pcoPlanId: planId,
            details: times.isEmpty ? nil : PCOItemDetails(itemTimes: times)
        )
    }

    private func makeEngine(_ items: [PCOTimerItem]? = nil, eventTimes: Bool = true, started: Bool = true) -> CueEngine {
        let engine = CueEngine(startsNetworking: false)
        engine.timerClock = { [unowned self] in self.clock }
        engine.outboundObserver = { [unowned self] packet, target in self.sent.append((packet, target)) }
        engine.importFlow(title: "Plan", items: items ?? [item("a"), item("b"), item("c"), item("d")])
        if eventTimes {
            engine.eventTimes = [
                EventTime(id: "e1", name: "Early", pcoPlanTimeId: "pt1"),
                EventTime(id: "e2", name: "Late", pcoPlanTimeId: "pt2"),
            ]
            engine.liveEventTimeId = "e1"
        }
        if started, let first = engine.activeTimerItem?.id { engine.setActivePlanItem(id: first) }
        sent = []
        return engine
    }

    private func setElapsed(_ engine: CueEngine, _ seconds: Int) {
        engine.activeTimerItem?.elapsedSeconds = seconds
    }

    private func actual(_ engine: CueEngine, _ itemId: String, eventTimeId: String? = "e1") -> ItemActual? {
        engine.itemActuals.first { $0.itemId == itemId && $0.eventTimeId == eventTimeId }
    }

    func testAdvancingRecordsEachItemsActual() {
        let engine = makeEngine()
        setElapsed(engine, 100)
        engine.nextPlanItem()
        setElapsed(engine, 50)
        engine.nextPlanItem()

        XCTAssertEqual(actual(engine, "a")?.lengthSeconds, 100)
        XCTAssertNotNil(actual(engine, "a")?.endedAt)
        XCTAssertEqual(actual(engine, "a")?.startedAt, clock)
        XCTAssertEqual(actual(engine, "b")?.lengthSeconds, 50)
        XCTAssertNil(actual(engine, "c")?.endedAt)
        XCTAssertNil(actual(engine, "c")?.lengthSeconds)
    }

    func testReactivatingAnItemAccumulatesItsLength() {
        let engine = makeEngine()
        setElapsed(engine, 100)
        engine.nextPlanItem()
        setElapsed(engine, 20)
        engine.setActivePlanItem(id: "a")
        setElapsed(engine, 40)
        engine.nextPlanItem()

        XCTAssertEqual(engine.itemActuals.filter { $0.itemId == "a" }.count, 1)
        XCTAssertEqual(actual(engine, "a")?.lengthSeconds, 140)
        XCTAssertEqual(actual(engine, "b")?.lengthSeconds, 20)
    }

    func testItemsThatNeverRanLeaveNoActual() {
        let engine = makeEngine()
        engine.nextPlanItem(startTimer: false)
        engine.nextPlanItem(startTimer: false)
        XCTAssertNil(actual(engine, "b"))
        XCTAssertEqual(engine.activeTimerItem?.id, "c")
        setElapsed(engine, 0)
        engine.nextPlanItem()
        XCTAssertNil(actual(engine, "c"))
    }

    func testLiveActualIncludesTheRunningItem() {
        let engine = makeEngine()
        engine.setActivePlanItem(id: "a")
        setElapsed(engine, 75)
        XCTAssertEqual(engine.actualLength(forItemId: "a"), 75)
        let entry = engine.runSheetSchedule(now: clock).entry(forItemId: "a")
        XCTAssertEqual(entry?.actualLength, 75)
        XCTAssertEqual(entry?.isActualComplete, false)
    }

    func testSwitchingEventTimesSplitsTheRunningItem() {
        let engine = makeEngine()
        engine.setActivePlanItem(id: "a")
        setElapsed(engine, 60)
        engine.setLiveEventTime(id: "e2")
        XCTAssertEqual(actual(engine, "a", eventTimeId: "e1")?.lengthSeconds, 60)
        setElapsed(engine, 90)
        engine.nextPlanItem()
        XCTAssertEqual(actual(engine, "a", eventTimeId: "e2")?.lengthSeconds, 30)
        XCTAssertEqual(actual(engine, "a", eventTimeId: "e1")?.lengthSeconds, 60)
    }

    func testAdvancingToTheNextEventTimeClosesTheLastItemUnderTheOldTime() {
        let engine = makeEngine([item("a"), item("b")])
        engine.nextPlanItem()
        setElapsed(engine, 45)
        engine.advanceToNextEventTime()

        XCTAssertEqual(engine.liveEventTime?.id, "e2")
        XCTAssertEqual(actual(engine, "b", eventTimeId: "e1")?.lengthSeconds, 45)
        XCTAssertNil(actual(engine, "b", eventTimeId: "e2"))
        XCTAssertEqual(engine.activeTimerItem?.id, "a")
    }

    func testWithoutEventTimesActualsAreKeyedAdhoc() {
        let engine = makeEngine(eventTimes: false)
        setElapsed(engine, 30)
        engine.nextPlanItem()
        XCTAssertEqual(actual(engine, "a", eventTimeId: nil)?.lengthSeconds, 30)
        XCTAssertEqual(engine.currentItemActuals.map(\.itemId), ["a", "b"])
    }

    func testRehearsalModeDoesNotLogAndRestoresTheLiveTime() {
        let engine = makeEngine()
        engine.setActivePlanItem(id: "a")
        setElapsed(engine, 40)
        engine.setRehearsalMode(true)
        XCTAssertEqual(actual(engine, "a")?.lengthSeconds, 40)

        setElapsed(engine, 500)
        engine.nextPlanItem()
        setElapsed(engine, 200)
        engine.nextPlanItem()
        XCTAssertNil(actual(engine, "b"))
        XCTAssertNil(actual(engine, "c"))
        XCTAssertTrue(engine.currentItemActuals.isEmpty)

        engine.setRehearsalMode(false)
        XCTAssertEqual(engine.liveEventTime?.id, "e1")
        setElapsed(engine, 10)
        engine.nextPlanItem()
        XCTAssertEqual(actual(engine, "c")?.lengthSeconds, 10)
        XCTAssertEqual(engine.currentItemActuals.map(\.itemId), ["a", "c", "d"])
    }

    func testClearActualsKeepsTheRunningItemCounting() {
        let engine = makeEngine()
        setElapsed(engine, 100)
        engine.nextPlanItem()
        setElapsed(engine, 30)
        engine.clearActuals()
        XCTAssertNil(actual(engine, "a"))
        XCTAssertNotNil(actual(engine, "b"))
        setElapsed(engine, 50)
        engine.nextPlanItem()
        XCTAssertEqual(actual(engine, "b")?.lengthSeconds, 20)
    }

    func testLoadingADifferentPlanClearsActualsAndSkipsButResyncingKeepsThem() {
        let engine = makeEngine()
        setElapsed(engine, 100)
        engine.nextPlanItem()
        engine.setItemSkipped(id: "d", skipped: true)
        XCTAssertFalse(engine.itemActuals.isEmpty)

        engine.importFlow(title: "Plan", items: [item("a"), item("b"), item("c"), item("d")])
        XCTAssertNotNil(actual(engine, "a"))
        XCTAssertTrue(engine.isItemSkipped("d"))

        engine.importFlow(title: "Other", items: [item("x", planId: "plan2"), item("y", planId: "plan2")])
        XCTAssertTrue(engine.itemActuals.allSatisfy { ["x", "y"].contains($0.itemId) })
        XCTAssertTrue(engine.skippedItemIds.isEmpty)
        XCTAssertFalse(engine.isRehearsalMode)
    }

    func testRemovingAnItemForgetsItsActualAndSkip() {
        let engine = makeEngine()
        setElapsed(engine, 100)
        engine.nextPlanItem()
        engine.setItemSkipped(id: "c", skipped: true)
        engine.removePlanItem(id: "a")
        engine.removePlanItem(id: "c")
        XCTAssertNil(actual(engine, "a"))
        XCTAssertTrue(engine.skippedItemIds.isEmpty)
    }

    func testNextAndPreviousSkipSkippedItems() {
        let engine = makeEngine()
        engine.setItemSkipped(id: "b", skipped: true)
        engine.setItemSkipped(id: "c", skipped: true)
        XCTAssertEqual(engine.derivedNextPlanItem?.id, "d")
        engine.nextPlanItem()
        XCTAssertEqual(engine.activeTimerItem?.id, "d")
        engine.previousPlanItem()
        XCTAssertEqual(engine.activeTimerItem?.id, "a")
        engine.nextPlanItem()
        engine.setItemSkipped(id: "c", skipped: false)
        engine.previousPlanItem()
        XCTAssertEqual(engine.activeTimerItem?.id, "c")
    }

    func testSkippingTheTailEndsThePlanAndExplicitJumpsStillWork() {
        let engine = makeEngine()
        engine.setItemSkipped(id: "c", skipped: true)
        engine.setItemSkipped(id: "d", skipped: true)
        engine.nextPlanItem()
        XCTAssertEqual(engine.activeTimerItem?.id, "b")
        XCTAssertTrue(engine.isAtEndOfPlan)
        XCTAssertNil(engine.nextItemForBroadcast)
        engine.setActivePlanItem(id: "c")
        XCTAssertEqual(engine.activeTimerItem?.id, "c")
    }

    func testSkipsAreScopedToTheLiveEventTime() {
        let engine = makeEngine()
        engine.setItemSkipped(id: "b", skipped: true)
        XCTAssertTrue(engine.isItemSkipped("b"))
        engine.setLiveEventTime(id: "e2")
        XCTAssertFalse(engine.isItemSkipped("b"))
        XCTAssertEqual(engine.derivedNextPlanItem?.id, "b")
        engine.setLiveEventTime(id: "e1")
        XCTAssertEqual(engine.derivedNextPlanItem?.id, "c")
    }

    func testPCOExcludedItemsAreSkippedForTheirTimeOnly() {
        let excludedLate = [PCOItemTimeInfo(id: "t1", planTimeId: "pt2", exclude: true)]
        let engine = makeEngine([item("a"), item("b", times: excludedLate), item("c")])
        XCTAssertEqual(engine.derivedNextPlanItem?.id, "b")
        engine.setLiveEventTime(id: "e2")
        XCTAssertEqual(engine.derivedNextPlanItem?.id, "c")
        XCTAssertFalse(engine.isItemSkipped("b"))
        XCTAssertTrue(engine.isOmittedFromNavigation(engine.planItems[1]))
    }

    func testSkippingChangesTheNextItemOnPagers() {
        let engine = makeEngine()
        engine.setItemSkipped(id: "b", skipped: true)
        XCTAssertEqual(engine.nextItemForBroadcast?.id, "c")
        XCTAssertEqual(sent.filter { $0.packet.type == .timerAnchor }.last?.packet.nextItem?.id, "c")
    }

    func testLiveStepsCountLocallySkippedItemsButNotPCOExcludedOnes() {
        let excluded = [PCOItemTimeInfo(id: "t1", planTimeId: "pt1", exclude: true)]
        let engine = makeEngine([item("a"), item("b"), item("c", times: excluded), item("d"), PCOTimerItem(id: "h", title: "H", itemType: "Header"), item("e")])
        XCTAssertEqual(engine.realItemStepCount(from: 0, to: 5), 3)
        engine.setItemSkipped(id: "b", skipped: true)
        XCTAssertEqual(engine.realItemStepCount(from: 0, to: 5), 3)
        XCTAssertEqual(engine.realItemStepCount(from: 5, to: 0), 3)
        engine.setLiveEventTime(id: "e2")
        XCTAssertEqual(engine.realItemStepCount(from: 0, to: 5), 4)
    }

    func testRehearsalUsesTheRehearsalTimeStartAndExclusions() {
        let start = Date(timeIntervalSince1970: 1_800_100_000)
        let excluded = [PCOItemTimeInfo(id: "t1", planTimeId: "rt", exclude: true)]
        let engine = makeEngine([item("a", length: 300), item("b", length: 100, times: excluded), item("c", length: 200)])
        engine.eventTimes[0].startTime = TimeOfDay(hour: 9, minute: 0)
        engine.pcoPlanContext = PCOPlanContext(planId: "plan1", serviceTypeId: "st", times: [
            PCOPlanTimeInfo(id: "rt", name: "Run-through", timeType: "rehearsal", startsAt: start),
            PCOPlanTimeInfo(id: "pt1", timeType: "service"),
        ])

        XCTAssertEqual(engine.rehearsalPlanTimes.map(\.id), ["rt"])
        XCTAssertFalse(engine.setRehearsalMode(true, planTimeId: "pt1"))
        XCTAssertTrue(engine.setRehearsalMode(true))
        XCTAssertEqual(engine.rehearsalPlanTimeId, "rt")
        XCTAssertEqual(engine.liveEventTimeLabel, "Rehearsal \u{00B7} Run-through")

        let schedule = engine.runSheetSchedule(now: clock)
        XCTAssertEqual(schedule.entry(forItemId: "a")?.plannedStart, start)
        XCTAssertEqual(schedule.entry(forItemId: "b")?.isExcluded, true)
        XCTAssertEqual(schedule.entry(forItemId: "c")?.plannedStart, start.addingTimeInterval(300))

        engine.setRehearsalMode(false)
        XCTAssertNil(engine.rehearsalPlanTimeId)
        XCTAssertEqual(engine.liveEventTime?.id, "e1")
    }

    func testRehearsalBlocksLiveStepCounting() {
        let engine = makeEngine()
        engine.isPCOLiveSyncEnabled = true
        engine.setRehearsalMode(true)
        var steps = 0
        engine.pcoChangeTracking.fetchRemote = { _, _ in steps += 1; return [] }
        engine.nextPlanItem()
        XCTAssertEqual(steps, 0)
        XCTAssertFalse(engine.isChangingEventTime)
    }

    func testSaveActualLengthsWritesEachChangedSyncedItem() async throws {
        let engine = makeEngine([item("a", length: 300), item("b", length: 300), item("c", length: 300), item("local", length: 60, planId: nil)])
        engine.isPCOConnected = true
        engine.pcoChangeTracking.pushDelay = 0
        var writes: [(String, Int)] = []
        engine.pcoChangeTracking.writeLength = { serviceTypeId, planId, itemId, seconds in
            XCTAssertEqual(serviceTypeId, "st")
            XCTAssertEqual(planId, "plan1")
            writes.append((itemId, seconds))
        }
        setElapsed(engine, 240)
        engine.nextPlanItem()
        setElapsed(engine, 300)
        engine.nextPlanItem()
        setElapsed(engine, 90)
        engine.nextPlanItem()
        setElapsed(engine, 70)
        engine.nextPlanItem(startTimer: false)

        let changes = engine.actualLengthChanges()
        XCTAssertEqual(changes.map(\.itemId), ["a", "c"])
        XCTAssertEqual(changes.map(\.actualSeconds), [240, 90])
        XCTAssertEqual(engine.saveActualLengthsToPCO(), 2)

        for _ in 0..<50 where engine.isPCOWriteActive || writes.count < 2 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(writes.map(\.0), ["a", "c"])
        XCTAssertEqual(writes.map(\.1), [240, 90])
        XCTAssertEqual(engine.planItems.first { $0.id == "a" }?.lengthInSeconds, 240)
        XCTAssertEqual(engine.pcoChangeTracking.baseline.first { $0.id == "a" }?.lengthInSeconds, 240)
        XCTAssertEqual(engine.pcoChangeTracking.baseline.first { $0.id == "b" }?.lengthInSeconds, 300)
        XCTAssertNil(engine.pcoPendingChanges)
        XCTAssertTrue(engine.actualLengthChanges().isEmpty)
    }

    func testUseActualAsPlannedLengthUpdatesLocallyAndPushes() async throws {
        let engine = makeEngine()
        engine.setActivePlanItem(id: "a")
        engine.pcoChangeTracking.pushDelay = 0
        var writes: [(String, Int)] = []
        engine.pcoChangeTracking.writeLength = { _, _, itemId, seconds in writes.append((itemId, seconds)) }
        setElapsed(engine, 125)
        XCTAssertTrue(engine.useActualAsPlannedLength(itemId: "a"))
        XCTAssertEqual(engine.planItems[0].lengthInSeconds, 125)
        XCTAssertEqual(engine.activeTimerItem?.lengthInSeconds, 125)
        XCTAssertFalse(engine.useActualAsPlannedLength(itemId: "c"))
        for _ in 0..<50 where writes.isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.first?.1, 125)
    }

    func testScheduleChainsProjectionsFromCompletedActuals() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [
            PCOTimerItem(id: "a", title: "a", lengthInSeconds: 300),
            PCOTimerItem(id: "b", title: "b", lengthInSeconds: 300),
            PCOTimerItem(id: "c", title: "c", lengthInSeconds: 300),
        ]
        let actuals = [
            "a": RunSheetSchedule.Actual(start: start.addingTimeInterval(10), length: 400, isComplete: true),
            "b": RunSheetSchedule.Actual(start: start.addingTimeInterval(410), length: 200, isComplete: true),
        ]
        let now = start.addingTimeInterval(610)
        let schedule = RunSheetSchedule(items: items, startDate: start, planTimeId: nil, actuals: actuals, now: now)

        XCTAssertEqual(schedule.entry(forItemId: "a")?.actualDeltaSeconds, 100)
        XCTAssertEqual(schedule.entry(forItemId: "b")?.actualDeltaSeconds, -100)
        XCTAssertEqual(schedule.entry(forItemId: "b")?.projectedStart, start.addingTimeInterval(410))
        XCTAssertEqual(schedule.entry(forItemId: "c")?.projectedStart, now)
        XCTAssertEqual(schedule.entry(forItemId: "c")?.driftSeconds, 10)
        XCTAssertEqual(schedule.projectedEnd, now.addingTimeInterval(300))
        XCTAssertEqual(schedule.actualElapsedSeconds, 600)
        XCTAssertEqual(schedule.actualDriftSeconds, 0)
    }

    func testScheduleTreatsTheActiveItemsActualAsInProgress() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [PCOTimerItem(id: "a", title: "a", lengthInSeconds: 300), PCOTimerItem(id: "b", title: "b", lengthInSeconds: 300)]
        let actuals = ["a": RunSheetSchedule.Actual(start: start, length: 120, isComplete: false)]
        let schedule = RunSheetSchedule(
            items: items, startDate: start, planTimeId: nil,
            activeIndex: 0, activeElapsed: 120, activeLength: 300, actuals: actuals, now: start.addingTimeInterval(120)
        )
        XCTAssertNil(schedule.entry(forItemId: "a")?.actualDeltaSeconds)
        XCTAssertNil(schedule.actualDriftSeconds)
        XCTAssertEqual(schedule.actualElapsedSeconds, 120)
        XCTAssertEqual(schedule.entry(forItemId: "b")?.projectedStart, start.addingTimeInterval(300))
    }

    func testScheduleOmitsSkippedItemsFromTheTimeline() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [
            PCOTimerItem(id: "a", title: "a", lengthInSeconds: 300),
            PCOTimerItem(id: "b", title: "b", lengthInSeconds: 200),
            PCOTimerItem(id: "c", title: "c", lengthInSeconds: 100),
        ]
        let schedule = RunSheetSchedule(items: items, startDate: start, planTimeId: nil, skippedItemIds: ["b"])
        XCTAssertEqual(schedule.entry(forItemId: "b")?.isSkipped, true)
        XCTAssertEqual(schedule.entry(forItemId: "b")?.isOmitted, true)
        XCTAssertNil(schedule.entry(forItemId: "b")?.plannedStart)
        XCTAssertEqual(schedule.entry(forItemId: "c")?.plannedStart, start.addingTimeInterval(300))
        XCTAssertEqual(schedule.plannedLength, 400)
    }

    func testScheduleReadsPCORecordedActuals() {
        let begin = Date(timeIntervalSince1970: 1_800_000_000)
        let times = [
            PCOItemTimeInfo(id: "t1", planTimeId: "pt1", liveStartAt: begin, liveEndAt: begin.addingTimeInterval(272)),
            PCOItemTimeInfo(id: "t2", planTimeId: "pt2", liveStartAt: begin),
        ]
        let items = [PCOTimerItem(id: "a", title: "a", lengthInSeconds: 300, details: PCOItemDetails(itemTimes: times))]
        let early = RunSheetSchedule(items: items, startDate: begin, planTimeId: "pt1").entry(forItemId: "a")
        XCTAssertEqual(early?.pcoActualLength, 272)
        XCTAssertEqual(early?.pcoActualStart, begin)
        XCTAssertNil(RunSheetSchedule(items: items, startDate: begin, planTimeId: "pt2").entry(forItemId: "a")?.pcoActualLength)
        XCTAssertNil(RunSheetSchedule(items: items, startDate: begin, planTimeId: nil).entry(forItemId: "a")?.pcoActualStart)
    }

    func testDocumentRoundTripAndLegacyDecode() throws {
        let engine = makeEngine()
        setElapsed(engine, 100)
        engine.nextPlanItem()
        engine.setItemSkipped(id: "d", skipped: true)
        let document = engine.makeDocument()
        XCTAssertEqual(document.itemActuals?.first?.itemId, "a")
        XCTAssertEqual(document.skippedItemIds, ["e1": ["d"]])

        let decoded = try ProducerDocument.decoded(from: document.encoded())
        XCTAssertEqual(decoded.itemActuals, document.itemActuals)
        XCTAssertEqual(decoded.skippedItemIds, document.skippedItemIds)
        XCTAssertNil(decoded.asTemplate().itemActuals)

        let legacy = Data(#"{"version":1,"planItems":[]}"#.utf8)
        let old = try ProducerDocument.decoded(from: legacy)
        XCTAssertNil(old.itemActuals)
        XCTAssertNil(old.skippedItemIds)

        let other = makeEngine()
        other.apply(decoded)
        XCTAssertEqual(other.itemActuals.first?.lengthSeconds, 100)
        XCTAssertTrue(other.isItemSkipped("d"))

        var stale = decoded
        stale.itemActuals = [ItemActual(itemId: "gone", eventTimeId: "e1", startedAt: clock, lengthSeconds: 5)]
        stale.skippedItemIds = ["e1": ["gone"]]
        other.apply(stale)
        XCTAssertTrue(other.itemActuals.isEmpty)
        XCTAssertTrue(other.skippedItemIds.isEmpty)
    }

    func testImportAloneDoesNotLogActuals() {
        let engine = makeEngine(started: false)
        clock.addTimeInterval(120)
        setElapsed(engine, 120)
        XCTAssertTrue(engine.itemActuals.isEmpty)
        XCTAssertTrue(engine.itemActualsIncludingLive.isEmpty)
        engine.eventTimes = [EventTime(id: "e1", name: "Early"), EventTime(id: "e2", name: "Late")]
        engine.liveEventTimeId = "e2"
        XCTAssertTrue(engine.itemActualsIncludingLive.isEmpty)
    }

    func testFirstExplicitGoLogsFromThatMoment() {
        let engine = makeEngine(started: false)
        clock.addTimeInterval(300)
        engine.setActivePlanItem(id: "c")
        XCTAssertEqual(engine.activeTimerItem?.id, "c")
        XCTAssertNil(actual(engine, "a"))
        XCTAssertEqual(actual(engine, "c")?.startedAt, clock)
        setElapsed(engine, 40)
        engine.nextPlanItem()
        XCTAssertEqual(actual(engine, "c")?.lengthSeconds, 40)
    }

    func testResumingThePausedTimerStartsLogging() {
        let engine = makeEngine(started: false)
        engine.toggleTimerRunning()
        setElapsed(engine, 30)
        XCTAssertTrue(engine.itemActualsIncludingLive.isEmpty)
        clock.addTimeInterval(30)
        engine.toggleTimerRunning()
        XCTAssertEqual(actual(engine, "a")?.startedAt, clock)
        setElapsed(engine, 50)
        engine.nextPlanItem()
        XCTAssertEqual(actual(engine, "a")?.lengthSeconds, 20)
    }

    func testNextAfterImportLogsOnlyFromTheFirstExplicitStart() {
        let engine = makeEngine(started: false)
        setElapsed(engine, 90)
        engine.nextPlanItem()
        setElapsed(engine, 45)
        engine.nextPlanItem()
        XCTAssertNil(actual(engine, "a"))
        XCTAssertEqual(actual(engine, "b")?.lengthSeconds, 45)
    }

    func testReloadingThePlanResetsTheStartedFlag() {
        let engine = makeEngine(started: false)
        engine.nextPlanItem()
        XCTAssertTrue(engine.hasStartedPlan)
        engine.importFlow(title: "Plan", items: [item("a"), item("b"), item("c"), item("d")])
        XCTAssertFalse(engine.hasStartedPlan)
        setElapsed(engine, 60)
        XCTAssertFalse(engine.itemActualsIncludingLive.contains { $0.itemId == "a" && $0.eventTimeId == "e1" && $0.startedAt > clock })
        engine.applyPlan(of: engine.makeDocument())
        XCTAssertFalse(engine.hasStartedPlan)
    }

    func testTappingAHeaderWhenEveryItemIsSkippedStillLandsOnAnItem() {
        let header = PCOTimerItem(id: "h", title: "Header", itemType: "Header", lengthInSeconds: 0)
        let engine = makeEngine([item("a"), header, item("c")])
        engine.setItemSkipped(id: "a", skipped: true)
        engine.setItemSkipped(id: "c", skipped: true)
        engine.setActivePlanItem(id: "h")
        XCTAssertEqual(engine.activeTimerItem?.id, "c")
        XCTAssertFalse(engine.activeTimerItem?.isHeader ?? true)

        engine.removePlanItem(id: "c")
        XCTAssertEqual(engine.activeTimerItem?.id, "a")
    }

    func testSavingActualsToPCORequiresSignIn() {
        let engine = makeEngine()
        setElapsed(engine, 100)
        engine.nextPlanItem()
        let router = ControlAPIRouter(engine: engine)
        func call(_ path: String) -> HTTPResponse {
            router.handle(HTTPRequest(method: "POST", path: path, body: Data()))
        }
        XCTAssertTrue(engine.actualLengthChanges().isEmpty)
        XCTAssertEqual(call("/v1/plan/actuals/save-to-pco").status, 409)
        XCTAssertEqual(call("/v1/pco/plan-context/refresh").status, 409)
        XCTAssertEqual(engine.planItems.first { $0.id == "a" }?.lengthInSeconds, 300)
        engine.isPCOConnected = true
        XCTAssertEqual(engine.actualLengthChanges().map(\.itemId), ["a"])
    }

    func testSwitchingRehearsalTimesRebroadcastsTheNextItem() {
        let excluded = PCOItemTimeInfo(id: "x", planTimeId: "r2", exclude: true)
        let engine = makeEngine([item("a"), item("b", times: [excluded]), item("c")])
        engine.pcoPlanContext = PCOPlanContext(planId: "plan1", serviceTypeId: "st", times: [
            PCOPlanTimeInfo(id: "r1", timeType: "rehearsal"), PCOPlanTimeInfo(id: "r2", timeType: "rehearsal"),
        ])
        XCTAssertTrue(engine.setRehearsalMode(true, planTimeId: "r1"))
        XCTAssertEqual(engine.nextItemForBroadcast?.id, "b")
        sent = []
        XCTAssertTrue(engine.setRehearsalMode(true, planTimeId: "r2"))
        XCTAssertEqual(engine.nextItemForBroadcast?.id, "c")
        XCTAssertTrue(sent.contains { $0.packet.nextItem?.id == "c" })
    }

    func testStateSnapshotAndRoutesExposeLiveOps() throws {
        let engine = makeEngine()
        setElapsed(engine, 100)
        engine.nextPlanItem()
        let router = ControlAPIRouter(engine: engine)
        func call(_ method: String, _ path: String, _ body: String? = nil) -> HTTPResponse {
            router.handle(HTTPRequest(method: method, path: path, body: body.map { Data($0.utf8) } ?? Data()))
        }
        func json(_ response: HTTPResponse) -> [String: Any] {
            (try? JSONSerialization.jsonObject(with: response.body) as? [String: Any]) ?? [:]
        }

        let skip = call("POST", "/v1/plan/items/c/skip", #"{"skipped":true}"#)
        XCTAssertEqual(skip.status, 200)
        XCTAssertEqual(json(skip)["skippedItemIds"] as? [String], ["c"])
        XCTAssertEqual(call("POST", "/v1/plan/items/nope/skip").status, 404)

        let state = json(call("GET", "/v1/state"))
        let liveOps = state["liveOps"] as? [String: Any]
        XCTAssertEqual(liveOps?["isRehearsalMode"] as? Bool, false)
        XCTAssertEqual((liveOps?["skippedItemIds"] as? [String: [String]])?["e1"], ["c"])
        XCTAssertEqual((liveOps?["actuals"] as? [[String: Any]])?.first?["itemId"] as? String, "a")

        let actuals = json(call("GET", "/v1/plan/actuals"))
        XCTAssertEqual(actuals["eventTimeId"] as? String, "e1")
        XCTAssertEqual((actuals["actuals"] as? [[String: Any]])?.count, 2)

        XCTAssertEqual(call("POST", "/v1/plan/items/c/skip", #"{"skipped":false}"#).status, 200)
        XCTAssertFalse(engine.isItemSkipped("c"))
        XCTAssertEqual(call("POST", "/v1/plan/items/c/skip").status, 200)
        XCTAssertTrue(engine.isItemSkipped("c"))
        XCTAssertEqual(call("DELETE", "/v1/plan/items/c/skip").status, 200)
        XCTAssertFalse(engine.isItemSkipped("c"))

        XCTAssertEqual(call("PUT", "/v1/rehearsal", #"{"enabled":true}"#).status, 200)
        XCTAssertTrue(engine.isRehearsalMode)
        XCTAssertEqual(json(call("GET", "/v1/rehearsal"))["enabled"] as? Bool, true)
        XCTAssertEqual(call("PUT", "/v1/rehearsal", #"{"enabled":true,"planTimeId":"nope"}"#).status, 404)
        XCTAssertEqual(call("PUT", "/v1/rehearsal", #"{"enabled":false}"#).status, 200)
        XCTAssertFalse(engine.isRehearsalMode)

        XCTAssertEqual(call("DELETE", "/v1/plan/actuals").status, 200)
        XCTAssertTrue(engine.currentItemActuals.filter { $0.endedAt != nil }.isEmpty)
        XCTAssertEqual(call("POST", "/v1/plan/actuals/save-to-pco").status, 409)
        XCTAssertEqual(call("POST", "/v1/plan/items/a/use-actual").status, 409)
    }

    func testMirrorAppliesLiveOpsFromState() {
        let host = makeEngine()
        setElapsed(host, 100)
        host.nextPlanItem()
        host.setItemSkipped(id: "c", skipped: true)
        host.setRehearsalMode(true)
        let router = ControlAPIRouter(engine: host)
        let response = router.handle(HTTPRequest(method: "GET", path: "/v1/state", body: Data()))
        let state = try? ControlAPIJSON.decoder.decode(ControlAPIState.self, from: response.body)
        XCTAssertNotNil(state)

        let mirror = CueEngine(mirroring: nil)
        mirror.apply(remoteState: state!)
        XCTAssertTrue(mirror.isRehearsalMode)
        XCTAssertEqual(mirror.skippedItemIds, host.skippedItemIds)
        XCTAssertEqual(mirror.itemActuals.map(\.itemId), ["a"])
        XCTAssertEqual(mirror.skipsKey, "rehearsal")
    }
}
