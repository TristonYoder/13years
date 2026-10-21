// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

private func decodeRole(_ json: String) throws -> RoleCue {
    try JSONDecoder().decode(RoleCue.self, from: Data(json.utf8))
}

private func encodedObject(_ role: RoleCue) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(role)) as? [String: Any])
}

final class RolePagerItemTests: XCTestCase {
    func testTokensRoundTrip() {
        XCTAssertEqual(RolePagerItem.field(.key).token, "field:key")
        XCTAssertEqual(RolePagerItem.note("Audio").token, "note:Audio")
        XCTAssertEqual(RolePagerItem(token: "field:leader"), .field(.leader))
        XCTAssertEqual(RolePagerItem(token: "note:Stage: Left"), .note("Stage: Left"))
        XCTAssertNil(RolePagerItem(token: "field:nope"))
        XCTAssertNil(RolePagerItem(token: "note:"))
        XCTAssertNil(RolePagerItem(token: "key"))
    }

    func testDecodeTolerantDropsUnknownAndDuplicates() {
        XCTAssertEqual(
            RolePagerItem.decodeTolerant(["note:B", "field:key", "bogus", "note:B", "field:zzz", "note:A"]),
            [.note("B"), .field(.key), .note("A")]
        )
    }

    func testListOperations() {
        let list: [RolePagerItem] = [.field(.key), .note("A"), .field(.bpm)]
        XCTAssertEqual(RolePagerItem.inserting(.note("B"), into: list), [.field(.key), .note("A"), .field(.bpm), .note("B")])
        XCTAssertEqual(RolePagerItem.inserting(.note("B"), into: list, at: 1), [.field(.key), .note("B"), .note("A"), .field(.bpm)])
        XCTAssertEqual(RolePagerItem.inserting(.field(.key), into: list, at: 3), [.note("A"), .field(.bpm), .field(.key)])
        XCTAssertEqual(RolePagerItem.moving(.field(.bpm), in: list, toIndex: 0), [.field(.bpm), .field(.key), .note("A")])
        XCTAssertEqual(RolePagerItem.moving(.note("Zed"), in: list, toIndex: 0), list)
        XCTAssertEqual(RolePagerItem.removing(.note("A"), from: list), [.field(.key), .field(.bpm)])
        XCTAssertEqual(RolePagerItem.inserting(.note("Q"), into: list, at: 99).last, .note("Q"))
    }

    func testDroppingMovesWithinAListAndCopiesAcrossLists() {
        let list: [RolePagerItem] = [.field(.key), .note("A"), .field(.bpm)]
        XCTAssertEqual(RolePagerItem.dropping(.field(.key), into: list, before: 3), [.note("A"), .field(.bpm), .field(.key)])
        XCTAssertEqual(RolePagerItem.dropping(.field(.key), into: list, before: 1), list)
        XCTAssertEqual(RolePagerItem.dropping(.field(.bpm), into: list, before: 0), [.field(.bpm), .field(.key), .note("A")])
        XCTAssertEqual(RolePagerItem.dropping(.note("B"), into: list, before: nil), list + [.note("B")])
        XCTAssertEqual(RolePagerItem.dropping(.note("B"), into: [], before: 4), [.note("B")])
        XCTAssertEqual(RolePagerItem.shifting(.note("A"), in: list, by: 1), [.field(.key), .field(.bpm), .note("A")])
        XCTAssertEqual(RolePagerItem.shifting(.field(.key), in: list, by: -1), list)
        XCTAssertEqual(RolePagerItem.shifting(.field(.bpm), in: list, by: 5), list)
    }
}

