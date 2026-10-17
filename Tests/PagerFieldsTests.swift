// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

private func richSong(id: String = "s1", sequence: [String] = ["V1", "C", "V2", "C", "B", "C"]) -> PCOTimerItem {
    PCOTimerItem(
        id: id,
        title: "Song \(id)",
        itemType: "Song",
        lengthInSeconds: 300,
        details: PCOItemDetails(
            description: "  Walk on\n  slowly  ",
            htmlDetails: String(repeating: "<p>lyrics lyrics lyrics</p>", count: 200),
            servicePosition: .pre,
            keyName: "Ab",
            song: PCOSongInfo(id: "song", title: "Heavy", author: "Author", copyright: "Copyright", ccliNumber: 1, themes: ["a", "b", "c"]),
            arrangement: PCOArrangementInfo(
                id: "arr", name: "Default", bpm: 72, meter: "4/4", length: 280,
                sequence: ["Verse 1", "Chorus", "Verse 2", "Chorus", "Bridge", "Chorus"],
                sequenceShort: sequence,
                hasChordChart: true, hasChords: true,
                notes: String(repeating: "Capo 3, watch the bridge. ", count: 40)
            ),
            key: PCOKeyInfo(id: "key", name: "Ab", startingKey: "G", endingKey: "G", alternateKeys: ["A", "Bb", "C"]),
            customSequence: ["Verse 1", "Chorus"],
            customSequenceShort: [],
            media: PCOMediaInfo(id: "media", title: "Clip", mediaType: "background_video", themes: ["x"], length: 30, thumbnailURL: "https://example.com/thumbnail.png"),
            itemTimes: (0..<4).map { PCOItemTimeInfo(id: "t\($0)", planTimeId: "pt\($0)", length: 280, lengthOffset: 0, exclude: false, liveStartAt: Date(timeIntervalSince1970: 100), liveEndAt: Date(timeIntervalSince1970: 380)) }
        )
    )
}

final class PagerItemFieldTests: XCTestCase {
    func testNormalizedDedupesAndUsesCanonicalOrder() {
        XCTAssertEqual(PagerItemField.normalized([.sequence, .key, .key, .bpm]), [.key, .bpm, .sequence])
        XCTAssertEqual(PagerItemField.normalized([]), [])
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(
            PagerItemField.allCases.map(\.rawValue),
            ["key", "bpm", "meter", "arrangement", "sequence", "description", "mediaType", "servicePosition", "startTime", "itemDetails"]
        )
        XCTAssertEqual(PagerItemField.itemDetails.label, "Item details")
        XCTAssertEqual(PagerItemField.allCases.filter { !$0.isLineSegment }, [.itemDetails])
    }

    func testRoleDecodesWithoutPagerFields() throws {
        let json = #"{"id":"r","name":"Band","state":"OFF","lastUpdated":0,"assignedNoteCategories":[]}"#
        let role = try JSONDecoder().decode(RoleCue.self, from: Data(json.utf8))
        XCTAssertNil(role.pagerFields)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(role)) as? [String: Any])
        XCTAssertNil(encoded["pagerFields"])
    }

    func testRoleRoundTripsAndDropsUnknownFields() throws {
        let json = #"{"id":"r","name":"Band","state":"OFF","lastUpdated":0,"assignedNoteCategories":[],"pagerFields":["sequence","future","key"]}"#
        let role = try JSONDecoder().decode(RoleCue.self, from: Data(json.utf8))
        XCTAssertEqual(role.pagerFields, [.key, .sequence])
        let decoded = try JSONDecoder().decode(RoleCue.self, from: JSONEncoder().encode(role))
        XCTAssertEqual(decoded, role)
        let api = try ControlAPIJSON.decoder.decode(RoleCue.self, from: ControlAPIJSON.encoder.encode(role))
        XCTAssertEqual(api.pagerFields, [.key, .sequence])
    }

    func testRoleWithMalformedPagerFieldsStillDecodes() throws {
        let json = #"{"id":"r","name":"Band","state":"OFF","lastUpdated":0,"assignedNoteCategories":[],"pagerFields":"key"}"#
        let role = try JSONDecoder().decode(RoleCue.self, from: Data(json.utf8))
        XCTAssertNil(role.pagerFields)
    }
}

