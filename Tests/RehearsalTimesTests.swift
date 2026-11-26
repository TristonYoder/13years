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
