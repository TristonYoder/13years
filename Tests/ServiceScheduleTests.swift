// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

@MainActor
final class ServiceScheduleTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearPersistedState()
    }

    override func tearDown() {
        clearPersistedState()
        super.tearDown()
    }

    private func clearPersistedState() {
        UserDefaults.standard.removeObject(forKey: "persistedFlow")
        UserDefaults.standard.removeObject(forKey: "persistedRoles")
        UserDefaults.standard.removeObject(forKey: "isPCOLiveSyncEnabled")
        UserDefaults.standard.removeObject(forKey: "recentMessages")
        UserDefaults.standard.removeObject(forKey: "notificationsClearedAt")
        UserDefaults.standard.removeObject(forKey: "waypoints")
        UserDefaults.standard.removeObject(forKey: "serviceTags")
        UserDefaults.standard.removeObject(forKey: "serviceSchedules")
    }

    func testGoLiveAtIsStartsAtMinusOffset() {
        let startsAt = Date(timeIntervalSince1970: 1_700_000_000)
        let schedule = ServiceSchedule(title: "Sunday", startsAt: startsAt, goLiveOffsetSeconds: 1800)
        XCTAssertEqual(schedule.goLiveAt, startsAt.addingTimeInterval(-1800))
    }

    func testGoLiveOffsetMinutesRoundTrips() {
        var schedule = ServiceSchedule(title: "Sunday", startsAt: Date())
        schedule.goLiveOffsetMinutes = 45
        XCTAssertEqual(schedule.goLiveOffsetSeconds, 2700)
        XCTAssertEqual(schedule.goLiveOffsetMinutes, 45)
    }

    func testShouldFireIsFalseBeforeGoLiveAt() {
        let startsAt = Date(timeIntervalSince1970: 1_700_000_000)
        let schedule = ServiceSchedule(title: "Sunday", startsAt: startsAt, goLiveOffsetSeconds: 1800)
        XCTAssertFalse(schedule.shouldFire(at: schedule.goLiveAt.addingTimeInterval(-1)))
    }

    func testShouldFireIsTrueAtExactlyGoLiveAt() {
        let startsAt = Date(timeIntervalSince1970: 1_700_000_000)
        let schedule = ServiceSchedule(title: "Sunday", startsAt: startsAt, goLiveOffsetSeconds: 1800)
        XCTAssertTrue(schedule.shouldFire(at: schedule.goLiveAt))
    }

    func testShouldFireIsTrueBetweenGoLiveAtAndStartsAt() {
        let startsAt = Date(timeIntervalSince1970: 1_700_000_000)
        let schedule = ServiceSchedule(title: "Sunday", startsAt: startsAt, goLiveOffsetSeconds: 1800)
        XCTAssertTrue(schedule.shouldFire(at: startsAt.addingTimeInterval(-900)))
    }

    func testShouldFireIsTrueInsideLateFireGraceAfterStartsAt() {
        let startsAt = Date(timeIntervalSince1970: 1_700_000_000)
        let schedule = ServiceSchedule(title: "Sunday", startsAt: startsAt, goLiveOffsetSeconds: 1800)
        XCTAssertTrue(schedule.shouldFire(at: startsAt.addingTimeInterval(ServiceSchedule.lateFireGrace - 1)))
    }

    func testShouldFireIsFalsePastLateFireGrace() {
        let startsAt = Date(timeIntervalSince1970: 1_700_000_000)
        let schedule = ServiceSchedule(title: "Sunday", startsAt: startsAt, goLiveOffsetSeconds: 1800)
        XCTAssertFalse(schedule.shouldFire(at: startsAt.addingTimeInterval(ServiceSchedule.lateFireGrace + 1)))
    }

    func testShouldFireIsFalseWhenDisabled() {
        let startsAt = Date(timeIntervalSince1970: 1_700_000_000)
        var schedule = ServiceSchedule(title: "Sunday", startsAt: startsAt, goLiveOffsetSeconds: 1800, isEnabled: false)
        XCTAssertFalse(schedule.shouldFire(at: schedule.goLiveAt))
        schedule.isEnabled = true
        XCTAssertTrue(schedule.shouldFire(at: schedule.goLiveAt))
    }

    func testShouldFireIsFalseWhenAlreadyFiredThisWindow() {
        let startsAt = Date(timeIntervalSince1970: 1_700_000_000)
        var schedule = ServiceSchedule(title: "Sunday", startsAt: startsAt, goLiveOffsetSeconds: 1800)
        schedule.lastFiredAt = schedule.goLiveAt
        XCTAssertFalse(schedule.shouldFire(at: schedule.goLiveAt))
    }

    func testShouldFireIsTrueWhenLastFiredAtIsFromAPreviousWeek() {
        let startsAt = Date(timeIntervalSince1970: 1_700_000_000)
        var schedule = ServiceSchedule(title: "Sunday", startsAt: startsAt, goLiveOffsetSeconds: 1800)
        schedule.lastFiredAt = schedule.goLiveAt.addingTimeInterval(-7 * 24 * 3600)
        XCTAssertTrue(schedule.shouldFire(at: schedule.goLiveAt))
    }

    func testNextOccurrenceReturnsNilForOnce() {
        let schedule = ServiceSchedule(title: "Sunday", startsAt: Date(), recurrence: .once)
        XCTAssertNil(schedule.nextOccurrence(after: Date()))
    }

    func testNextOccurrenceWeeklyIsWholeDaysLaterAndPreservesWallClockAcrossDST() {
        let probeStart = Date(timeIntervalSince1970: 0)
        let systemObservesDST = TimeZone.current.nextDaylightSavingTimeTransition(after: probeStart) != nil

        var calendar = Calendar(identifier: .gregorian)
        if systemObservesDST {
            calendar = Calendar.current
        } else {
            calendar.timeZone = TimeZone(identifier: "America/New_York")!
        }

        guard let searchStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)),
              let transition = calendar.timeZone.nextDaylightSavingTimeTransition(after: searchStart) else {
            XCTFail("Expected \(calendar.timeZone.identifier) to have a DST transition in 2026 to test against")
            return
        }

        var startComponents = calendar.dateComponents([.year, .month, .day], from: transition)
        startComponents.hour = 10
        startComponents.minute = 0
        startComponents.second = 0
        guard let transitionDayAt10 = calendar.date(from: startComponents),
              let startsAt = calendar.date(byAdding: .day, value: -7, to: transitionDayAt10) else {
            XCTFail("Could not construct test dates")
            return
        }

        let schedule = ServiceSchedule(title: "Sunday Service", startsAt: startsAt, recurrence: .weekly)
        guard let next = schedule.nextOccurrence(after: startsAt) else {
            XCTFail("Expected a next occurrence for a .weekly schedule")
            return
        }

        XCTAssertGreaterThan(next, startsAt)

        let dayDelta = calendar.dateComponents([.day], from: startsAt, to: next).day
        XCTAssertEqual(dayDelta, 7, "expected exactly seven calendar days between occurrences")

        let nextComponents = calendar.dateComponents([.hour, .minute], from: next)
        XCTAssertEqual(nextComponents.hour, 10)
        XCTAssertEqual(nextComponents.minute, 0)
    }

    func testAddServiceScheduleRejectsEmptyTitleAndNegativeOffset() {
        let engine = CueEngine()
        XCTAssertNil(engine.addServiceSchedule(title: "", startsAt: Date()))
        XCTAssertNil(engine.addServiceSchedule(title: "   ", startsAt: Date()))
        XCTAssertNil(engine.addServiceSchedule(title: "Sunday", startsAt: Date(), goLiveOffsetSeconds: -1))
        XCTAssertEqual(engine.serviceSchedules.count, 0)
    }

    func testAddServiceScheduleKeepsArraySortedByStartsAt() {
        let engine = CueEngine()
        let base = Date()
        _ = engine.addServiceSchedule(title: "Third", startsAt: base.addingTimeInterval(3000))
        _ = engine.addServiceSchedule(title: "First", startsAt: base.addingTimeInterval(1000))
        _ = engine.addServiceSchedule(title: "Second", startsAt: base.addingTimeInterval(2000))
        XCTAssertEqual(engine.serviceSchedules.map(\.title), ["First", "Second", "Third"])
    }

    func testUpdateServiceScheduleLeavesAbsentFieldsAlone() {
        let engine = CueEngine()
        let schedule = engine.addServiceSchedule(title: "Sunday", startsAt: Date(), goLiveOffsetSeconds: 900)!
        engine.updateServiceSchedule(id: schedule.id, title: "Sunday AM")
        let updated = engine.serviceSchedule(id: schedule.id)!
        XCTAssertEqual(updated.title, "Sunday AM")
        XCTAssertEqual(updated.startsAt, schedule.startsAt)
        XCTAssertEqual(updated.goLiveOffsetSeconds, 900)
    }

    func testUpdateServiceScheduleClearsLastFiredAtWhenStartsAtChanges() {
        let engine = CueEngine()
        let schedule = engine.addServiceSchedule(title: "Sunday", startsAt: Date(), recurrence: .once)!
        engine.goLiveWithSchedule(id: schedule.id)
        XCTAssertNotNil(engine.serviceSchedule(id: schedule.id)?.lastFiredAt)

        engine.updateServiceSchedule(id: schedule.id, startsAt: Date().addingTimeInterval(86400))
        XCTAssertNil(engine.serviceSchedule(id: schedule.id)?.lastFiredAt)
    }

    func testUpdateServiceScheduleClearsLastFiredAtWhenOffsetChanges() {
        let engine = CueEngine()
        let schedule = engine.addServiceSchedule(title: "Sunday", startsAt: Date(), recurrence: .once)!
        engine.goLiveWithSchedule(id: schedule.id)
        XCTAssertNotNil(engine.serviceSchedule(id: schedule.id)?.lastFiredAt)

        engine.updateServiceSchedule(id: schedule.id, goLiveOffsetSeconds: 600)
        XCTAssertNil(engine.serviceSchedule(id: schedule.id)?.lastFiredAt)
    }

    func testRemoveServiceScheduleAndLookupById() {
        let engine = CueEngine()
        let schedule = engine.addServiceSchedule(title: "Sunday", startsAt: Date())!
        XCTAssertNotNil(engine.serviceSchedule(id: schedule.id))

        engine.removeServiceSchedule(id: schedule.id)

        XCTAssertNil(engine.serviceSchedule(id: schedule.id))
    }

    func testNextScheduledServiceSkipsDisabledAndPastGoLiveEntries() {
        let engine = CueEngine()
        let now = Date()
        _ = engine.addServiceSchedule(title: "Disabled", startsAt: now.addingTimeInterval(3600), goLiveOffsetSeconds: 0, isEnabled: false)
        _ = engine.addServiceSchedule(title: "AlreadyPastGoLive", startsAt: now.addingTimeInterval(10), goLiveOffsetSeconds: 3600)
        let future = engine.addServiceSchedule(title: "Future", startsAt: now.addingTimeInterval(7200), goLiveOffsetSeconds: 0)!

        XCTAssertEqual(engine.nextScheduledService?.id, future.id)
    }

    func testGoLiveWithScheduleOnceStampsLastFiredAtAndDisablesIt() {
        let engine = CueEngine()
        let schedule = engine.addServiceSchedule(title: "Sunday", startsAt: Date(), recurrence: .once)!

        engine.goLiveWithSchedule(id: schedule.id)

        let updated = engine.serviceSchedule(id: schedule.id)!
        XCTAssertNotNil(updated.lastFiredAt)
        XCTAssertFalse(updated.isEnabled)
        XCTAssertFalse(updated.shouldFire(at: Date()))
        XCTAssertEqual(engine.appMode, .producerControl)
    }

    func testGoLiveWithScheduleWeeklyRollsStartsAtForwardAndStaysArmed() {
        let engine = CueEngine()
        let startsAt = Date()
        let schedule = engine.addServiceSchedule(title: "Sunday", startsAt: startsAt, recurrence: .weekly)!

        engine.goLiveWithSchedule(id: schedule.id)

        let updated = engine.serviceSchedule(id: schedule.id)!
        XCTAssertNil(updated.lastFiredAt)
        XCTAssertTrue(updated.isEnabled)
        XCTAssertGreaterThan(updated.startsAt, startsAt)
        XCTAssertEqual(updated.startsAt.timeIntervalSince(startsAt), 7 * 24 * 3600, accuracy: 3700)
        XCTAssertTrue(updated.shouldFire(at: updated.goLiveAt))
    }

    func testFiringScheduleWithNoPCOPlanIdsDoesNotCrashOrClearTheLoadedPlan() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let originalItemIds = engine.planItems.map(\.id)
        let schedule = engine.addServiceSchedule(title: "Sunday", startsAt: Date())!

        engine.goLiveWithSchedule(id: schedule.id)

        XCTAssertEqual(engine.planItems.map(\.id), originalItemIds)
        XCTAssertEqual(engine.appMode, .producerControl)
    }
}