final class PagerDetailsFormatTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    func testLineFollowsCanonicalFieldOrder() {
        let song = richSong()
        XCTAssertEqual(
            song.pagerDetailsLine(fields: [.sequence, .meter, .bpm, .key]),
            "G \u{00B7} 72 BPM \u{00B7} 4/4 \u{00B7} V1 C V2 C B C"
        )
    }

    func testEveryFieldTogether() {
        let line = richSong().pagerDetailsLine(fields: PagerItemField.allCases, startTime: start, clockFormat: .twentyFourHour, timeZone: utc)
        XCTAssertEqual(
            line,
            "G \u{00B7} 72 BPM \u{00B7} 4/4 \u{00B7} Default \u{00B7} V1 C V2 C B C \u{00B7} Walk on slowly \u{00B7} Background Video \u{00B7} Pre-service \u{00B7} @ 08:53"
        )
    }

    func testStartTimeFollowsClockFormatAndZone() {
        let song = richSong()
        XCTAssertEqual(song.pagerDetailsLine(fields: [.startTime], startTime: start, clockFormat: .twelveHour, timeZone: utc), "@ 8:53 AM")
        XCTAssertEqual(song.pagerDetailsLine(fields: [.startTime], startTime: start, clockFormat: .twentyFourHour, timeZone: TimeZone(secondsFromGMT: 9 * 3600)!), "@ 17:53")
        XCTAssertNil(song.pagerDetailsLine(fields: [.startTime], startTime: nil))
    }

    func testCustomSequenceWinsAndKeyFallsBack() {
        var song = richSong()
        song.details?.customSequenceShort = ["C", "B"]
        song.details?.key = nil
        XCTAssertEqual(song.pagerDetailsLine(fields: [.key, .sequence]), "Ab \u{00B7} C B")
        song.details?.keyName = nil
        XCTAssertEqual(song.pagerDetailsLine(fields: [.key]), nil)
    }

    func testDuringServiceAndHeadersAndManualItemsShowNothing() {
        var song = richSong()
        song.details?.servicePosition = .during
        XCTAssertNil(song.pagerDetailsLine(fields: [.servicePosition]))
        var header = richSong()
        header.itemType = "Header"
        XCTAssertNil(header.pagerDetailsLine(fields: PagerItemField.allCases))
        XCTAssertNil(PCOTimerItem(title: "Manual").pagerDetailsLine(fields: PagerItemField.allCases))
        XCTAssertNil(richSong().pagerDetailsLine(fields: []))
    }

    func testItemDetailsIsNeverPartOfTheLine() {
        let song = richSong()
        XCTAssertNil(song.pagerDetailsLine(fields: [.itemDetails]))
        XCTAssertEqual(song.pagerDetailsLine(fields: [.key, .itemDetails]), "G")
        let everyLineField = PagerItemField.allCases.filter(\.isLineSegment)
        XCTAssertEqual(
            song.pagerDetailsLine(fields: PagerItemField.allCases, startTime: start, clockFormat: .twentyFourHour, timeZone: utc),
            song.pagerDetailsLine(fields: everyLineField, startTime: start, clockFormat: .twentyFourHour, timeZone: utc)
        )
    }

    func testItemDetailsSourcePrefersHTMLAndTrustsDescriptionOnlyWhenAsked() {
        var song = richSong()
        XCTAssertEqual(song.itemDetailsSource(includingDescription: false), song.details?.htmlDetails)
        song.details?.htmlDetails = nil
        XCTAssertNil(song.itemDetailsSource(includingDescription: false))
        XCTAssertEqual(song.itemDetailsSource(includingDescription: true), "  Walk on\n  slowly  ")
        song.details?.htmlDetails = String(repeating: "x", count: PCOTimerItem.maxItemDetailsCharacters + 10)
        XCTAssertEqual(song.itemDetailsSource(includingDescription: false)?.count, PCOTimerItem.maxItemDetailsCharacters)
        song.itemType = "Header"
        XCTAssertNil(song.itemDetailsSource(includingDescription: true))
        XCTAssertNil(PCOTimerItem(title: "Manual").itemDetailsSource(includingDescription: true))
    }

    func testFractionalBPM() {
        var song = richSong()
        song.details?.arrangement?.bpm = 90.5
        XCTAssertEqual(song.pagerDetailsLine(fields: [.bpm]), "90.5 BPM")
    }
}

