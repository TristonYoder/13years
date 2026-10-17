// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

private enum Fixture {
    static let itemsPage1 = """
    {
      "links": {"next": "https://api.planningcenteronline.com/services/v2/service_types/st/plans/p/items?offset=3&per_page=3&include=x"},
      "data": [
        {"type": "Item", "id": "100", "attributes": {"title": "Doors Open", "item_type": "item", "length": 600, "service_position": "pre", "description": "Walk-in music"},
         "relationships": {"item_notes": {"data": []}, "song": {"data": null}, "item_times": {"data": [{"type": "ItemTime", "id": "t100"}]}}},
        {"type": "Item", "id": "101", "attributes": {"title": "Welcome", "item_type": "header", "length": 0, "service_position": "during"},
         "relationships": {"item_notes": {"data": []}}},
        {"type": "Item", "id": "102", "attributes": {"title": "Great Is Thy Faithfulness", "item_type": "song", "length": 270, "key_name": "G", "service_position": "during", "custom_arrangement_sequence_short": ["V1", "C", "V2", "C"], "description": "Lead in with piano"},
         "relationships": {
           "item_notes": {"data": [{"type": "ItemNote", "id": "n1"}]},
           "song": {"data": {"type": "Song", "id": "s1"}},
           "arrangement": {"data": {"type": "Arrangement", "id": "a1"}},
           "key": {"data": {"type": "Key", "id": "k1"}},
           "item_times": {"data": [{"type": "ItemTime", "id": "t1"}, {"type": "ItemTime", "id": "t2"}]}}}
      ],
      "included": [
        {"type": "ItemNoteCategory", "id": "1", "attributes": {"name": "Audio"}},
        {"type": "ItemNote", "id": "n1", "attributes": {"content": "Reverb up"}, "relationships": {"item_note_category": {"data": {"type": "ItemNoteCategory", "id": "1"}}}},
        {"type": "Song", "id": "1", "attributes": {"title": "Wrong Song Sharing An Id"}},
        {"type": "Song", "id": "s1", "attributes": {"title": "Great Is Thy Faithfulness", "author": "Thomas Chisholm", "copyright": "Hope Publishing", "ccli_number": 18723, "themes": "Faithfulness, Praise"}},
        {"type": "Arrangement", "id": "a1", "attributes": {"name": "Default", "bpm": 72, "meter": "4/4", "length": 270, "sequence": ["Verse 1", "Chorus 1", "Verse 2", "Chorus 2"], "sequence_short": ["V1", "C1", "V2", "C2"], "has_chord_chart": true, "has_chords": true, "notes": "Capo 2"}},
        {"type": "Key", "id": "k1", "attributes": {"name": "Original", "starting_key": "G", "ending_key": "G", "alternate_keys": "[{\\"name\\": \\"Low\\", \\"key\\": \\"E\\"}]"}},
        {"type": "ItemTime", "id": "t100", "attributes": {"exclude": false, "length": 600, "length_offset": 0}, "relationships": {"plan_time": {"data": {"type": "PlanTime", "id": "pt1"}}}},
        {"type": "ItemTime", "id": "t1", "attributes": {"exclude": false, "length": 270, "length_offset": 0, "live_start_at": "2026-10-18T14:05:00Z", "live_end_at": "2026-10-18T14:09:30Z"}, "relationships": {"plan_time": {"data": {"type": "PlanTime", "id": "pt1"}}}},
        {"type": "ItemTime", "id": "t2", "attributes": {"exclude": true, "length": 270, "length_offset": 15}, "relationships": {"plan_time": {"data": {"type": "PlanTime", "id": "pt2"}}}}
      ],
      "meta": {"total_count": 4, "count": 3}
    }
    """

