// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

@MainActor
final class WaypointTests: XCTestCase {
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

    func testSlugLowercasesAndDashesSpaces() {
        XCTAssertEqual(Waypoint.slug(for: "Song 1"), "song-1")
    }

    func testSlugTreatsUnderscoreAsPunctuation() {
        XCTAssertEqual(Waypoint.slug(for: "SONG_1"), "song-1")
    }

    func testSlugStripsLeadingAndTrailingWhitespaceAndPunctuation() {
        XCTAssertEqual(Waypoint.slug(for: "  ! Song 1 ! "), "song-1")
    }

    func testSlugCollapsesRunsOfPunctuationToOneDash() {
        XCTAssertEqual(Waypoint.slug(for: "Song -- # 1"), "song-1")
    }

    func testSlugOfAllPunctuationNameIsEmpty() {
        XCTAssertEqual(Waypoint.slug(for: "!!!"), "")
        XCTAssertEqual(Waypoint.slug(for: "   "), "")
    }

    func testMatchesAcceptsIdNameSlugAndDifferentFormatting() {
        let waypoint = Waypoint(id: "waypoint-abc123", name: "Song 1")

        XCTAssertTrue(waypoint.matches("waypoint-abc123"))
        XCTAssertTrue(waypoint.matches("Song 1"))
        XCTAssertTrue(waypoint.matches("song 1"))
        XCTAssertTrue(waypoint.matches("song-1"))
        XCTAssertTrue(waypoint.matches("SONG_1"))
    }

    func testMatchesRejectsUnrelatedString() {
        let waypoint = Waypoint(id: "waypoint-abc123", name: "Song 1")
        XCTAssertFalse(waypoint.matches("Sermon"))
    }

    func testMatchesGuardsAgainstEmptySlugMatchingAnything() {
        let waypoint = Waypoint(id: "waypoint-xyz", name: "!!!")
        XCTAssertEqual(waypoint.slug, "")
        XCTAssertFalse(waypoint.matches("###"))
        XCTAssertFalse(waypoint.matches(""))
    }

    func testAddWaypointTrimsAppendsAndReturnsTheWaypoint() {
        let engine = CueEngine()
        let waypoint = engine.addWaypoint(name: "  Song 1  ")
        XCTAssertEqual(waypoint?.name, "Song 1")
        XCTAssertEqual(engine.waypoints.map(\.id), [waypoint?.id].compactMap { $0 })
    }

    func testAddWaypointRejectsEmptyOrWhitespaceName() {
        let engine = CueEngine()
        XCTAssertNil(engine.addWaypoint(name: ""))
        XCTAssertNil(engine.addWaypoint(name: "   "))
        XCTAssertEqual(engine.waypoints.count, 0)
    }

    func testAddWaypointRejectsSlugCollision() {
        let engine = CueEngine()
        XCTAssertNotNil(engine.addWaypoint(name: "Song 1"))
        XCTAssertNil(engine.addWaypoint(name: "song 1"))
        XCTAssertEqual(engine.waypoints.count, 1)
    }

    func testRenameWaypointChangesNameKeepsId() {
        let engine = CueEngine()
        let waypoint = engine.addWaypoint(name: "Song 1")!
        engine.renameWaypoint(id: waypoint.id, name: "Opener")
        XCTAssertEqual(engine.waypoints.first?.id, waypoint.id)
        XCTAssertEqual(engine.waypoints.first?.name, "Opener")
    }

    func testRenameWaypointIsNoOpOnEmptyName() {
        let engine = CueEngine()
        let waypoint = engine.addWaypoint(name: "Song 1")!
        engine.renameWaypoint(id: waypoint.id, name: "   ")
        XCTAssertEqual(engine.waypoints.first?.name, "Song 1")
    }

    func testRenameWaypointIsNoOpOnCollisionWithADifferentWaypoint() {
        let engine = CueEngine()
        let waypointA = engine.addWaypoint(name: "Song 1")!
        _ = engine.addWaypoint(name: "Song 2")!
        engine.renameWaypoint(id: waypointA.id, name: "song 2")
        XCTAssertEqual(engine.waypoint(matching: waypointA.id)?.name, "Song 1")
    }

