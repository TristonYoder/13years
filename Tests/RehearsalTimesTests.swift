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

@MainActor
final class PCOUnlinkTests: XCTestCase {
    func testUnlinkingKeepsTheContentAndHandsTheTimesToThisApp() throws {
        let engine = CueEngine()
        engine.importFlow(title: "Easter", items: [
            PCOTimerItem(id: "a", title: "Song", itemType: "Item", lengthInSeconds: 60, noteIds: ["Lights": "n1"], pcoServiceTypeId: "st", pcoPlanId: "p")
        ])
        engine.eventTimes = [EventTime(id: "t1", name: "Early", day: .weekday(1), startTime: TimeOfDay(hour: 9, minute: 30), pcoPlanTimeId: "t1")]
        engine.pcoPlanContext = PCOPlanContext(
            planId: "p", serviceTypeId: "st", title: "Easter",
            times: [PCOPlanTimeInfo(id: "r1", name: "Band", timeType: "rehearsal", startsAt: Date(timeIntervalSince1970: 1_700_000_000))],
            fetchedAt: Date()
        )
        XCTAssertTrue(engine.isLinkedToPCOPlan)
        XCTAssertTrue(engine.isEventTimesManagedByPCO)

        engine.unlinkPCOPlan()

        XCTAssertFalse(engine.isLinkedToPCOPlan)
        XCTAssertFalse(engine.isEventTimesManagedByPCO)
        XCTAssertNil(engine.pcoPlanContext)
        XCTAssertEqual(engine.planItems.map(\.title), ["Song"])
        XCTAssertNil(engine.planItems[0].pcoPlanId)
        XCTAssertTrue(engine.planItems[0].noteIds.isEmpty)
        XCTAssertEqual(engine.planTitle, "Easter")
        XCTAssertEqual(engine.eventTimes.map(\.id), ["t1"])
        XCTAssertNil(engine.eventTimes[0].pcoPlanTimeId)
        XCTAssertEqual(engine.manualRehearsalTimes.map(\.id), ["r1"])
        XCTAssertEqual(engine.rehearsalPlanTimes.map(\.name), ["Band"])
        // Now editable here.
        XCTAssertNotNil(engine.addEventTime(name: "Late", day: nil, startTime: TimeOfDay(hour: 11, minute: 0)))
    }

    func testUnlinkingARunSheetThatIsNotLinkedDoesNothing() {
        let engine = CueEngine()
        engine.importFlow(title: nil, items: [PCOTimerItem(id: "a", title: "A", itemType: "Item", lengthInSeconds: 60)])
        XCTAssertFalse(engine.isLinkedToPCOPlan)
        engine.unlinkPCOPlan()
        XCTAssertEqual(engine.planItems.count, 1)
    }
}

@MainActor
final class PlanTitleEditingTests: XCTestCase {
    func testAnUnlinkedPlanCanBeNamedAndRenamed() {
        let engine = CueEngine()
        engine.importFlow(title: nil, items: [PCOTimerItem(id: "a", title: "A", itemType: "Item", lengthInSeconds: 60)])
        engine.setPlanTitle("  Sunday Service ")
        XCTAssertEqual(engine.planTitle, "Sunday Service")
        engine.setPlanTitle("   ")
        XCTAssertNil(engine.planTitle)
    }

    func testALinkedPlanKeepsItsPlanningCenterName() {
        let engine = CueEngine()
        engine.importFlow(title: "Easter", items: [PCOTimerItem(id: "a", title: "A", itemType: "Item", lengthInSeconds: 60, pcoServiceTypeId: "st", pcoPlanId: "p")])
        engine.setPlanTitle("Something else")
        XCTAssertEqual(engine.planTitle, "Easter")
        engine.unlinkPCOPlan()
        engine.setPlanTitle("Our Easter")
        XCTAssertEqual(engine.planTitle, "Our Easter")
    }