    static let itemsPage2 = """
    {
      "data": [
        {"type": "Item", "id": "103", "attributes": {"title": "Testimony Video", "item_type": "media", "length": 180, "service_position": "during"},
         "relationships": {"item_notes": {"data": []}, "media": {"data": {"type": "Media", "id": "m1"}}, "item_times": {"data": []}}}
      ],
      "included": [
        {"type": "Media", "id": "m1", "attributes": {"title": "Baptism Story", "media_type": "video", "themes": "Grace", "length": 175, "thumbnail_url": "https://example.com/t.png"}},
        {"type": "ItemNoteCategory", "id": "1", "attributes": {"name": "Audio"}}
      ]
    }
    """

    static func json(_ text: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    }
}

final class PCOItemDetailsParsingTests: XCTestCase {
    private func parsed() -> [PCOTimerItem] {
        let merged = PCOClient.mergePages([Fixture.json(Fixture.itemsPage1), Fixture.json(Fixture.itemsPage2)])
        return PCOClient.parsePlanItems(merged, serviceTypeId: "st", planId: "p")
    }

    func testPaginationMergesDataAndDeduplicatesIncluded() {
        let merged = PCOClient.mergePages([Fixture.json(Fixture.itemsPage1), Fixture.json(Fixture.itemsPage2)])
        XCTAssertEqual((merged["data"] as? [[String: Any]])?.count, 4)
        let included = merged["included"] as? [[String: Any]] ?? []
        XCTAssertEqual(included.filter { $0["type"] as? String == "ItemNoteCategory" }.count, 1)
        XCTAssertEqual(included.filter { $0["type"] as? String == "Media" }.count, 1)
    }

    func testCollectPagesFollowsNextLinksAndStops() async throws {
        let first = URL(string: "https://api.planningcenteronline.com/services/v2/service_types/st/plans/p/items?per_page=3")!
        var requested: [URL] = []
        let merged = try await PCOClient.collectPages(from: first) { url in
            requested.append(url)
            return url == first ? Fixture.json(Fixture.itemsPage1) : Fixture.json(Fixture.itemsPage2)
        }
        XCTAssertEqual(requested.count, 2)
        XCTAssertEqual(requested[1].absoluteString, "https://api.planningcenteronline.com/services/v2/service_types/st/plans/p/items?offset=3&per_page=3&include=x")
        XCTAssertEqual((merged["data"] as? [[String: Any]])?.count, 4)
    }

    func testNextPageLinkMustStayOnSameHost() {
        let current = URL(string: "https://api.planningcenteronline.com/services/v2/items?per_page=25")!
        let sameHost: [String: Any] = ["links": ["next": "https://api.planningcenteronline.com/services/v2/items?offset=25"]]
        XCTAssertEqual(PCOClient.nextPageURL(in: sameHost, after: current)?.host, "api.planningcenteronline.com")
        let otherHost: [String: Any] = ["links": ["next": "https://evil.example.com/items?offset=25"]]
        XCTAssertNil(PCOClient.nextPageURL(in: otherHost, after: current))
        let plainHTTP: [String: Any] = ["links": ["next": "http://api.planningcenteronline.com/services/v2/items?offset=25"]]
        XCTAssertNil(PCOClient.nextPageURL(in: plainHTTP, after: current))
    }

    func testNextPageFallsBackToMetaOffset() {
        let current = URL(string: "https://example.com/items?per_page=25&offset=25")!
        let page: [String: Any] = ["meta": ["next": ["offset": 50]]]
        let next = PCOClient.nextPageURL(in: page, after: current)
        let items = URLComponents(url: next!, resolvingAgainstBaseURL: true)?.queryItems
        XCTAssertEqual(items?.filter { $0.name == "offset" }.map(\.value), ["50"])
        XCTAssertEqual(items?.first { $0.name == "per_page" }?.value, "25")
        XCTAssertNil(PCOClient.nextPageURL(in: ["meta": ["count": 3]], after: current))
    }