    func testRenameWaypointAllowsRecasingItsOwnName() {
        let engine = CueEngine()
        let waypoint = engine.addWaypoint(name: "Song 1")!
        engine.renameWaypoint(id: waypoint.id, name: "SONG 1")
        XCTAssertEqual(engine.waypoint(matching: waypoint.id)?.name, "SONG 1")
    }

    func testRemoveWaypointDropsFromLibraryAndStripsFromEveryItem() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        engine.addPlanItem(title: "Song B", itemType: "Song", lengthInSeconds: 200)
        let waypoint = engine.addWaypoint(name: "Song 1")!
        let itemId = engine.planItems[0].id
        engine.assignWaypoint(waypoint.id, toItemId: itemId)
        XCTAssertTrue(engine.planItems[0].waypointIds.contains(waypoint.id))

        engine.removeWaypoint(id: waypoint.id)

        XCTAssertFalse(engine.waypoints.contains { $0.id == waypoint.id })
        XCTAssertTrue(engine.planItems.allSatisfy { !$0.waypointIds.contains(waypoint.id) })
    }

    func testAssignWaypointIsExclusiveAcrossItems() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        engine.addPlanItem(title: "Song B", itemType: "Song", lengthInSeconds: 200)
        let waypoint = engine.addWaypoint(name: "Song 1")!
        let itemA = engine.planItems[0].id
        let itemB = engine.planItems[1].id

        engine.assignWaypoint(waypoint.id, toItemId: itemA)
        XCTAssertTrue(engine.planItems.first(where: { $0.id == itemA })!.waypointIds.contains(waypoint.id))

        engine.assignWaypoint(waypoint.id, toItemId: itemB)
        XCTAssertFalse(engine.planItems.first(where: { $0.id == itemA })!.waypointIds.contains(waypoint.id))
        XCTAssertTrue(engine.planItems.first(where: { $0.id == itemB })!.waypointIds.contains(waypoint.id))
    }

    func testAssignWaypointWithNilUnassigns() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let waypoint = engine.addWaypoint(name: "Song 1")!
        let itemId = engine.planItems[0].id

        engine.assignWaypoint(waypoint.id, toItemId: itemId)
        XCTAssertTrue(engine.planItems[0].waypointIds.contains(waypoint.id))

        engine.assignWaypoint(waypoint.id, toItemId: nil)
        XCTAssertFalse(engine.planItems[0].waypointIds.contains(waypoint.id))
    }

    func testAssignWaypointWithUnknownWaypointIdIsNoOp() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let itemId = engine.planItems[0].id

        engine.assignWaypoint("not-a-real-waypoint-id", toItemId: itemId)

        XCTAssertTrue(engine.planItems[0].waypointIds.isEmpty)
    }

    func testSetWaypointIdsDedupesIgnoresUnknownAndStealsFromOtherItem() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        engine.addPlanItem(title: "Song B", itemType: "Song", lengthInSeconds: 200)
        let waypointOne = engine.addWaypoint(name: "Song 1")!
        let waypointTwo = engine.addWaypoint(name: "Song 2")!
        let itemA = engine.planItems[0].id
        let itemB = engine.planItems[1].id

        engine.assignWaypoint(waypointOne.id, toItemId: itemA)
        XCTAssertTrue(engine.planItems.first(where: { $0.id == itemA })!.waypointIds.contains(waypointOne.id))

        engine.setWaypointIds([waypointOne.id, waypointOne.id, "bogus-id", waypointTwo.id], forItemId: itemB)

        XCTAssertEqual(engine.planItems.first(where: { $0.id == itemB })!.waypointIds, [waypointOne.id, waypointTwo.id])
        XCTAssertFalse(engine.planItems.first(where: { $0.id == itemA })!.waypointIds.contains(waypointOne.id))
    }

    func testWaypointsForItemIdReturnsLibraryOrderNotAssignmentOrder() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let waypointOne = engine.addWaypoint(name: "Song 1")!
        let waypointTwo = engine.addWaypoint(name: "Song 2")!
        let itemId = engine.planItems[0].id

        engine.assignWaypoint(waypointTwo.id, toItemId: itemId)
        engine.assignWaypoint(waypointOne.id, toItemId: itemId)

        XCTAssertEqual(engine.waypoints(forItemId: itemId).map(\.id), [waypointOne.id, waypointTwo.id])
    }

    func testPCOTimerItemWithWaypointIdsRoundTripsThroughCodable() {
        let item = PCOTimerItem(title: "Song", waypointIds: ["waypoint-1", "waypoint-2"])
        let data = try! JSONEncoder().encode(item)
        let decoded = try! JSONDecoder().decode(PCOTimerItem.self, from: data)
        XCTAssertEqual(decoded.waypointIds, ["waypoint-1", "waypoint-2"])
        XCTAssertEqual(decoded, item)
    }

    func testPCOTimerItemJSONWithoutWaypointIdsKeyDecodesWithEmptyArray() {
        let json = """
        {
            "id": "item-1",
            "title": "Old Item",
            "itemType": "Song",
            "sequence": 1,
            "lengthInSeconds": 300,
            "elapsedSeconds": 0,
            "isRunning": false
        }
        """
        let decoded = try! JSONDecoder().decode(PCOTimerItem.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.waypointIds, [])
        XCTAssertEqual(decoded.id, "item-1")
    }

    func testPlanItemDecodesLegacyTagIdsKeyIntoWaypointIds() {
        let json = """
        {
            "id": "item-1",
            "title": "Great Are You Lord",
            "itemType": "Song",
            "sequence": 1,
            "lengthInSeconds": 300,
            "elapsedSeconds": 0,
            "isRunning": false,
            "tagIds": ["wp-song-1", "wp-opener"]
        }
        """
        let decoded = try! JSONDecoder().decode(PCOTimerItem.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.waypointIds, ["wp-song-1", "wp-opener"])
    }

    func testPlanItemPrefersWaypointIdsOverLegacyTagIds() {
        let json = """
        {
            "id": "item-1",
            "title": "Song",
            "itemType": "Song",
            "sequence": 1,
            "lengthInSeconds": 300,
            "elapsedSeconds": 0,
            "isRunning": false,
            "tagIds": ["stale"],
            "waypointIds": ["current"]
        }
        """
        let decoded = try! JSONDecoder().decode(PCOTimerItem.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.waypointIds, ["current"])
    }

    func testLibraryMigratesFromLegacyServiceTagsDefaultsKey() {
        let legacy = [Waypoint(id: "wp-1", name: "song1"), Waypoint(id: "wp-2", name: "doors")]
        UserDefaults.standard.set(try! JSONEncoder().encode(legacy), forKey: "serviceTags")
        UserDefaults.standard.removeObject(forKey: "waypoints")

        let engine = CueEngine()

        XCTAssertEqual(engine.waypoints.map(\.name), ["song1", "doors"])
        XCTAssertNotNil(UserDefaults.standard.data(forKey: "waypoints"))
        XCTAssertNil(UserDefaults.standard.data(forKey: "serviceTags"))
    }

    func testCurrentLibraryWinsOverLegacyKey() {
        let current = [Waypoint(id: "wp-new", name: "current")]
        let legacy = [Waypoint(id: "wp-old", name: "legacy")]
        UserDefaults.standard.set(try! JSONEncoder().encode(current), forKey: "waypoints")
        UserDefaults.standard.set(try! JSONEncoder().encode(legacy), forKey: "serviceTags")

        let engine = CueEngine()

        XCTAssertEqual(engine.waypoints.map(\.name), ["current"])
    }

    func testFireWaypointOnAssignedWaypointMovesActiveItem() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        engine.addPlanItem(title: "Song B", itemType: "Song", lengthInSeconds: 200)
        let waypoint = engine.addWaypoint(name: "Song 2")!
        let songBId = engine.planItems[1].id
        engine.assignWaypoint(waypoint.id, toItemId: songBId)

        let result = engine.fireWaypoint("Song 2")

        XCTAssertEqual(result, .fired(itemId: songBId))
        XCTAssertEqual(engine.activeItemIndex, 1)
        XCTAssertEqual(engine.activeTimerItem?.id, songBId)
    }

    func testFireWaypointUnknownNameReturnsUnknownWaypoint() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        XCTAssertEqual(engine.fireWaypoint("no-such-waypoint"), .unknownWaypoint)
    }

    func testFireWaypointKnownButUnassignedReturnsUnassigned() {
        let engine = CueEngine()
        let waypoint = engine.addWaypoint(name: "Song 3")!
        XCTAssertEqual(engine.fireWaypoint("Song 3"), .unassigned(waypointId: waypoint.id))
    }

    func testFireWaypointWithStartTimerLeavesItemRunning() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let waypoint = engine.addWaypoint(name: "Song 1")!
        engine.assignWaypoint(waypoint.id, toItemId: engine.planItems[0].id)

        _ = engine.fireWaypoint("Song 1", startTimer: true)

        XCTAssertEqual(engine.activeTimerItem?.isRunning, true)
    }

    func testFireWaypointTwiceWithStartTimerDoesNotToggleToPaused() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let waypoint = engine.addWaypoint(name: "Song 1")!
        engine.assignWaypoint(waypoint.id, toItemId: engine.planItems[0].id)

        _ = engine.fireWaypoint("Song 1", startTimer: true)
        XCTAssertEqual(engine.activeTimerItem?.isRunning, true)
        _ = engine.fireWaypoint("Song 1", startTimer: true)
        XCTAssertEqual(engine.activeTimerItem?.isRunning, true)
    }

    func testFiringAWaypointOnAHeaderResolvesToTheNearestRealItem() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Host Moment", itemType: "Header", lengthInSeconds: 0)
        engine.addPlanItem(title: "HOST // Welcome", itemType: "Item", lengthInSeconds: 120)
        let header = engine.planItems[0]
        let realItem = engine.planItems[1]
        let waypoint = engine.addWaypoint(name: "Host Pre")!
        engine.assignWaypoint(waypoint.id, toItemId: header.id)

        let result = engine.fireWaypoint("Host Pre")

        XCTAssertEqual(result, .fired(itemId: header.id), "the result reports the assigned id…")
        XCTAssertEqual(engine.activeTimerItem?.id, realItem.id, "…but the playhead lands on the real item")
    }

    func testFireWaypointDefaultsToStartingTheTimer() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let waypoint = engine.addWaypoint(name: "Song 1")!
        engine.assignWaypoint(waypoint.id, toItemId: engine.planItems[0].id)

        _ = engine.fireWaypoint("Song 1")

        XCTAssertEqual(engine.activeTimerItem?.isRunning, true)
    }

    func testFireWaypointWithStartTimerFalseLeavesItemPaused() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let waypoint = engine.addWaypoint(name: "Song 1")!
        engine.assignWaypoint(waypoint.id, toItemId: engine.planItems[0].id)

        _ = engine.fireWaypoint("Song 1", startTimer: false)

        XCTAssertEqual(engine.activeTimerItem?.id, engine.planItems[0].id)
        XCTAssertEqual(engine.activeTimerItem?.isRunning, false)
    }

    func testAPIFireWithNoBodyStartsTheTimer() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let waypoint = engine.addWaypoint(name: "Song 1")!
        engine.assignWaypoint(waypoint.id, toItemId: engine.planItems[0].id)
        let router = ControlAPIRouter(engine: engine)

        let response = router.handle(HTTPRequest(method: "POST", path: "/v1/waypoints/song-1/go"))

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(engine.activeTimerItem?.isRunning, true)
    }

    func testAPIFireWithStartTimerFalseLeavesItemPaused() {
        let engine = CueEngine()
        engine.addPlanItem(title: "Song A", itemType: "Song", lengthInSeconds: 200)
        let waypoint = engine.addWaypoint(name: "Song 1")!
        engine.assignWaypoint(waypoint.id, toItemId: engine.planItems[0].id)
        let router = ControlAPIRouter(engine: engine)

        let response = router.handle(HTTPRequest(
            method: "POST",
            path: "/v1/waypoints/song-1/go",
            body: Data(#"{"startTimer":false}"#.utf8)
        ))

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(engine.activeTimerItem?.isRunning, false)
    }
}
