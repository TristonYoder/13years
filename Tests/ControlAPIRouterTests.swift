// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

@MainActor
final class ControlAPIRouterTests: XCTestCase {
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

    private func send(_ method: String, _ path: String, _ json: String? = nil) -> HTTPResponse {
        let engine = CueEngine()
        let router = ControlAPIRouter(engine: engine)
        let body = json.map { Data($0.utf8) } ?? Data()
        let request = HTTPRequest(method: method, path: path, body: body)
        return router.handle(request)
    }

    private func sendWithEngine(_ engine: CueEngine, _ method: String, _ path: String, _ json: String? = nil) -> HTTPResponse {
        let router = ControlAPIRouter(engine: engine)
        let body = json.map { Data($0.utf8) } ?? Data()
        let request = HTTPRequest(method: method, path: path, body: body)
        return router.handle(request)
    }

    private func decodeJSON(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func testHealthEndpointReturns200WithServiceKey() {
        let response = send("GET", "/v1/health")
        XCTAssertEqual(response.status, 200)

        guard let json = decodeJSON(response.body) else {
            XCTFail("Response body is not valid JSON")
            return
        }
        XCTAssertNotNil(json["service"])
    }

    func testStateEndpointReturns200WithRequiredKeys() {
        let response = send("GET", "/v1/state")
        XCTAssertEqual(response.status, 200)

        guard let json = decodeJSON(response.body) else {
            XCTFail("Response body is not valid JSON")
            return
        }
        XCTAssertNotNil(json["roles"])
        XCTAssertNotNil(json["plan"])
        XCTAssertNotNil(json["network"])
    }

    func testCuesSelectedWithValidStateReturns200AndSetsCueState() {
        let engine = CueEngine()
        let response = sendWithEngine(engine, "POST", "/v1/cues/selected", "{\"state\":\"GO\"}")
        XCTAssertEqual(response.status, 200)

        let selectedRole = engine.roles.first(where: { engine.selectedRoleIds.contains($0.id) })
        XCTAssertEqual(selectedRole?.state, .go)
    }

    func testCuesSelectedWithInvalidStateReturns400() {
        let response = send("POST", "/v1/cues/selected", "{\"state\":\"BOGUS\"}")
        XCTAssertEqual(response.status, 400)
    }

    func testCuesClearSetsAllRolesToOff() {
        let engine = CueEngine()
        engine.setCueForSelectedRoles(.go)
        engine.selectedRoleIds = Set(engine.roles.map { $0.id })
        engine.setCueForSelectedRoles(.standby)

        let response = sendWithEngine(engine, "POST", "/v1/cues/clear", nil)
        XCTAssertEqual(response.status, 200)

        XCTAssertTrue(engine.roles.allSatisfy { $0.state == .off })
    }

    func testCreateRoleReturns201AndAppends() {
        let engine = CueEngine()
        let initialCount = engine.roles.count
        let response = sendWithEngine(engine, "POST", "/v1/roles", "{\"name\":\"Lighting\"}")
        XCTAssertEqual(response.status, 201)
        XCTAssertEqual(engine.roles.count, initialCount + 1)

        guard let json = decodeJSON(response.body) else {
            XCTFail("Response body is not valid JSON")
            return
        }
        guard let createdId = json["id"] as? String else {
            XCTFail("Response missing id")
            return
        }

        let deleteResponse = sendWithEngine(engine, "DELETE", "/v1/roles/\(createdId)", nil)
        XCTAssertEqual(deleteResponse.status, 200)
        XCTAssertEqual(engine.roles.count, initialCount)
    }

    func testCueForUnknownRoleReturns404() {
        let response = send("POST", "/v1/roles/unknown123/cue", "{\"state\":\"GO\"}")
        XCTAssertEqual(response.status, 404)
    }

    func testTimerAdjustIncreasesActiveLengthInSeconds() {
        let engine = CueEngine()
        engine.importFlow(
            title: "Test",
            items: [
                PCOTimerItem(title: "A", itemType: "item", sequence: 1, lengthInSeconds: 300),
                PCOTimerItem(title: "B", itemType: "item", sequence: 2, lengthInSeconds: 600),
            ]
        )
        let initialLength = engine.activeTimerItem?.lengthInSeconds ?? 0
        let response = sendWithEngine(engine, "POST", "/v1/timer/adjust", "{\"seconds\":60}")
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(engine.activeTimerItem?.lengthInSeconds, initialLength + 60)
    }

    func testTimerRemainingWithInputParsing() {
        let engine = CueEngine()
        engine.importFlow(
            title: "Test",
            items: [
                PCOTimerItem(title: "A", itemType: "item", sequence: 1, lengthInSeconds: 300),
            ]
        )
        let initialLength = engine.activeTimerItem?.lengthInSeconds ?? 0
        let response = sendWithEngine(engine, "PUT", "/v1/timer/remaining", "{\"input\":\"+30s\"}")
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(engine.activeTimerItem?.lengthInSeconds, initialLength + 30)
    }

    func testTimerRemainingWithGarbageInputReturns400() {
        let engine = CueEngine()
        engine.importFlow(
            title: "Test",
            items: [
                PCOTimerItem(title: "A", itemType: "item", sequence: 1, lengthInSeconds: 300),
            ]
        )
        let response = sendWithEngine(engine, "PUT", "/v1/timer/remaining", "{\"input\":\"garbage\"}")
        XCTAssertEqual(response.status, 400)
    }

    func testTimerPauseSetsIsRunningFalse() {
        let engine = CueEngine()
        engine.importFlow(
            title: "Test",
            items: [
                PCOTimerItem(title: "A", itemType: "item", sequence: 1, lengthInSeconds: 300),
            ]
        )
        let response = sendWithEngine(engine, "POST", "/v1/timer/pause", nil)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(engine.activeTimerItem?.isRunning, false)
    }

    func testTimerStartSetsIsRunningTrue() {
        let engine = CueEngine()
        engine.importFlow(
            title: "Test",
            items: [
                PCOTimerItem(title: "A", itemType: "item", sequence: 1, lengthInSeconds: 300),
            ]
        )
        engine.activeTimerItem?.isRunning = false

        let response = sendWithEngine(engine, "POST", "/v1/timer/start", nil)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(engine.activeTimerItem?.isRunning, true)
    }

    func testTimerStartTwiceKeepsItTrue() {
        let engine = CueEngine()
        engine.importFlow(
            title: "Test",
            items: [
                PCOTimerItem(title: "A", itemType: "item", sequence: 1, lengthInSeconds: 300),
            ]
        )
        engine.activeTimerItem?.isRunning = false

        sendWithEngine(engine, "POST", "/v1/timer/start", nil)
        XCTAssertEqual(engine.activeTimerItem?.isRunning, true)

        let response = sendWithEngine(engine, "POST", "/v1/timer/start", nil)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(engine.activeTimerItem?.isRunning, true)
    }

    func testTimerAdjustWithNoPlanReturns409() {
        let response = send("POST", "/v1/timer/adjust", "{\"seconds\":60}")
        XCTAssertEqual(response.status, 409)
    }

    func testPlanNextAdvancesActiveItemIndex() {
        let engine = CueEngine()
        engine.importFlow(
            title: "Test",
            items: [
                PCOTimerItem(title: "A", itemType: "item", sequence: 1, lengthInSeconds: 300),
                PCOTimerItem(title: "B", itemType: "item", sequence: 2, lengthInSeconds: 600),
            ]
        )
        let initialIndex = engine.activeItemIndex
        let response = sendWithEngine(engine, "POST", "/v1/plan/next", nil)
        XCTAssertEqual(response.status, 200)
        XCTAssertGreaterThan(engine.activeItemIndex, initialIndex)
    }

    func testPlanImportReturns201AndLoadsItems() {
        let engine = CueEngine()
        let json = "{\"text\":\"Welcome | Item | 2:00\\nSong | Song | 4:30\"}"
        let response = sendWithEngine(engine, "POST", "/v1/plan/import", json)
        XCTAssertEqual(response.status, 201)
        XCTAssertEqual(engine.planItems.count, 2)
    }

    func testMessagesPostAppends() {
        let engine = CueEngine()
        let response = sendWithEngine(engine, "POST", "/v1/messages", "{\"text\":\"stand by\"}")
        XCTAssertEqual(response.status, 201)
        XCTAssertEqual(engine.recentMessages.count, 1)
        XCTAssertEqual(engine.recentMessages.first?.text, "stand by")
    }

    func testMessagesDeleteClears() {
        let engine = CueEngine()
        engine.sendMessage("stand by")
        XCTAssertGreaterThan(engine.recentMessages.count, 0)

        let response = sendWithEngine(engine, "DELETE", "/v1/messages", nil)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(engine.recentMessages.count, 0)
    }

    func testDismissClearsTheNotificationAndKeepsEveryMessage() {
        let engine = CueEngine()
        engine.sendMessage("Two minutes to the video", targetRoleId: nil, senderRoleId: nil)

        let response = sendWithEngine(engine, "POST", "/v1/messages/dismiss")
        XCTAssertEqual(response.status, 200)
        XCTAssertNotNil(engine.notificationsClearedAt)
        XCTAssertEqual(engine.recentMessages.count, 1, "the thread is not what was cleared")
        XCTAssertNil(engine.activeNotification(forRoleId: nil))

        let body = decodeJSON(response.body)
        XCTAssertNotNil(body?["notificationsClearedAt"], "a client has to be able to see where the line sits")
    }

    func testAMessageAfterTheDismissNotifiesAgain() {
        let engine = CueEngine()
        engine.sendMessage("Old news", targetRoleId: nil, senderRoleId: nil)
        _ = sendWithEngine(engine, "POST", "/v1/messages/dismiss")
        XCTAssertNil(engine.activeNotification(forRoleId: nil))

        Thread.sleep(forTimeInterval: 1.1)
        engine.sendMessage("Stand by", targetRoleId: nil, senderRoleId: nil)

        XCTAssertEqual(engine.activeNotification(forRoleId: nil)?.text, "Stand by")
    }

    func testClearingHistoryAlsoDropsTheClearedMark() {
        let engine = CueEngine()
        engine.sendMessage("Anything", targetRoleId: nil, senderRoleId: nil)
        _ = sendWithEngine(engine, "POST", "/v1/messages/dismiss")
        XCTAssertNotNil(engine.notificationsClearedAt)

        _ = sendWithEngine(engine, "DELETE", "/v1/messages")
        XCTAssertNil(engine.notificationsClearedAt, "nothing left to have acknowledged")
    }

    func testDismissOnlyTakesAWrite() {
        XCTAssertEqual(send("GET", "/v1/messages/dismiss").status, 405)
    }

    func testUnknownPathReturns404() {
        let response = send("GET", "/v1/nope")
        XCTAssertEqual(response.status, 404)
    }

    func testPathOutsideV1Returns404() {
        let response = send("GET", "/nope")
        XCTAssertEqual(response.status, 404)
    }

    func testMalformedJSONReturns400() {
        let response = send("POST", "/v1/cues/selected", "{invalid json")
        XCTAssertEqual(response.status, 400)
    }

    func testHandleCommandWithValidOp() {
        let engine = CueEngine()
        let router = ControlAPIRouter(engine: engine)

        let commandJSON = "{\"id\":\"1\",\"op\":\"cues.clear\"}"
        guard let data = commandJSON.data(using: .utf8),
              let command = try? JSONDecoder().decode(ControlAPICommand.self, from: data)
        else {
            XCTFail("Could not decode command")
            return
        }

        let reply = router.handleCommand(command)
        XCTAssertEqual(reply.status, 200)
        XCTAssertEqual(reply.id, "1")
    }

    func testCueForSelectedRolesReturns409WhenSelectionMatchesNoRole() {
        let engine = CueEngine()
        let router = ControlAPIRouter(engine: engine)
        engine.roles = [RoleCue(id: "host", name: "Host")]
        engine.selectedRoleIds = ["default"]

        let request = HTTPRequest(method: "POST", path: "/v1/cues/selected", body: Data(#"{"state":"GO"}"#.utf8))
        let response = router.handle(request)

        XCTAssertEqual(response.status, 409)
        XCTAssertEqual(engine.roles.first?.state, .off)
    }

    func testStateIncludesWaypointsAndSchedulesKeysWithEntries() {
        let engine = CueEngine()
        _ = engine.addWaypoint(name: "Song 1")
        _ = engine.addServiceSchedule(title: "Sunday", startsAt: Date().addingTimeInterval(3600))

        let response = sendWithEngine(engine, "GET", "/v1/state")
        XCTAssertEqual(response.status, 200)

        guard let json = decodeJSON(response.body),
              let waypoints = json["waypoints"] as? [[String: Any]],
              let schedules = json["schedules"] as? [String: Any],
              let entries = schedules["entries"] as? [[String: Any]] else {
            XCTFail("Expected waypoints array and schedules.entries in state")
            return
        }
        XCTAssertEqual(waypoints.count, 1)
        XCTAssertEqual(entries.count, 1)
        XCTAssertNotNil(schedules["nextId"])
    }

    func testCreateWaypointReturns201WithIdNameSlug() {
        let response = send("POST", "/v1/waypoints", #"{"name":"Song 1"}"#)
        XCTAssertEqual(response.status, 201)
        guard let json = decodeJSON(response.body) else {
            XCTFail("Response body is not valid JSON")
            return
        }
        XCTAssertNotNil(json["id"])
        XCTAssertEqual(json["name"] as? String, "Song 1")
        XCTAssertEqual(json["slug"] as? String, "song-1")
    }

    func testCreateWaypointWithEmptyNameReturns400() {
        XCTAssertEqual(send("POST", "/v1/waypoints", #"{"name":"   "}"#).status, 400)
    }

    func testCreateDuplicateWaypointReturns409() {
        let engine = CueEngine()
        _ = sendWithEngine(engine, "POST", "/v1/waypoints", #"{"name":"Song 1"}"#)
        let response = sendWithEngine(engine, "POST", "/v1/waypoints", #"{"name":"song 1"}"#)
        XCTAssertEqual(response.status, 409)
    }

    func testListWaypointsReturnsAllWaypoints() {
        let engine = CueEngine()
        _ = engine.addWaypoint(name: "Song 1")
        _ = engine.addWaypoint(name: "Song 2")
        let response = sendWithEngine(engine, "GET", "/v1/waypoints")
        XCTAssertEqual(response.status, 200)
        guard let json = try? JSONSerialization.jsonObject(with: response.body) as? [[String: Any]] else {
            XCTFail("Expected an array of waypoints")
            return
        }
        XCTAssertEqual(json.count, 2)
    }

    func testGetWaypointByIdNameOrSlugAllResolveToTheSameWaypoint() {
        let engine = CueEngine()
        let waypoint = engine.addWaypoint(name: "Song 1")!
        for ref in [waypoint.id, waypoint.name, waypoint.slug] {
            let response = sendWithEngine(engine, "GET", "/v1/waypoints/\(ref)")
            XCTAssertEqual(response.status, 200, "ref \"\(ref)\" should resolve")
            XCTAssertEqual(decodeJSON(response.body)?["id"] as? String, waypoint.id)
        }
    }

    func testGetUnknownWaypointRefReturns404() {
        XCTAssertEqual(send("GET", "/v1/waypoints/nonexistent").status, 404)
    }

    func testPatchWaypointRenames() {
        let engine = CueEngine()
        let waypoint = engine.addWaypoint(name: "Song 1")!
        let response = sendWithEngine(engine, "PATCH", "/v1/waypoints/\(waypoint.id)", #"{"name":"Opener"}"#)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(decodeJSON(response.body)?["name"] as? String, "Opener")
    }

    func testPatchWaypointWithEmptyNameReturns400() {
        let engine = CueEngine()
        let waypoint = engine.addWaypoint(name: "Song 1")!
        let response = sendWithEngine(engine, "PATCH", "/v1/waypoints/\(waypoint.id)", #"{"name":"   "}"#)
        XCTAssertEqual(response.status, 400)
    }

    func testPatchWaypointRenameCollidingWithAnotherWaypointReturns409() {
        let engine = CueEngine()
        let waypointA = engine.addWaypoint(name: "Song 1")!
        _ = engine.addWaypoint(name: "Song 2")!
        let response = sendWithEngine(engine, "PATCH", "/v1/waypoints/\(waypointA.id)", #"{"name":"song 2"}"#)
        XCTAssertEqual(response.status, 409)
        XCTAssertEqual(engine.waypoint(matching: waypointA.id)?.name, "Song 1")
    }

    func testDeleteWaypointRemovesItAndSubsequentGetReturns404() {
        let engine = CueEngine()
        let waypoint = engine.addWaypoint(name: "Song 1")!
        XCTAssertEqual(sendWithEngine(engine, "DELETE", "/v1/waypoints/\(waypoint.id)").status, 200)
        XCTAssertEqual(sendWithEngine(engine, "GET", "/v1/waypoints/\(waypoint.id)").status, 404)
    }

    func testAssignWaypointWithItemIdReturns200() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let waypoint = engine.addWaypoint(name: "Song 1")!
        let itemId = engine.planItems[0].id

        let response = sendWithEngine(engine, "POST", "/v1/waypoints/\(waypoint.id)/assign", #"{"itemId":"\#(itemId)"}"#)

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(decodeJSON(response.body)?["itemId"] as? String, itemId)
    }

    func testAssignWaypointWithNullItemIdUnassigns() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let waypoint = engine.addWaypoint(name: "Song 1")!
        engine.assignWaypoint(waypoint.id, toItemId: engine.planItems[0].id)

        let response = sendWithEngine(engine, "POST", "/v1/waypoints/\(waypoint.id)/assign", #"{"itemId":null}"#)

        XCTAssertEqual(response.status, 200)
        XCTAssertNil(engine.itemId(forWaypointId: waypoint.id))
    }

    func testAssignWaypointWithAbsentItemIdUnassigns() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let waypoint = engine.addWaypoint(name: "Song 1")!
        engine.assignWaypoint(waypoint.id, toItemId: engine.planItems[0].id)

        let response = sendWithEngine(engine, "POST", "/v1/waypoints/\(waypoint.id)/assign", "{}")

        XCTAssertEqual(response.status, 200)
        XCTAssertNil(engine.itemId(forWaypointId: waypoint.id))
    }

    func testAssignUnknownWaypointReturns404() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let itemId = engine.planItems[0].id
        let response = sendWithEngine(engine, "POST", "/v1/waypoints/nonexistent/assign", #"{"itemId":"\#(itemId)"}"#)
        XCTAssertEqual(response.status, 404)
    }

    func testAssignWaypointWithUnknownItemIdReturns404() {
        let engine = CueEngine()
        let waypoint = engine.addWaypoint(name: "Song 1")!
        let response = sendWithEngine(engine, "POST", "/v1/waypoints/\(waypoint.id)/assign", #"{"itemId":"nonexistent-item"}"#)
        XCTAssertEqual(response.status, 404)
    }

    func testFireWaypointAssignedReturns200WithWaypointedItemActive() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        engine.addPlanItem(title: "Song B", itemType: "Song", lengthInSeconds: 200)
        let waypoint = engine.addWaypoint(name: "Song 2")!
        let songBId = engine.planItems[1].id
        engine.assignWaypoint(waypoint.id, toItemId: songBId)

        let response = sendWithEngine(engine, "POST", "/v1/waypoints/\(waypoint.slug)/go")

        XCTAssertEqual(response.status, 200)
        guard let json = decodeJSON(response.body),
              let timer = json["timer"] as? [String: Any],
              let item = timer["item"] as? [String: Any] else {
            XCTFail("Expected timer.item in the snapshot")
            return
        }
        XCTAssertEqual(item["id"] as? String, songBId)
    }

    func testFireWaypointWithCompletelyEmptyBodyStillReturns200() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let waypoint = engine.addWaypoint(name: "Song 1")!
        engine.assignWaypoint(waypoint.id, toItemId: engine.planItems[0].id)

        let router = ControlAPIRouter(engine: engine)
        let request = HTTPRequest(method: "POST", path: "/v1/waypoints/\(waypoint.slug)/go", body: Data())
        let response = router.handle(request)

        XCTAssertEqual(response.status, 200)
    }

    func testFireWaypointWithStartTimerTrueShowsTimerRunningInSnapshot() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let waypoint = engine.addWaypoint(name: "Song 1")!
        engine.assignWaypoint(waypoint.id, toItemId: engine.planItems[0].id)

        let response = sendWithEngine(engine, "POST", "/v1/waypoints/\(waypoint.slug)/go", #"{"startTimer":true}"#)

        XCTAssertEqual(response.status, 200)
        guard let json = decodeJSON(response.body), let timer = json["timer"] as? [String: Any] else {
            XCTFail("Expected timer in the snapshot")
            return
        }
        XCTAssertEqual(timer["isRunning"] as? Bool, true)
    }

    func testFireUnknownWaypointReturns404() {
        XCTAssertEqual(send("POST", "/v1/waypoints/nonexistent/go").status, 404)
    }

    func testFireKnownButUnassignedWaypointReturns409DistinctFrom404() {
        let engine = CueEngine()
        let waypoint = engine.addWaypoint(name: "Song 3")!

        let response = sendWithEngine(engine, "POST", "/v1/waypoints/\(waypoint.slug)/go")

        XCTAssertEqual(response.status, 409)
        let json = decodeJSON(response.body)
        let message = "\(json?["error"] as? String ?? "") \(json?["detail"] as? String ?? "")"
        XCTAssertFalse(message.localizedCaseInsensitiveContains("unknown"))
    }

    func testFireWaypointWithSpaceInPathResolves() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let waypoint = engine.addWaypoint(name: "Song 1")!
        engine.assignWaypoint(waypoint.id, toItemId: engine.planItems[0].id)

        let router = ControlAPIRouter(engine: engine)
        let request = HTTPRequest(method: "POST", path: "/v1/waypoints/song 1/go", body: Data())
        let response = router.handle(request)

        XCTAssertEqual(response.status, 200)
    }

    func testSetPlanItemWaypointsSetsTheList() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let itemId = engine.planItems[0].id
        let waypointOne = engine.addWaypoint(name: "Song 1")!
        let waypointTwo = engine.addWaypoint(name: "Song 2")!

        let response = sendWithEngine(
            engine, "POST", "/v1/plan/items/\(itemId)/waypoints",
            #"{"waypoints":["\#(waypointOne.slug)","\#(waypointTwo.slug)"]}"#
        )

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(Set(engine.planItems[0].waypointIds), Set([waypointOne.id, waypointTwo.id]))
    }

    func testSetPlanItemWaypointsWithUnresolvableWaypointReturns404NamingIt() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let itemId = engine.planItems[0].id

        let response = sendWithEngine(engine, "POST", "/v1/plan/items/\(itemId)/waypoints", #"{"waypoints":["no-such-waypoint"]}"#)

        XCTAssertEqual(response.status, 404)
        XCTAssertEqual(decodeJSON(response.body)?["detail"] as? String, "no-such-waypoint")
    }

    func testSetPlanItemWaypointsWithUnknownItemReturns404() {
        XCTAssertEqual(send("POST", "/v1/plan/items/nonexistent/waypoints", #"{"waypoints":[]}"#).status, 404)
    }

    func testCreateScheduleReturns201WithISODatesAndGoLiveAt() {
        let response = send(
            "POST", "/v1/schedules",
            #"{"title":"Sunday 10am","startsAt":"2026-10-04T10:00:00Z","goLiveOffsetMinutes":15}"#
        )
        XCTAssertEqual(response.status, 201)
        guard let json = decodeJSON(response.body) else {
            XCTFail("Response body is not valid JSON")
            return
        }
        XCTAssertEqual(json["startsAt"] as? String, "2026-10-04T10:00:00Z")
        XCTAssertEqual(json["goLiveAt"] as? String, "2026-10-04T09:45:00Z")
        XCTAssertEqual(json["goLiveOffsetSeconds"] as? Int, 900)
    }

    func testCreateScheduleGoLiveOffsetMinutesWinsOverSeconds() {
        let response = send(
            "POST", "/v1/schedules",
            #"{"title":"Sunday","startsAt":"2026-10-04T10:00:00Z","goLiveOffsetMinutes":10,"goLiveOffsetSeconds":99999}"#
        )
        XCTAssertEqual(response.status, 201)
        XCTAssertEqual(decodeJSON(response.body)?["goLiveOffsetSeconds"] as? Int, 600)
    }

    func testCreateScheduleWithUnknownRecurrenceReturns400() {
        let response = send(
            "POST", "/v1/schedules",
            #"{"title":"Sunday","startsAt":"2026-10-04T10:00:00Z","recurrence":"biweekly"}"#
        )
        XCTAssertEqual(response.status, 400)
    }

    func testCreateScheduleWithEmptyTitleReturns400() {
        let response = send("POST", "/v1/schedules", #"{"title":"   ","startsAt":"2026-10-04T10:00:00Z"}"#)
        XCTAssertEqual(response.status, 400)
    }

    func testListSchedulesReturnsAllEntries() {
        let engine = CueEngine()
        _ = engine.addServiceSchedule(title: "A", startsAt: Date())
        _ = engine.addServiceSchedule(title: "B", startsAt: Date().addingTimeInterval(100))

        let response = sendWithEngine(engine, "GET", "/v1/schedules")

        XCTAssertEqual(response.status, 200)
        guard let json = decodeJSON(response.body), let entries = json["entries"] as? [[String: Any]] else {
            XCTFail("Expected an entries array")
            return
        }
        XCTAssertEqual(entries.count, 2)
    }

    func testGetPatchDeleteScheduleById() {
        let engine = CueEngine()
        let schedule = engine.addServiceSchedule(title: "Sunday", startsAt: Date())!

        XCTAssertEqual(sendWithEngine(engine, "GET", "/v1/schedules/\(schedule.id)").status, 200)

        let patchResponse = sendWithEngine(engine, "PATCH", "/v1/schedules/\(schedule.id)", #"{"title":"Sunday AM"}"#)
        XCTAssertEqual(patchResponse.status, 200)
        XCTAssertEqual(decodeJSON(patchResponse.body)?["title"] as? String, "Sunday AM")

        XCTAssertEqual(sendWithEngine(engine, "DELETE", "/v1/schedules/\(schedule.id)").status, 200)
        XCTAssertEqual(sendWithEngine(engine, "GET", "/v1/schedules/\(schedule.id)").status, 404)
    }

    func testScheduleRoutesWithUnknownIdReturn404() {
        XCTAssertEqual(send("GET", "/v1/schedules/nonexistent").status, 404)
        XCTAssertEqual(send("PATCH", "/v1/schedules/nonexistent", #"{"title":"X"}"#).status, 404)
        XCTAssertEqual(send("DELETE", "/v1/schedules/nonexistent").status, 404)
    }

    func testGoLiveScheduleNowReturns202() {
        let engine = CueEngine()
        let schedule = engine.addServiceSchedule(title: "Sunday", startsAt: Date())!
        let response = sendWithEngine(engine, "POST", "/v1/schedules/\(schedule.id)/go-live")
        XCTAssertEqual(response.status, 202)
    }

    func testGoLiveScheduleUnknownIdReturns404() {
        XCTAssertEqual(send("POST", "/v1/schedules/nonexistent/go-live").status, 404)
    }

    func testHandleCommandWaypointsGoReachesSameRouteAndReturns200() {
        let engine = CueEngine()
        let router = ControlAPIRouter(engine: engine)
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let waypoint = engine.addWaypoint(name: "Song 1")!
        engine.assignWaypoint(waypoint.id, toItemId: engine.planItems[0].id)

        guard let data = #"{"id":"1","op":"waypoints.song-1.go"}"#.data(using: .utf8),
              let command = try? JSONDecoder().decode(ControlAPICommand.self, from: data) else {
            XCTFail("Could not decode command")
            return
        }

        let reply = router.handleCommand(command)
        XCTAssertEqual(reply.status, 200)
    }

    func testHandleCommandWaypointsGoUnassignedReturns409() {
        let engine = CueEngine()
        let router = ControlAPIRouter(engine: engine)
        _ = engine.addWaypoint(name: "Song 1")

        guard let data = #"{"id":"1","op":"waypoints.song-1.go"}"#.data(using: .utf8),
              let command = try? JSONDecoder().decode(ControlAPICommand.self, from: data) else {
            XCTFail("Could not decode command")
            return
        }

        let reply = router.handleCommand(command)
        XCTAssertEqual(reply.status, 409)
        XCTAssertNotNil(reply.error)
    }
}