    func testParsesEveryItemKindAcrossPages() {
        let items = parsed()
        XCTAssertEqual(items.map(\.title), ["Doors Open", "Welcome", "Great Is Thy Faithfulness", "Testimony Video"])
        XCTAssertEqual(items.map(\.sequence), [1, 2, 3, 4])
        XCTAssertTrue(items[1].isHeader)
        XCTAssertTrue(items.allSatisfy { $0.pcoPlanId == "p" && $0.pcoServiceTypeId == "st" && $0.details != nil })
    }

    func testSongItemCarriesArrangementKeyAndItemTimes() throws {
        let song = parsed()[2]
        let details = try XCTUnwrap(song.details)
        XCTAssertEqual(song.notes, ["Audio": "Reverb up"])
        XCTAssertEqual(song.noteIds, ["Audio": "n1"])
        XCTAssertEqual(details.song?.title, "Great Is Thy Faithfulness")
        XCTAssertEqual(details.song?.ccliNumber, 18723)
        XCTAssertEqual(details.song?.themes, ["Faithfulness", "Praise"])
        XCTAssertEqual(details.arrangement?.bpm, 72)
        XCTAssertEqual(details.arrangement?.meter, "4/4")
        XCTAssertEqual(details.arrangement?.sequenceShort, ["V1", "C1", "V2", "C2"])
        XCTAssertEqual(details.arrangement?.hasChordChart, true)
        XCTAssertEqual(details.key?.startingKey, "G")
        XCTAssertEqual(details.key?.alternateKeys, ["E"])
        XCTAssertEqual(details.displayKey, "G")
        XCTAssertEqual(details.customSequenceShort, ["V1", "C", "V2", "C"])
        XCTAssertEqual(details.effectiveSequenceShort, ["V1", "C", "V2", "C"])
        XCTAssertEqual(details.description, "Lead in with piano")
        XCTAssertEqual(details.itemTimes.map(\.planTimeId), ["pt1", "pt2"])
        XCTAssertEqual(details.itemTimes[0].liveStartAt, ISO8601DateFormatter().date(from: "2026-10-18T14:05:00Z"))
        XCTAssertFalse(details.isExcluded(fromPlanTimeId: "pt1"))
        XCTAssertTrue(details.isExcluded(fromPlanTimeId: "pt2"))
        XCTAssertEqual(details.itemTime(forPlanTimeId: "pt2")?.lengthOffset, 15)
    }

    func testMediaPreServiceAndHeaderItems() {
        let items = parsed()
        XCTAssertEqual(items[0].details?.servicePosition, .pre)
        XCTAssertEqual(items[0].details?.description, "Walk-in music")
        XCTAssertNil(items[0].details?.song)
        XCTAssertEqual(items[1].details?.servicePosition, .during)
        XCTAssertEqual(items[3].details?.media?.mediaType, "video")
        XCTAssertEqual(items[3].details?.media?.themes, ["Grace"])
        XCTAssertEqual(items[3].details?.media?.thumbnailURL, "https://example.com/t.png")
        XCTAssertTrue(items[3].details?.itemTimes.isEmpty ?? false)
    }

    func testIncludedResourcesAreKeyedByTypeAndId() {
        XCTAssertEqual(parsed()[2].details?.song?.id, "s1")
    }

    func testPlanTitleFallsBack() {
        XCTAssertEqual(PCOClient.parsePlanTitle(["data": ["attributes": ["title": "Easter"]]], planId: "9"), "Easter")
        XCTAssertEqual(PCOClient.parsePlanTitle(["data": ["attributes": ["title": "", "series_title": "Grace", "dates": "Oct 18"]]], planId: "9"), "Grace")
        XCTAssertEqual(PCOClient.parsePlanTitle(["data": ["attributes": ["dates": "Oct 18"]]], planId: "9"), "Oct 18")
        XCTAssertEqual(PCOClient.parsePlanTitle([:], planId: "9"), "PCO Plan #9")
    }

