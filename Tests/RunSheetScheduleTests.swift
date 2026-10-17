// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

final class RunSheetScheduleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(
        _ id: String,
        length: Int,
        type: String = "Item",
        position: PCOServicePosition = .during,
        itemTimes: [PCOItemTimeInfo] = []
    ) -> PCOTimerItem {
        let needsDetails = position != .during || !itemTimes.isEmpty
        let details = needsDetails ? PCOItemDetails(servicePosition: position, itemTimes: itemTimes) : nil
        return PCOTimerItem(id: id, title: id, itemType: type, lengthInSeconds: length, details: details)
    }

    private func offset(_ date: Date?) -> Int? {
        date.map { Int($0.timeIntervalSince(start)) }
    }

    func testPlannedStartsChainFromEventStart() {
        let items = [item("a", length: 300), item("b", length: 120), item("c", length: 60)]
        let schedule = RunSheetSchedule(items: items, startDate: start, planTimeId: nil)
        XCTAssertEqual(schedule.entries.map { offset($0.plannedStart) }, [0, 300, 420])
        XCTAssertEqual(schedule.plannedLength, 480)
        XCTAssertEqual(offset(schedule.plannedEnd), 480)
        XCTAssertEqual(offset(schedule.projectedEnd), 480)
        XCTAssertEqual(schedule.overUnderSeconds, 0)
    }

    func testPreItemsAreScheduledBackwardsAndPostItemsAfterTheLastDuringItem() {
        let items = [
            item("pre1", length: 600, position: .pre),
            item("pre2", length: 300, position: .pre),
            item("a", length: 300),
            item("b", length: 200),
            item("post", length: 100, position: .post)
        ]
        let schedule = RunSheetSchedule(items: items, startDate: start, planTimeId: nil)
        XCTAssertEqual(schedule.entries.map { offset($0.plannedStart) }, [-900, -300, 0, 300, 500])
        XCTAssertEqual(schedule.plannedLength, 500)
        XCTAssertEqual(schedule.preLength, 900)
        XCTAssertEqual(schedule.postLength, 100)
        XCTAssertEqual(offset(schedule.plannedEnd), 500)
    }

    func testExclusionIsPerPlanTime() {
        let times = [
            PCOItemTimeInfo(id: "t1", planTimeId: "early", exclude: false),
            PCOItemTimeInfo(id: "t2", planTimeId: "late", exclude: true)
        ]
        let items = [item("a", length: 300), item("skip", length: 200, itemTimes: times), item("b", length: 100)]

        let early = RunSheetSchedule(items: items, startDate: start, planTimeId: "early")
        XCTAssertEqual(early.entries.map(\.isExcluded), [false, false, false])
        XCTAssertEqual(early.plannedLength, 600)

        let late = RunSheetSchedule(items: items, startDate: start, planTimeId: "late")
        XCTAssertEqual(late.entries.map(\.isExcluded), [false, true, false])
        XCTAssertEqual(late.entries.map { offset($0.plannedStart) }, [0, nil, 300])
        XCTAssertEqual(late.plannedLength, 400)

        let unknown = RunSheetSchedule(items: items, startDate: start, planTimeId: nil)
        XCTAssertEqual(unknown.entries.map(\.isExcluded), [false, false, false])
    }

    func testPerPlanTimeLengthOverridesItemLength() {
        let times = [PCOItemTimeInfo(id: "t1", planTimeId: "late", length: 500)]
        let items = [item("a", length: 300, itemTimes: times), item("b", length: 100)]

        let late = RunSheetSchedule(items: items, startDate: start, planTimeId: "late")
        XCTAssertEqual(late.entries.map(\.length), [500, 100])
        XCTAssertEqual(offset(late.entries[1].plannedStart), 500)
        XCTAssertEqual(late.plannedLength, 600)

        let other = RunSheetSchedule(items: items, startDate: start, planTimeId: "early")
        XCTAssertEqual(other.entries.map(\.length), [300, 100])
    }

    func testProjectedStartsDriftWithTheActiveItem() {
        let items = [item("a", length: 300), item("b", length: 300), item("c", length: 300)]
        let now = start.addingTimeInterval(400)
        let schedule = RunSheetSchedule(items: items, startDate: start, planTimeId: nil, activeIndex: 1, activeElapsed: 130, now: now)
        XCTAssertEqual(schedule.entries.map { offset($0.plannedStart) }, [0, 300, 600])
        XCTAssertEqual(schedule.entries.map { offset($0.projectedStart) }, [0, 270, 570])
        XCTAssertEqual(schedule.entries[1].driftSeconds, -30)
        XCTAssertEqual(offset(schedule.projectedEnd), 870)
        XCTAssertEqual(schedule.overUnderSeconds, -30)
    }

    func testOvertimeActiveItemProjectsToNow() {
        let items = [item("a", length: 300), item("b", length: 300)]
        let now = start.addingTimeInterval(500)
        let schedule = RunSheetSchedule(items: items, startDate: start, planTimeId: nil, activeIndex: 0, activeElapsed: 500, now: now)
        XCTAssertEqual(offset(schedule.entries[1].projectedStart), 500)
        XCTAssertEqual(schedule.entries[1].driftSeconds, 200)
        XCTAssertEqual(schedule.overUnderSeconds, 200)
    }

    func testActiveLengthOverrideIsUsedForTheActiveItem() {
        let items = [item("a", length: 300), item("b", length: 300)]
        let now = start.addingTimeInterval(100)
        let schedule = RunSheetSchedule(items: items, startDate: start, planTimeId: nil, activeIndex: 0, activeElapsed: 100, activeLength: 400, now: now)
        XCTAssertEqual(offset(schedule.entries[1].projectedStart), 400)
    }

    func testProjectionSkipsExcludedItemsAndHeaders() {
        let times = [PCOItemTimeInfo(id: "t1", planTimeId: "pt", exclude: true)]
        let items = [item("a", length: 100), item("skip", length: 999, itemTimes: times), item("h", length: 0, type: "Header"), item("b", length: 100)]
        let now = start.addingTimeInterval(160)
        let schedule = RunSheetSchedule(items: items, startDate: start, planTimeId: "pt", activeIndex: 0, activeElapsed: 160, now: now)
        XCTAssertNil(schedule.entries[1].projectedStart)
        XCTAssertEqual(offset(schedule.entries[2].projectedStart), 160)
        XCTAssertEqual(offset(schedule.entries[3].projectedStart), 160)
        XCTAssertEqual(offset(schedule.projectedEnd), 260)
    }

    func testFirstDuringItemNeverProjectsEarlierThanPlannedWhilePreItemRuns() {
        let items = [item("pre", length: 600, position: .pre), item("a", length: 300)]
        let now = start.addingTimeInterval(-1200)
        let schedule = RunSheetSchedule(items: items, startDate: start, planTimeId: nil, activeIndex: 0, activeElapsed: 0, now: now)
        XCTAssertEqual(offset(schedule.entries[1].projectedStart), 0)
        XCTAssertEqual(offset(schedule.projectedEnd), 300)
    }

    func testOverrunningPreItemPushesTheEventBack() {
        let items = [item("pre", length: 600, position: .pre), item("a", length: 300), item("post", length: 60, position: .post)]
        let now = start.addingTimeInterval(120)
        let schedule = RunSheetSchedule(items: items, startDate: start, planTimeId: nil, activeIndex: 0, activeElapsed: 720, now: now)
        XCTAssertEqual(offset(schedule.entries[1].projectedStart), 120)
        XCTAssertEqual(offset(schedule.entries[2].projectedStart), 420)
        XCTAssertEqual(schedule.overUnderSeconds, 120)
    }

    func testNoStartTimeStillTotalsLengthsButLeavesStartsNil() {
        let items = [item("a", length: 300), item("b", length: 120)]
        let schedule = RunSheetSchedule(items: items, startDate: nil, planTimeId: nil, activeIndex: 0, activeElapsed: 10)
        XCTAssertEqual(schedule.plannedLength, 420)
        XCTAssertEqual(schedule.entries.map(\.length), [300, 120])
        XCTAssertTrue(schedule.entries.allSatisfy { $0.plannedStart == nil && $0.projectedStart == nil })
        XCTAssertNil(schedule.plannedEnd)
        XCTAssertNil(schedule.projectedEnd)
        XCTAssertNil(schedule.overUnderSeconds)
    }

    func testHeadersHaveNoLengthAndCollectSubtotals() {
        let times = [PCOItemTimeInfo(id: "t1", planTimeId: "pt", exclude: true)]
        let items = [
            item("h1", length: 500, type: "Header"),
            item("a", length: 100),
            item("b", length: 200, itemTimes: times),
            item("h2", length: 0, type: "header"),
            item("c", length: 50),
            item("d", length: 25)
        ]
        let schedule = RunSheetSchedule(items: items, startDate: start, planTimeId: "pt")
        XCTAssertEqual(schedule.entries[0].length, 0)
        XCTAssertEqual(schedule.headerSubtotals["h1"], 100)
        XCTAssertEqual(schedule.headerSubtotals["h2"], 75)
        XCTAssertEqual(schedule.plannedLength, 175)
        XCTAssertEqual(offset(schedule.entries[0].plannedStart), 0)
        XCTAssertEqual(offset(schedule.entries[4].plannedStart), 100)
    }

    func testHeaderSubtotalsDoNotCrossServicePositions() {
        let items = [
            item("h1", length: 0, type: "Header"),
            item("a", length: 100),
            item("h2", length: 0, type: "Header", position: .post),
            item("p", length: 40, position: .post)
        ]
        let schedule = RunSheetSchedule(items: items, startDate: start, planTimeId: nil)
        XCTAssertEqual(schedule.headerSubtotals["h1"], 100)
        XCTAssertEqual(schedule.headerSubtotals["h2"], 40)
    }

    func testEntryLookupByIdAndNoActiveItemProjectsThePlan() {
        let items = [item("a", length: 300), item("b", length: 120)]
        let schedule = RunSheetSchedule(items: items, startDate: start, planTimeId: nil, activeIndex: nil)
        XCTAssertEqual(offset(schedule.entry(forItemId: "b")?.projectedStart), 300)
        XCTAssertNil(schedule.entry(forItemId: "missing"))
    }
}