    func testThePlanTitleIsSetThroughTheControlAPI() throws {
        let engine = CueEngine()
        let router = ControlAPIRouter(engine: engine)
        engine.importFlow(title: nil, items: [PCOTimerItem(id: "a", title: "A", itemType: "Item", lengthInSeconds: 60)])
        let reply = router.handle(HTTPRequest(method: "PATCH", path: "/v1/plan/title", body: Data(#"{"title":"Wednesday"}"#.utf8)))
        XCTAssertEqual(reply.status, 200)
        XCTAssertEqual(engine.planTitle, "Wednesday")
    }
}

@MainActor
final class ScheduleTargetTests: XCTestCase {
    func testGoingLiveMakesTheTargetTimeCurrentAndCanStartTheFirstItem() throws {
        let engine = CueEngine()
        engine.importFlow(title: nil, items: [
            PCOTimerItem(id: "h", title: "Pre-Service", itemType: "header", lengthInSeconds: 0),
            PCOTimerItem(id: "a", title: "Countdown", itemType: "Item", lengthInSeconds: 300),
            PCOTimerItem(id: "b", title: "Welcome", itemType: "Item", lengthInSeconds: 60)
        ])
        let early = try XCTUnwrap(engine.addEventTime(name: "Early", day: nil, startTime: TimeOfDay(hour: 9, minute: 0)))
        let late = try XCTUnwrap(engine.addEventTime(name: "Late", day: nil, startTime: TimeOfDay(hour: 11, minute: 0)))
        engine.setLiveEventTime(id: early.id)
        let schedule = try XCTUnwrap(engine.addServiceSchedule(
            title: "Late", startsAt: Date().addingTimeInterval(3600), recurrence: .once,
            target: ServiceSchedule.TimeTarget(kind: .event, id: late.id), startsFirstItem: true
        ))
        engine.goLiveWithSchedule(id: schedule.id)
        XCTAssertEqual(engine.liveEventTime?.id, late.id)
        XCTAssertEqual(engine.activeTimerItem?.id, "a")
        XCTAssertEqual(engine.activeTimerItem?.isRunning, true)
    }

    func testARehearsalTargetEntersRehearsalAndAMissingTimeIsSkipped() throws {
        let engine = CueEngine()
        engine.importFlow(title: nil, items: [PCOTimerItem(id: "a", title: "A", itemType: "Item", lengthInSeconds: 60)])
        let rehearsal = try XCTUnwrap(engine.addRehearsalTime(name: "Band", day: nil, startTime: TimeOfDay(hour: 18, minute: 0)))
        let schedule = try XCTUnwrap(engine.addServiceSchedule(
            title: "Band", startsAt: Date().addingTimeInterval(3600), recurrence: .once,
            target: ServiceSchedule.TimeTarget(kind: .rehearsal, id: rehearsal.id)
        ))
        engine.goLiveWithSchedule(id: schedule.id)
        XCTAssertTrue(engine.isRehearsalMode)
        engine.setRehearsalMode(false)
        let missing = try XCTUnwrap(engine.addServiceSchedule(
            title: "Gone", startsAt: Date().addingTimeInterval(7200), recurrence: .once,
            target: ServiceSchedule.TimeTarget(kind: .event, id: "nope")
        ))
        engine.goLiveWithSchedule(id: missing.id)
        XCTAssertFalse(engine.isRehearsalMode)
    }

    func testOlderSchedulesDecodeWithoutATargetAndRoundTripTheNewFields() throws {
        let old = #"{"id":"s","title":"Sunday","startsAt":0,"goLiveOffsetSeconds":1800,"recurrence":"weekly","isEnabled":true}"#
        let decoded = try JSONDecoder().decode(ServiceSchedule.self, from: Data(old.utf8))
        XCTAssertNil(decoded.target)
        XCTAssertFalse(decoded.startsFirstItem)
        var schedule = decoded
        schedule.target = ServiceSchedule.TimeTarget(kind: .rehearsal, id: "r")
        schedule.startsFirstItem = true
        XCTAssertEqual(try JSONDecoder().decode(ServiceSchedule.self, from: JSONEncoder().encode(schedule)), schedule)
    }

    func testNextStartRollsAWeekdayForwardAndNeedsATime() {
        let now = Date()
        XCTAssertNil(CueEngine.nextStart(day: nil, time: nil, after: now))
        let start = CueEngine.nextStart(day: .weekday(1), time: TimeOfDay(hour: 9, minute: 30), after: now)
        XCTAssertNotNil(start)
        XCTAssertGreaterThan(start!, now)
        XCTAssertLessThanOrEqual(start!.timeIntervalSince(now), 7 * 86_400 + 1)
    }

    func testTheScheduleTargetIsSetThroughTheControlAPI() throws {
        let engine = CueEngine()
        let router = ControlAPIRouter(engine: engine)
        let body = #"{"title":"Band","startsAt":"2030-01-01T18:00:00Z","targetKind":"rehearsal","targetId":"r1","startsFirstItem":true}"#
        let reply = router.handle(HTTPRequest(method: "POST", path: "/v1/schedules", body: Data(body.utf8)))
        XCTAssertEqual(reply.status, 201)
        let created = try XCTUnwrap(engine.serviceSchedules.first(where: { $0.target?.id == "r1" }))
        XCTAssertEqual(created.target, ServiceSchedule.TimeTarget(kind: .rehearsal, id: "r1"))
        XCTAssertTrue(created.startsFirstItem)
    }
}

@MainActor
final class WeeklyScheduleFiringTests: XCTestCase {
    func testAWeeklyScheduleFiredDuringItsLeadTimeMovesToNextWeekAndDoesNotFireAgain() throws {
        let engine = CueEngine()
        let start = Date().addingTimeInterval(600)
        let schedule = try XCTUnwrap(engine.addServiceSchedule(title: "Weekly \(UUID().uuidString.prefix(6))", startsAt: start, goLiveOffsetSeconds: 1800, recurrence: .weekly))
        XCTAssertTrue(schedule.shouldFire(at: Date()))
        engine.goLiveWithSchedule(id: schedule.id)
        let after = try XCTUnwrap(engine.serviceSchedule(id: schedule.id))
        XCTAssertFalse(after.shouldFire(at: Date()))
        XCTAssertEqual(after.startsAt.timeIntervalSince(start), 7 * 86_400, accuracy: 3700)
        engine.removeServiceSchedule(id: schedule.id)
    }
}