final class RoleCuePagerItemsTests: XCTestCase {
    func testLegacyKeysDecodeIntoOneOrderedList() throws {
        let role = try decodeRole(#"{"id":"r","name":"Band","state":"OFF","lastUpdated":0,"assignedNoteCategories":["Lights","Audio"],"pagerFields":["sequence","key"]}"#)
        XCTAssertEqual(role.pagerItems, [.field(.sequence), .field(.key), .note("Lights"), .note("Audio")])
        XCTAssertEqual(role.assignedNoteCategories, ["Lights", "Audio"])
        XCTAssertEqual(role.pagerFields, [.sequence, .key])
    }

    func testNoLegacyConfigurationStaysUnset() throws {
        let role = try decodeRole(#"{"id":"r","name":"Band","state":"OFF","lastUpdated":0,"assignedNoteCategories":[]}"#)
        XCTAssertNil(role.pagerItems)
        XCTAssertNil(role.pagerFields)
        let object = try encodedObject(role)
        XCTAssertNil(object["pagerFields"])
        XCTAssertNil(object["pagerItems"])
        XCTAssertEqual(object["assignedNoteCategories"] as? [String], [])
    }

    func testNotesOnlyLegacyRoleKeepsItsCategories() throws {
        let role = try decodeRole(#"{"id":"r","name":"Host","state":"OFF","lastUpdated":0,"assignedNoteCategories":["Host Notes"]}"#)
        XCTAssertEqual(role.assignedNoteCategories, ["Host Notes"])
        XCTAssertEqual(role.pagerItems, [.note("Host Notes")])
    }

    func testPagerItemsWinOverLegacyKeys() throws {
        let json = #"{"id":"r","name":"Band","state":"OFF","lastUpdated":0,"assignedNoteCategories":["Old"],"pagerFields":["key"],"pagerItems":["note:Zeta","field:bpm","note:Alpha","field:nope"]}"#
        let role = try decodeRole(json)
        XCTAssertEqual(role.pagerItems, [.note("Zeta"), .field(.bpm), .note("Alpha")])
        XCTAssertEqual(role.assignedNoteCategories, ["Zeta", "Alpha"])
        XCTAssertEqual(role.pagerFields, [.bpm])
    }

    func testEncodingWritesTheNewListAndBothDerivedLegacyKeys() throws {
        let role = RoleCue(id: "r", name: "Band", pagerItems: [.note("Zeta"), .field(.bpm), .field(.key), .note("Alpha")])
        let object = try encodedObject(role)
        XCTAssertEqual(object["pagerItems"] as? [String], ["note:Zeta", "field:bpm", "field:key", "note:Alpha"])
        XCTAssertEqual(object["assignedNoteCategories"] as? [String], ["Zeta", "Alpha"])
        XCTAssertEqual(object["pagerFields"] as? [String], ["bpm", "key"])
        let decoded = try JSONDecoder().decode(RoleCue.self, from: JSONEncoder().encode(role))
        XCTAssertEqual(decoded, role)
        let api = try ControlAPIJSON.decoder.decode(RoleCue.self, from: ControlAPIJSON.encoder.encode(role))
        XCTAssertEqual(api.pagerItems, role.pagerItems)
    }

    func testAnOlderPagerReadingTheNewJSONStillGetsOrderedLegacyKeys() throws {
        let role = RoleCue(id: "r", name: "Band", pagerItems: [.field(.sequence), .note("B"), .field(.key), .note("A")])
        var object = try encodedObject(role)
        object.removeValue(forKey: "pagerItems")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let old = try JSONDecoder().decode(RoleCue.self, from: stripped)
        XCTAssertEqual(old.assignedNoteCategories, ["B", "A"])
        XCTAssertEqual(old.pagerFields, [.sequence, .key])
    }

    func testMemberwiseInitBuildsTheListFromLegacyArguments() {
        let role = RoleCue(id: "r", name: "Band", assignedNoteCategories: ["B", "A"], pagerFields: [.bpm, .key])
        XCTAssertEqual(role.pagerItems, [.field(.bpm), .field(.key), .note("B"), .note("A")])
        XCTAssertEqual(RoleCue(id: "r", name: "Band").pagerItems, nil)
        XCTAssertEqual(RoleCue(id: "r", name: "Band", pagerFields: []).pagerItems, [])
    }

    func testLegacySettersKeepInterleavedOrder() {
        var role = RoleCue(id: "r", name: "Band", pagerItems: [.note("A"), .field(.key), .note("B"), .field(.bpm)])
        role.assignedNoteCategories = ["C", "A", "D"]
        XCTAssertEqual(role.pagerItems, [.note("C"), .field(.key), .note("A"), .field(.bpm), .note("D")])
        role.pagerFields = [.meter]
        XCTAssertEqual(role.pagerItems, [.note("C"), .field(.meter), .note("A"), .note("D")])
        role.pagerFields = nil
        XCTAssertEqual(role.pagerItems, [.note("C"), .note("A"), .note("D")])
        role.assignedNoteCategories = []
        XCTAssertEqual(role.pagerItems, [])
        var unset = RoleCue(id: "u", name: "U")
        unset.assignedNoteCategories = []
        XCTAssertNil(unset.pagerItems)
    }
}

final class NoteOrderTests: XCTestCase {
    private func state(items: [RolePagerItem], active: PCOTimerItem, next: PCOTimerItem) -> PagerPresentationState {
        PagerPresentationState(
            roles: [RoleCue(id: "audio", name: "Audio", pagerItems: items)],
            planItems: [],
            activeItemIndex: 0,
            activeTimerItem: active,
            recentMessages: [],
            selectedRoleId: "audio",
            isProducerLive: true,
            isLANConnected: true,
            connectedMasterName: nil,
            hourFormatThreshold: .over90Minutes,
            clockFormat: .twentyFourHour,
            receivedNextItem: next
        )
    }

    private let notes = ["Alpha": "a", "Mid": "m", "Zeta": "z", "Beta": "b"]

    func testNativeNotesFollowTheRolesCustomOrder() {
        let active = PCOTimerItem(id: "1", title: "One", notes: notes)
        let next = PCOTimerItem(id: "2", title: "Two", notes: notes)
        let state = state(items: [.note("Zeta"), .field(.key), .note("Alpha"), .note("Mid")], active: active, next: next)
        XCTAssertEqual(state.currentNotes.map(\.category), ["Zeta", "Alpha", "Mid"])
        XCTAssertEqual(state.nextNotes.map(\.category), ["Zeta", "Alpha", "Mid"])
        XCTAssertNotEqual(state.currentNotes.map(\.category), notes.keys.sorted().filter { ["Zeta", "Alpha", "Mid"].contains($0) })
    }

    func testReorderingTheListReordersTheNotes() {
        let active = PCOTimerItem(id: "1", title: "One", notes: notes)
        var items: [RolePagerItem] = [.note("Alpha"), .note("Beta"), .note("Mid")]
        XCTAssertEqual(state(items: items, active: active, next: active).currentNotes.map(\.category), ["Alpha", "Beta", "Mid"])
        items = RolePagerItem.moving(.note("Mid"), in: items, toIndex: 0)
        XCTAssertEqual(state(items: items, active: active, next: active).currentNotes.map(\.category), ["Mid", "Alpha", "Beta"])
    }

    func testEmptyNotesAreSkippedWithoutDisturbingTheOrder() {
        let active = PCOTimerItem(id: "1", title: "One", notes: ["Zeta": "z", "Alpha": ""])
        let state = state(items: [.note("Zeta"), .note("Alpha"), .note("Mid")], active: active, next: active)
        XCTAssertEqual(state.currentNotes.map(\.category), ["Zeta"])
    }
}

@MainActor
final class RolePagerItemsEngineTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clear()
    }

    override func tearDown() {
        clear()
        super.tearDown()
    }

    private func clear() {
        for key in ["persistedFlow", "persistedRoles", "isPCOLiveSyncEnabled", "recentMessages", "waypoints", "serviceTags", "serviceSchedules"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func leaderSong(id: String) -> PCOTimerItem {
        PCOTimerItem(
            id: id,
            title: "Song \(id)",
            itemType: "song",
            lengthInSeconds: 240,
            notes: ["Audio": "Fade", "Lights": "Warm"],
            details: PCOItemDetails(
                keyName: "G",
                leaders: [
                    PCOItemLeader(personId: "p1", name: "Sam Rivera", firstName: "Sam", photoThumbnailURL: "https://example.com/sam-long-photo-thumbnail-path.jpg"),
                    PCOItemLeader(personId: "p2", name: "Pat Lee", firstName: "Pat", photoThumbnailURL: "https://example.com/pat-long-photo-thumbnail-path.jpg"),
                ]
            )
        )
    }

    private func makeProducer(roles: [RoleCue]) -> CueEngine {
        let engine = CueEngine(startsNetworking: false)
        engine.roles = roles
        engine.selectedRoleIds = Set(roles.map(\.id))
        engine.importFlow(title: "Plan", items: [leaderSong(id: "a"), leaderSong(id: "b"), PCOTimerItem(id: "c", title: "Sermon", itemType: "Item", lengthInSeconds: 1800)])
        return engine
    }

    func testSetPagerItemsStoresOrderAndNormalizes() {
        let engine = makeProducer(roles: [RoleCue(id: "band", name: "Band")])
        engine.setPagerItems(forRoleId: "band", [.note("Lights"), .field(.leader), .note("Lights"), .field(.key), .note("Audio")])
        XCTAssertEqual(engine.roles[0].pagerItems, [.note("Lights"), .field(.leader), .field(.key), .note("Audio")])
        XCTAssertEqual(engine.roles[0].assignedNoteCategories, ["Lights", "Audio"])
        XCTAssertEqual(engine.roles[0].pagerFields, [.leader, .key])
        engine.setNoteCategory(forRoleId: "band", category: "Video", isOn: true)
        XCTAssertEqual(engine.roles[0].assignedNoteCategories, ["Lights", "Audio", "Video"])
        engine.setNoteCategory(forRoleId: "band", category: "Lights", isOn: false)
        XCTAssertEqual(engine.roles[0].pagerItems, [.field(.leader), .field(.key), .note("Audio"), .note("Video")])
        engine.setPagerItems(forRoleId: "band", nil)
        XCTAssertNil(engine.roles[0].pagerItems)
    }

    func testLeaderRidesTheWireAsFirstNamesOnlyAndOnlyWhenARoleUsesIt() throws {
        let without = makeProducer(roles: [RoleCue(id: "band", name: "Band", pagerFields: [.key])])
        XCTAssertTrue(without.activeTimerItemForBroadcast?.details?.leaders.isEmpty ?? true)
        XCTAssertTrue(without.nextItemForBroadcast?.details?.leaders.isEmpty ?? true)

        let with = makeProducer(roles: [RoleCue(id: "band", name: "Band", pagerFields: [.leader])])
        let current = try XCTUnwrap(with.activeTimerItemForBroadcast?.details)
        XCTAssertEqual(current.leaders.map(\.firstName), ["Sam", "Pat"])
        XCTAssertEqual(PCOItemLeader.bylineNames(current.leaders), "Sam & Pat")
        let data = try JSONEncoder().encode(with.activeTimerItemForBroadcast)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("example.com"))
        XCTAssertFalse(text.contains("Rivera"))
        XCTAssertFalse(text.contains("personId"))
        XCTAssertTrue(text.contains("\"firstName\":\"Sam\""))
        let next = try XCTUnwrap(with.nextItemForBroadcast)
        XCTAssertEqual(next.details?.leaders.map(\.firstName), ["Sam", "Pat"])
        XCTAssertLessThan(try JSONEncoder().encode(next).count, 700)
    }

    func testTypeAndLengthNeedNoExtraWireData() throws {
        let engine = makeProducer(roles: [RoleCue(id: "band", name: "Band", pagerFields: [.type, .length])])
        XCTAssertNil(engine.activeTimerItemForBroadcast?.details)
        let next = try XCTUnwrap(engine.nextItemForBroadcast)
        XCTAssertEqual(next.itemType, "song")
        XCTAssertEqual(next.lengthInSeconds, 240)
        XCTAssertEqual(next.timerItem.pagerDetailsLine(fields: [.type, .length]), "Song \u{00B7} 4:00")
    }

    func testWireSizeStaysBoundedWithEveryFieldAndNoteChosen() throws {
        let items: [RolePagerItem] = PagerItemField.allCases.map(RolePagerItem.field) + [.note("Audio"), .note("Lights")]
        let engine = makeProducer(roles: [RoleCue(id: "a", name: "A", pagerItems: items), RoleCue(id: "b", name: "B", pagerItems: items.reversed())])
        let next = try JSONEncoder().encode(try XCTUnwrap(engine.nextItemForBroadcast)).count
        let timer = try JSONEncoder().encode(try XCTUnwrap(engine.activeTimerItemForBroadcast)).count
        print("pager items wire sizes: next=\(next) timer=\(timer)")
        XCTAssertLessThan(next, 1000)
        XCTAssertLessThan(timer, 1400)
        let pong = engine.makeV2CatchUpPong(to: nil)
        XCTAssertLessThanOrEqual(pong.encode()?.count ?? .max, CueEngine.maxCatchUpPongBytes)
    }

    func testApiPatchAcceptsAnOrderedPagerItemsList() throws {
        let engine = makeProducer(roles: [RoleCue(id: "band", name: "Band", pagerFields: [.key], pagerItems: nil)])
        let router = ControlAPIRouter(engine: engine)
        func patch(_ json: String) -> HTTPResponse {
            router.handle(HTTPRequest(method: "PATCH", path: "/v1/roles/band", body: Data(json.utf8)))
        }
        let response = patch(#"{"pagerItems":["note:Lights","field:leader","note:Audio","field:bpm"]}"#)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(engine.roles[0].pagerItems, [.note("Lights"), .field(.leader), .note("Audio"), .field(.bpm)])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        XCTAssertEqual(object["pagerItems"] as? [String], ["note:Lights", "field:leader", "note:Audio", "field:bpm"])
        XCTAssertEqual(object["assignedNoteCategories"] as? [String], ["Lights", "Audio"])
        XCTAssertEqual(object["pagerFields"] as? [String], ["leader", "bpm"])

        XCTAssertEqual(patch(#"{"pagerItems":["field:key","note:"]}"#).status, 400)
        XCTAssertEqual(patch(#"{"pagerItems":["bogus"]}"#).status, 400)
        XCTAssertEqual(patch(#"{"pagerItems":["field:nope"]}"#).status, 400)
        XCTAssertEqual(engine.roles[0].pagerItems, [.note("Lights"), .field(.leader), .note("Audio"), .field(.bpm)])

        XCTAssertEqual(patch(#"{"assignedNoteCategories":["Audio","Video"]}"#).status, 200)
        XCTAssertEqual(engine.roles[0].assignedNoteCategories, ["Audio", "Video"])
        XCTAssertEqual(engine.roles[0].pagerFields, [.leader, .bpm])
        XCTAssertEqual(patch(#"{"pagerItems":[]}"#).status, 200)
        XCTAssertEqual(engine.roles[0].pagerItems, [])
        XCTAssertEqual(patch(#"{"pagerItems":["field:key"],"pagerFields":["bpm"]}"#).status, 200)
        XCTAssertEqual(engine.roles[0].pagerItems, [.field(.key)])
    }

    func testEngineRoleRoundTripKeepsTheOrder() throws {
        let engine = makeProducer(roles: [RoleCue(id: "band", name: "Band")])
        engine.setPagerItems(forRoleId: "band", [.note("Z"), .field(.key), .note("A")])
        let decoded = try JSONDecoder().decode(RoleCue.self, from: JSONEncoder().encode(engine.roles[0]))
        XCTAssertEqual(decoded.assignedNoteCategories, ["Z", "A"])
        XCTAssertEqual(decoded.pagerItems, [.note("Z"), .field(.key), .note("A")])
    }
}