final class RunSheetItemPresentationTests: XCTestCase {
    func testKindFollowsItemTypeOrDetails() {
        XCTAssertEqual(PCOTimerItem(title: "H", itemType: "header").runSheetKind, .header)
        XCTAssertEqual(PCOTimerItem(title: "S", itemType: "Song").runSheetKind, .song)
        XCTAssertEqual(PCOTimerItem(title: "M", itemType: "item", details: PCOItemDetails(media: PCOMediaInfo(id: "m"))).runSheetKind, .media)
        XCTAssertEqual(PCOTimerItem(title: "I").runSheetKind, .item)
    }

    func testSongAccessors() {
        let details = PCOItemDetails(
            keyName: "G",
            song: PCOSongInfo(id: "s", author: "Someone"),
            arrangement: PCOArrangementInfo(id: "a", name: "Default", bpm: 72, meter: "4/4", sequenceShort: ["V1", "C"])
        )
        let item = PCOTimerItem(title: "Song", itemType: "song", details: details)
        XCTAssertEqual(item.runSheetBPMText, "72")
        XCTAssertEqual(item.runSheetMeter, "4/4")
        XCTAssertEqual(item.runSheetArrangementName, "Default")
        XCTAssertEqual(item.runSheetSequenceText, "V1 C")
        XCTAssertEqual(item.runSheetAuthor, "Someone")
    }