    func testParsesPlanContext() throws {
        let plan = Fixture.json("""
        {"data": {"type": "Plan", "id": "p", "attributes": {"title": "", "series_title": "Grace", "dates": "October 18, 2026", "total_length": 3600, "planning_center_url": "https://services.planningcenteronline.com/plans/p"},
                  "relationships": {"plan_times": {"data": [{"type": "PlanTime", "id": "pt2"}, {"type": "PlanTime", "id": "pt1"}]}}},
         "included": [
           {"type": "PlanTime", "id": "pt2", "attributes": {"name": "11:00", "time_type": "service", "starts_at": "2026-10-18T16:00:00Z", "ends_at": "2026-10-18T17:00:00Z"}},
           {"type": "PlanTime", "id": "pt1", "attributes": {"time_type": "rehearsal", "starts_at": "2026-10-16T23:00:00Z"}}]}
        """)
        let notes = Fixture.json("""
        {"data": [{"type": "PlanNote", "id": "pn1", "attributes": {"category_name": "Announcements", "content": "Baptism today"}},
                  {"type": "PlanNote", "id": "pn2", "attributes": {"category_name": "Empty", "content": ""}}]}
        """)
        let team = Fixture.json("""
        {"data": [{"type": "PlanPerson", "id": "pp1", "attributes": {"name": "Sam Lee", "status": "Confirmed", "team_position_name": "Drums"},
                   "relationships": {"person": {"data": {"type": "Person", "id": "77"}}, "team": {"data": {"type": "Team", "id": "tm1"}}, "declined_plan_times": {"data": [{"type": "PlanTime", "id": "pt1"}]}}}],
         "included": [{"type": "Team", "id": "tm1", "attributes": {"name": "Band"}}]}
        """)
        let needed = Fixture.json("""
        {"data": [{"type": "NeededPosition", "id": "np1", "attributes": {"quantity": 2, "team_position_name": "Vocals"},
                   "relationships": {"team": {"data": {"type": "Team", "id": "tm1"}}, "time": {"data": {"type": "PlanTime", "id": "pt2"}}}}],
         "included": [{"type": "Team", "id": "tm1", "attributes": {"name": "Band"}}]}
        """)

        let context = PCOClient.parsePlanContext(plan: plan, notes: notes, team: team, neededPositions: needed, serviceTypeId: "st", planId: "p", fetchedAt: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(context.title, "Grace")
        XCTAssertEqual(context.seriesTitle, "Grace")
        XCTAssertEqual(context.totalLength, 3600)
        XCTAssertEqual(context.planningCenterURL, "https://services.planningcenteronline.com/plans/p")
        XCTAssertEqual(context.times.map(\.id), ["pt1", "pt2"])
        XCTAssertEqual(context.times.map(\.timeType), ["rehearsal", "service"])
        XCTAssertEqual(context.notes, [PCOPlanNoteInfo(id: "pn1", category: "Announcements", content: "Baptism today")])
        let person = try XCTUnwrap(context.team.first)
        XCTAssertEqual(person.name, "Sam Lee")
        XCTAssertEqual(person.personId, "77")
        XCTAssertEqual(person.teamName, "Band")
        XCTAssertEqual(person.positionName, "Drums")
        XCTAssertEqual(person.status, "C")
        XCTAssertEqual(person.declinedPlanTimeIds, ["pt1"])
        XCTAssertEqual(context.neededPositions, [PCONeededPositionInfo(teamName: "Band", positionName: "Vocals", quantity: 2, planTimeIds: ["pt2"])])
    }
}

final class PCOItemDetailsModelTests: XCTestCase {
    private func richDetails() -> PCOItemDetails {
        PCOItemDetails(
            description: String(repeating: "d", count: 300),
            htmlDetails: "<p>Lyrics</p>",
            servicePosition: .post,
            keyName: "A",
            song: PCOSongInfo(id: "s", title: "Song", author: "Author", copyright: "Copy", ccliNumber: 1, themes: ["a", "b"]),
            arrangement: PCOArrangementInfo(id: "a", name: "Default", bpm: 120, meter: "6/8", length: 200, sequence: ["Verse 1", "Chorus 1"], sequenceShort: ["V1", "C1"], hasChordChart: true, hasChords: true, notes: "Capo"),
            key: PCOKeyInfo(id: "k", name: "Original", startingKey: "A", endingKey: "A", alternateKeys: ["C"]),
            customSequence: ["Verse 1"],
            customSequenceShort: ["V1"],
            media: PCOMediaInfo(id: "m", title: "Clip", mediaType: "video", themes: ["x"], length: 30, thumbnailURL: "https://example.com/t.png"),
            itemTimes: [PCOItemTimeInfo(id: "t", planTimeId: "pt", length: 200, lengthOffset: 0, exclude: false, liveStartAt: Date(timeIntervalSince1970: 100), liveEndAt: Date(timeIntervalSince1970: 300))]
        )
    }