@MainActor
final class PagerFieldsEngineTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearPersistedState()
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

    private func makeProducer(roles: [RoleCue]) -> CueEngine {
        let engine = CueEngine(startsNetworking: false)
        engine.roles = roles
        engine.selectedRoleIds = Set(roles.map(\.id))
        engine.importFlow(title: "Plan", items: [
            richSong(id: "a"),
            richSong(id: "b", sequence: ["V1", "C"]),
            PCOTimerItem(id: "c", title: "Sermon", itemType: "Item", lengthInSeconds: 1800),
        ])
        return engine
    }

    func testDisplayPagerFieldsUsesFirstSelectedRoleWithAValue() {
        let engine = CueEngine(startsNetworking: false)
        engine.roles = [
            RoleCue(id: "a", name: "A"),
            RoleCue(id: "b", name: "B", pagerFields: [.bpm, .key]),
            RoleCue(id: "c", name: "C", pagerFields: [.meter]),
        ]
        engine.selectedRoleIds = ["a", "b", "c"]
        XCTAssertEqual(engine.displayPagerFields, [.key, .bpm])
        engine.selectedRoleIds = ["c"]
        XCTAssertEqual(engine.displayPagerFields, [.meter])
        engine.selectedRoleIds = ["a"]
        XCTAssertEqual(engine.displayPagerFields, [])
    }

    func testSetPagerFieldsNormalizesAndToggles() {
        let engine = makeProducer(roles: [RoleCue(id: "band", name: "Band")])
        engine.setPagerFields(forRoleId: "band", [.sequence, .key])
        XCTAssertEqual(engine.roles[0].pagerFields, [.key, .sequence])
        engine.setPagerField(forRoleId: "band", field: .bpm, isOn: true)
        XCTAssertEqual(engine.roles[0].pagerFields, [.key, .bpm, .sequence])
        engine.setPagerField(forRoleId: "band", field: .key, isOn: false)
        XCTAssertEqual(engine.roles[0].pagerFields, [.bpm, .sequence])
        engine.setPagerFields(forRoleId: "band", nil)
        XCTAssertNil(engine.roles[0].pagerFields)
    }

    func testApiPatchSetsAndClearsPagerFields() throws {
        let engine = makeProducer(roles: [RoleCue(id: "band", name: "Band")])
        let router = ControlAPIRouter(engine: engine)
        func patch(_ json: String) -> HTTPResponse {
            router.handle(HTTPRequest(method: "PATCH", path: "/v1/roles/band", body: Data(json.utf8)))
        }
        let response = patch(#"{"pagerFields":["sequence","key"]}"#)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(engine.roles[0].pagerFields, [.key, .sequence])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        XCTAssertEqual(object["pagerFields"] as? [String], ["key", "sequence"])
        XCTAssertEqual(patch(#"{"name":"Band"}"#).status, 200)
        XCTAssertEqual(engine.roles[0].pagerFields, [.key, .sequence])
        XCTAssertEqual(patch(#"{"pagerFields":["key","nope"]}"#).status, 400)
        XCTAssertEqual(engine.roles[0].pagerFields, [.key, .sequence])
        XCTAssertEqual(patch(#"{"pagerFields":[]}"#).status, 200)
        XCTAssertEqual(engine.roles[0].pagerFields, [])
    }

    func testBroadcastCarriesNothingWhenNoRoleChoseFields() {
        let engine = makeProducer(roles: [RoleCue(id: "band", name: "Band")])
        XCTAssertNil(engine.activeTimerItemForBroadcast?.details)
        XCTAssertNil(engine.nextItemForBroadcast?.details)
        XCTAssertNil(engine.nextItemForBroadcast?.startsAtMs)
    }

    func testBroadcastCarriesOnlyWhatTheChosenFieldsNeed() throws {
        let engine = makeProducer(roles: [RoleCue(id: "band", name: "Band", pagerFields: [.key, .bpm])])
        let current = try XCTUnwrap(engine.activeTimerItemForBroadcast?.details)
        XCTAssertEqual(current.displayKey, "G")
        XCTAssertEqual(current.arrangement?.bpm, 72)
        XCTAssertNil(current.arrangement?.meter)
        XCTAssertNil(current.arrangement?.name)
        XCTAssertEqual(current.arrangement?.sequenceShort, [])
        XCTAssertNil(current.description)
        XCTAssertNil(current.media)
        XCTAssertNil(current.htmlDetails)
        XCTAssertNil(current.song)
        XCTAssertTrue(current.itemTimes.isEmpty)
        XCTAssertEqual(current.servicePosition, .during)

        let next = try XCTUnwrap(engine.nextItemForBroadcast?.details)
        XCTAssertEqual(next.displayKey, "G")
        XCTAssertEqual(next.arrangement?.bpm, 72)
        XCTAssertNil(engine.nextItemForBroadcast?.startsAtMs)
    }

    func testItemDetailsNeverRidesTheLANPackets() throws {
        let engine = makeProducer(roles: [RoleCue(id: "band", name: "Band", pagerFields: [.itemDetails])])
        XCTAssertNil(engine.activeTimerItemForBroadcast?.details)
        XCTAssertNil(engine.nextItemForBroadcast?.details)
        let both = makeProducer(roles: [RoleCue(id: "band", name: "Band", pagerFields: [.key, .itemDetails, .description])])
        let current = try XCTUnwrap(both.activeTimerItemForBroadcast?.details)
        XCTAssertNil(current.htmlDetails)
        XCTAssertEqual(current.displayKey, "G")
        XCTAssertNil(both.nextItemForBroadcast?.details?.htmlDetails)
        let encoded = try XCTUnwrap(both.makeV2CatchUpPong(to: nil).encode())
        XCTAssertLessThanOrEqual(encoded.count, CueEngine.maxCatchUpPongBytes)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("lyrics lyrics"))
    }

    func testApiAcceptsItemDetails() throws {
        let engine = makeProducer(roles: [RoleCue(id: "band", name: "Band")])
        let router = ControlAPIRouter(engine: engine)
        let response = router.handle(HTTPRequest(method: "PATCH", path: "/v1/roles/band", body: Data(#"{"pagerFields":["itemDetails","key"]}"#.utf8)))
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(engine.roles[0].pagerFields, [.key, .itemDetails])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        XCTAssertEqual(object["pagerFields"] as? [String], ["key", "itemDetails"])
    }

    func testBroadcastUsesTheUnionOfAllRolesFields() throws {
        let engine = makeProducer(roles: [
            RoleCue(id: "a", name: "A", pagerFields: [.key]),
            RoleCue(id: "b", name: "B", pagerFields: [.sequence, .servicePosition, .mediaType, .description]),
        ])
        let current = try XCTUnwrap(engine.activeTimerItemForBroadcast?.details)
        XCTAssertEqual(current.displayKey, "G")
        XCTAssertEqual(current.arrangement?.sequenceShort, ["V1", "C", "V2", "C", "B", "C"])
        XCTAssertEqual(current.servicePosition, .pre)
        XCTAssertEqual(current.media?.mediaType, "background_video")
        XCTAssertEqual(current.description, "  Walk on\n  slowly  ")
        XCTAssertNil(current.arrangement?.bpm)
    }

    func testNextItemCarriesDetailsAndProjectedStartOnlyForStartTime() throws {
        let engine = makeProducer(roles: [RoleCue(id: "band", name: "Band", pagerFields: [.sequence, .startTime])])
        if engine.activeTimerItem?.isRunning != true { engine.toggleTimerRunning() }
        let next = try XCTUnwrap(engine.nextItemForBroadcast)
        XCTAssertEqual(next.details?.arrangement?.sequenceShort, ["V1", "C"])
        let startsAt = try XCTUnwrap(next.startsAtMs)
        let expected = Date().timeIntervalSince1970 * 1000 + 300_000
        XCTAssertEqual(Double(startsAt), expected, accuracy: 3000)
        XCTAssertEqual(next.timerItem.details?.arrangement?.sequenceShort, ["V1", "C"])
        XCTAssertEqual(next.withoutStart.startsAtMs, nil)
    }

    func testChangingOnlyTheStartTimeDoesNotCountAsANewNextItem() {
        let first = CueNextItem(id: "n", title: "N", itemType: "Item", lengthInSeconds: 1, notes: [:], startsAtMs: 1000)
        var second = first
        second.startsAtMs = 61000
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.withoutStart, second.withoutStart)
    }

    func testRichSongSlimPayloadStaysSmall() throws {
        let item = richSong()
        let full = try JSONEncoder().encode(item).count
        let allFields = Set(PagerItemField.allCases)
        let slimAll = try JSONEncoder().encode(item.broadcastTrimmed(fields: allFields)).count
        let keyBpmSeq = try JSONEncoder().encode(item.broadcastTrimmed(fields: [.key, .bpm, .meter, .sequence])).count
        let bare = try JSONEncoder().encode(PCOTimerItem(id: "s1", title: "Song s1", itemType: "Song", lengthInSeconds: 300)).count
        let next = try JSONEncoder().encode(CueNextItem(item: item, noteCategories: [], pagerFields: allFields, startsAtMs: 1_760_000_000_000)).count
        print("pager fields wire sizes: bare=\(bare) keyBpmMeterSeq=\(keyBpmSeq) all=\(slimAll) full=\(full) nextAll=\(next)")
        XCTAssertLessThan(keyBpmSeq - bare, 600)
        XCTAssertLessThan(slimAll - bare, 800)
        XCTAssertLessThan(next, 1000)
        XCTAssertLessThan(slimAll, full / 10)
    }

    func testCatchUpPongStaysWithinTheSizeLimitWithEveryFieldChosen() {
        let engine = makeProducer(roles: [
            RoleCue(id: "a", name: "A", assignedNoteCategories: ["Band"], pagerFields: PagerItemField.allCases),
            RoleCue(id: "b", name: "B", pagerFields: PagerItemField.allCases),
        ])
        let pong = engine.makeV2CatchUpPong(to: nil)
        XCTAssertLessThanOrEqual(pong.encode()?.count ?? .max, CueEngine.maxCatchUpPongBytes)
        XCTAssertNotNil(pong.timerItem?.details)
    }
}

final class PagerPresentationFieldsTests: XCTestCase {
    private let utc = 0

    private func presentation(
        fields: [PagerItemField]?,
        active: PCOTimerItem? = richSong(id: "a"),
        next: PCOTimerItem? = richSong(id: "b", sequence: ["V1", "C"]),
        nextStart: Date? = nil,
        clockFormat: ClockFormat = .twentyFourHour,
        selected: String = "band"
    ) -> PagerPresentationState {
        PagerPresentationState(
            roles: [RoleCue(id: "host", name: "Host"), RoleCue(id: "band", name: "Band", pagerFields: fields)],
            planItems: [],
            activeItemIndex: 0,
            activeTimerItem: active,
            recentMessages: [],
            selectedRoleId: selected,
            isProducerLive: true,
            isLANConnected: true,
            connectedMasterName: nil,
            hourFormatThreshold: .over90Minutes,
            clockFormat: clockFormat,
            receivedNextItem: next,
            producerClockOffsetMs: 0,
            producerUTCOffsetSeconds: utc,
            nextItemStartDate: nextStart
        )
    }

    func testFieldsFollowTheSelectedRole() {
        XCTAssertEqual(presentation(fields: [.bpm, .key]).pagerFields, [.key, .bpm])
        XCTAssertEqual(presentation(fields: [.bpm], selected: "host").pagerFields, [])
        XCTAssertEqual(presentation(fields: nil).pagerFields, [])
        XCTAssertNil(presentation(fields: nil).currentDetailsLine())
        XCTAssertNil(presentation(fields: nil).nextDetailsLine())
    }

    func testCurrentAndNextLines() {
        let state = presentation(fields: [.key, .bpm, .meter, .sequence])
        XCTAssertEqual(state.currentDetailsLine(), "G \u{00B7} 72 BPM \u{00B7} 4/4 \u{00B7} V1 C V2 C B C")
        XCTAssertEqual(state.nextDetailsLine(), "G \u{00B7} 72 BPM \u{00B7} 4/4 \u{00B7} V1 C")
    }

    func testCurrentStartIsNowMinusElapsed() {
        var active = richSong(id: "a")
        active.isRunning = true
        active.elapsedSeconds = 125
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let state = presentation(fields: [.startTime], active: active)
        XCTAssertEqual(state.currentDetailsLine(now: now), "@ 08:51")
        active.isRunning = false
        active.elapsedSeconds = 0
        XCTAssertNil(presentation(fields: [.startTime], active: active).currentDetailsLine(now: now))
    }

    func testNextStartNeverEarlierThanTheRunningItemEnds() {
        var active = richSong(id: "a")
        active.isRunning = true
        active.elapsedSeconds = 100
        active.lengthInSeconds = 300
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let early = presentation(fields: [.startTime], active: active, nextStart: now.addingTimeInterval(10))
        XCTAssertEqual(early.nextStartDate(now: now), now.addingTimeInterval(200))
        let late = presentation(fields: [.startTime], active: active, nextStart: now.addingTimeInterval(900))
        XCTAssertEqual(late.nextStartDate(now: now), now.addingTimeInterval(900))
        active.isRunning = false
        let paused = presentation(fields: [.startTime], active: active, nextStart: now.addingTimeInterval(900))
        XCTAssertEqual(paused.nextStartDate(now: now), now.addingTimeInterval(900))
        XCTAssertNil(presentation(fields: [.startTime], active: active).nextStartDate(now: now))
        XCTAssertEqual(late.nextDetailsLine(now: now), "@ 09:08")
    }
}