    func testMediaTypeLabelIsHumanized() {
        let item = PCOTimerItem(title: "Clip", itemType: "media", details: PCOItemDetails(media: PCOMediaInfo(id: "m", mediaType: "countdown_video")))
        XCTAssertEqual(item.runSheetTypeLabel, "Countdown Video")
    }
}

@MainActor
final class RunSheetEngineTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "persistedFlow")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "persistedFlow")
        super.tearDown()
    }

    private func makeEngine() -> CueEngine {
        let engine = CueEngine(startsNetworking: false)
        engine.importFlow(title: "Plan", items: [
            PCOTimerItem(id: "a", title: "Walk-in", itemType: "Item", lengthInSeconds: 60),
            PCOTimerItem(id: "b", title: "Song", itemType: "Song", lengthInSeconds: 200)
        ])
        return engine
    }

    func testManualItemDetailsCreateAndClear() {
        let engine = makeEngine()
        XCTAssertNil(engine.planItems[0].details)

        engine.updatePlanItem(id: "a", title: "Walk-in", itemType: "Item", lengthInSeconds: 60, description: "  Play music ", servicePosition: .pre)
        XCTAssertEqual(engine.planItems[0].details?.description, "Play music")
        XCTAssertEqual(engine.planItems[0].details?.servicePosition, .pre)

        engine.updatePlanItem(id: "a", title: "Walk-in", itemType: "Item", lengthInSeconds: 60, description: "", servicePosition: .during)
        XCTAssertNil(engine.planItems[0].details)
    }

    func testPCOItemDetailsAreNotOverwrittenByManualEdit() {
        let engine = makeEngine()
        engine.planItems[1].pcoPlanId = "plan"
        engine.planItems[1].details = PCOItemDetails(description: "From PCO", servicePosition: .pre)

        engine.updatePlanItem(id: "b", title: "Song", itemType: "Song", lengthInSeconds: 200, description: "Local", servicePosition: .post)
        XCTAssertEqual(engine.planItems[1].details?.description, "From PCO")
        XCTAssertEqual(engine.planItems[1].details?.servicePosition, .pre)
    }

    func testEngineScheduleUsesTheLiveEventTime() {
        let engine = makeEngine()
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let time = EventTime(name: "Late", day: EventDay(date: day), startTime: TimeOfDay(hour: 11, minute: 0))
        engine.restoreEventTimes([time], liveId: time.id)

        let schedule = engine.runSheetSchedule(now: day)
        XCTAssertEqual(schedule.plannedLength, 260)
        XCTAssertEqual(schedule.entries[0].plannedStart, time.startDate(onOrAfter: day))
        XCTAssertEqual(engine.liveEventTimeLabel, "Late")
    }
}