    func testItemRoundTripsWithDetails() throws {
        let item = PCOTimerItem(id: "i", title: "Song", itemType: "song", details: richDetails())
        let decoded = try JSONDecoder().decode(PCOTimerItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(decoded, item)

        let encoder = ControlAPIJSON.encoder
        let api = try ControlAPIJSON.decoder.decode(PCOTimerItem.self, from: encoder.encode(item))
        XCTAssertEqual(api, item)
    }

    func testLegacyItemDecodesWithoutDetails() throws {
        let legacy = """
        {"id": "i", "title": "Old", "itemType": "Item", "sequence": 1, "lengthInSeconds": 60, "elapsedSeconds": 0, "isRunning": false}
        """
        let item = try JSONDecoder().decode(PCOTimerItem.self, from: Data(legacy.utf8))
        XCTAssertNil(item.details)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any]
        XCTAssertNil(encoded?["details"])
    }

    func testSparseDetailsDecodeWithDefaults() throws {
        let details = try JSONDecoder().decode(PCOItemDetails.self, from: Data("{}".utf8))
        XCTAssertEqual(details, PCOItemDetails())
        XCTAssertEqual(details.servicePosition, .during)
        let unknown = try JSONDecoder().decode(PCOItemDetails.self, from: Data(#"{"servicePosition": "later"}"#.utf8))
        XCTAssertEqual(unknown.servicePosition, .during)
    }

    func testDocumentRoundTripAndLegacyDecode() throws {
        let context = PCOPlanContext(planId: "p", serviceTypeId: "st", title: "Easter", notes: [PCOPlanNoteInfo(id: "n", category: "A", content: "B")], times: [PCOPlanTimeInfo(id: "t", startsAt: Date(timeIntervalSince1970: 1_700_000_000))], team: [PCOPlanPersonInfo(id: "pp", name: "Sam", declinedPlanTimeIds: ["t"])], neededPositions: [PCONeededPositionInfo(quantity: 2)], fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let document = ProducerDocument(
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            roles: [],
            waypoints: [],
            serviceSchedules: [],
            planItems: [PCOTimerItem(id: "i", title: "Song", details: richDetails())],
            activeItemIndex: 0,
            pcoPlanContext: context,
            settings: .init(hourFormatThreshold: .never, pcoDefaultServiceTypeId: nil, plotipharRelayHost: "")
        )
        XCTAssertEqual(try ProducerDocument.decoded(from: document.encoded()), document)

        var legacy = document
        legacy.pcoPlanContext = nil
        legacy.planItems[0].details = nil
        let decoded = try ProducerDocument.decoded(from: legacy.encoded())
        XCTAssertNil(decoded.pcoPlanContext)
        XCTAssertNil(decoded.planItems[0].details)
    }

    func testContextRefreshDoesNotDirtyTheDocument() {
        var context = PCOPlanContext(planId: "p", serviceTypeId: "st", fetchedAt: Date(timeIntervalSince1970: 1))
        let first = ProducerDocument(roles: [], waypoints: [], serviceSchedules: [], planItems: [], activeItemIndex: 0, pcoPlanContext: context, settings: .init(hourFormatThreshold: .never, pcoDefaultServiceTypeId: nil, plotipharRelayHost: ""))
        context.fetchedAt = Date(timeIntervalSince1970: 999)
        var second = first
        second.pcoPlanContext = context
        XCTAssertEqual(first.normalizedForComparison(), second.normalizedForComparison())
    }

    func testBroadcastTrimmedDropsHeavyFields() throws {
        let item = PCOTimerItem(id: "i", title: "Song", itemType: "song", details: richDetails())
        let slim = try XCTUnwrap(item.broadcastTrimmed.details)

        XCTAssertEqual(slim.servicePosition, .post)
        XCTAssertEqual(slim.displayKey, "A")
        XCTAssertEqual(slim.arrangement?.name, "Default")
        XCTAssertEqual(slim.arrangement?.bpm, 120)
        XCTAssertEqual(slim.arrangement?.meter, "6/8")
        XCTAssertEqual(slim.arrangement?.sequenceShort, ["V1", "C1"])
        XCTAssertEqual(slim.customSequenceShort, ["V1"])
        XCTAssertEqual(slim.media?.mediaType, "video")
        XCTAssertEqual(slim.description?.count, PCOItemDetails.broadcastDescriptionLimit)

        XCTAssertNil(slim.htmlDetails)
        XCTAssertNil(slim.song)
        XCTAssertNil(slim.media?.title)
        XCTAssertNil(slim.media?.thumbnailURL)
        XCTAssertTrue(slim.media?.themes.isEmpty ?? false)
        XCTAssertTrue(slim.itemTimes.isEmpty)
        XCTAssertTrue(slim.customSequence.isEmpty)
        XCTAssertTrue(slim.arrangement?.sequence.isEmpty ?? false)
        XCTAssertNil(slim.arrangement?.notes)
        XCTAssertNil(slim.key?.alternateKeys.first)
        XCTAssertNil(slim.key?.endingKey)
        XCTAssertNil(PCOTimerItem(title: "Manual").broadcastTrimmed.details)
    }

    func testTrimmedItemIsMuchSmallerOnTheWire() throws {
        let item = PCOTimerItem(id: "i", title: "Song", itemType: "song", details: richDetails())
        let full = try JSONEncoder().encode(item).count
        let slim = try JSONEncoder().encode(item.broadcastTrimmed).count
        let bare = try JSONEncoder().encode(PCOTimerItem(id: "i", title: "Song", itemType: "song")).count
        XCTAssertLessThan(slim, full)
        XCTAssertLessThan(slim - bare, 900)
        print("PCOItemDetails wire sizes: bare=\(bare) trimmed=\(slim) full=\(full)")
    }
}

@MainActor
final class PCOItemDetailsEngineTests: XCTestCase {
    private var remote: [PCOTimerItem] = []

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

    private func item(_ id: String, key: String? = nil, length: Int = 300) -> PCOTimerItem {
        PCOTimerItem(
            id: id,
            title: "Item \(id)",
            lengthInSeconds: length,
            pcoServiceTypeId: "st",
            pcoPlanId: "p",
            details: PCOItemDetails(keyName: key, key: key.map { PCOKeyInfo(id: "k", startingKey: $0) })
        )
    }

    private func makeEngine(_ items: [PCOTimerItem]) -> CueEngine {
        let engine = CueEngine(startsNetworking: false)
        engine.isPCOConnected = true
        engine.importFlow(title: "Sunday", items: items)
        engine.beginPCOChangeTracking(planId: "p", items: items)
        engine.pcoChangeTracking.pollTask?.cancel()
        engine.pcoChangeTracking.pushDelay = 0
        engine.pcoChangeTracking.fetchRemote = { [unowned self] _, _ in self.remote }
        return engine
    }

    func testDetailChangesApplyWithoutABanner() async {
        let engine = makeEngine([item("a", key: "G"), item("b", key: "C")])
        remote = [item("a", key: "A"), item("b", key: "C")]

        await engine.checkPCOForChanges()

        XCTAssertNil(engine.pcoPendingChanges)
        XCTAssertEqual(engine.planItems[0].details?.displayKey, "A")
        XCTAssertEqual(engine.activeTimerItem?.details?.displayKey, "A")
        XCTAssertEqual(engine.pcoChangeTracking.baseline[0].details?.displayKey, "A")
    }

    func testDetailChangesAlongsideRealChangesSurviveAccept() async {
        let engine = makeEngine([item("a", key: "G"), item("b", key: "C")])
        remote = [item("a", key: "G"), item("b", key: "D", length: 600)]

        await engine.checkPCOForChanges()
        XCTAssertEqual(engine.pcoPendingChanges?.changes.map(\.kind), [.length])
        XCTAssertTrue(engine.acceptPCOChanges())

        XCTAssertEqual(engine.planItems[1].lengthInSeconds, 600)
        XCTAssertEqual(engine.planItems[1].details?.displayKey, "D")
    }

    func testLocalOnlyFieldsSurviveDetailRefresh() async {
        let engine = makeEngine([item("a", key: "G")])
        engine.planItems[0].waypointIds = ["w1"]
        engine.planItems[0].notes["Local"] = "keep"
        remote = [item("a", key: "B")]

        await engine.checkPCOForChanges()

        XCTAssertEqual(engine.planItems[0].waypointIds, ["w1"])
        XCTAssertEqual(engine.planItems[0].notes["Local"], "keep")
        XCTAssertEqual(engine.planItems[0].details?.displayKey, "B")
    }

    func testMergeAppliesRemoteDetailsOverBaseline() {
        let baseline = [item("a", key: "G")]
        let merged = PCOPlanDiff.merge(remote: [item("a", key: "E")], baseline: baseline, into: baseline, keeping: nil)
        XCTAssertEqual(merged[0].details?.displayKey, "E")
        XCTAssertNil(PCOPlanDiff.changes(from: baseline, to: [item("a", key: "E")]).first)
    }

    func testBroadcastItemIsTrimmed() throws {
        var rich = item("a")
        rich.details?.htmlDetails = "<p>lyrics</p>"
        rich.details?.itemTimes = [PCOItemTimeInfo(id: "t")]
        let engine = makeEngine([rich])
        let broadcast = try XCTUnwrap(engine.activeTimerItemForBroadcast)
        XCTAssertNil(broadcast.details?.htmlDetails)
        XCTAssertTrue(broadcast.details?.itemTimes.isEmpty ?? false)
        XCTAssertNotNil(engine.activeTimerItem?.details?.htmlDetails)
    }

    func testPlanContextRefreshSaveAndClear() async {
        let engine = makeEngine([item("a")])
        engine.pcoChangeTracking.fetchContext = { _, planId in PCOPlanContext(planId: planId, serviceTypeId: "st", title: "Easter") }

        await engine.checkPCOForChanges()
        XCTAssertEqual(engine.pcoPlanContext?.title, "Easter")
        XCTAssertEqual(engine.makeDocument().pcoPlanContext?.title, "Easter")

        engine.importFlow(title: "Manual", items: [PCOTimerItem(title: "Local")])
        XCTAssertNil(engine.pcoPlanContext)

        engine.pcoChangeTracking.fetchContext = nil
        var document = engine.makeDocument()
        document.planItems = [item("a")]
        document.pcoPlanContext = PCOPlanContext(planId: "p", serviceTypeId: "st", title: "Saved")
        engine.apply(document)
        XCTAssertEqual(engine.pcoPlanContext?.title, "Saved")

        document.pcoPlanContext = PCOPlanContext(planId: "other", serviceTypeId: "st")
        engine.apply(document)
        XCTAssertNil(engine.pcoPlanContext)

        document.pcoPlanContext = PCOPlanContext(planId: "p", serviceTypeId: "st")
        engine.apply(document)
        engine.resetToNewDocument()
        XCTAssertNil(engine.pcoPlanContext)
    }
}
