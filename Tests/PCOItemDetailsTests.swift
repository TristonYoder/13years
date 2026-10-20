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
        var rich = item("a", key: "G")
        rich.details?.htmlDetails = "<p>lyrics</p>"
        rich.details?.itemTimes = [PCOItemTimeInfo(id: "t")]
        let engine = makeEngine([rich])
        XCTAssertNil(engine.activeTimerItemForBroadcast?.details)
        engine.roles[0].pagerFields = [.key]
        let broadcast = try XCTUnwrap(engine.activeTimerItemForBroadcast)
        XCTAssertEqual(broadcast.details?.displayKey, "G")
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

private final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func record(_ entry: String) {
        lock.lock()
        entries.append(entry)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries.sorted()
    }
}

final class PCOItemLeaderTests: XCTestCase {
    private func json(_ text: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    }

    private let itemsJSON = """
    {
      "data": [
        {"type": "Item", "id": "1", "attributes": {"title": "Sermon", "item_type": "item", "length": 1200},
         "relationships": {"item_assignments": {"data": [
           {"type": "ItemAssignment", "id": "a1"}, {"type": "ItemAssignment", "id": "a2"},
           {"type": "ItemAssignment", "id": "a3"}, {"type": "ItemAssignment", "id": "a4"}]}}},
        {"type": "Item", "id": "2", "attributes": {"title": "Prayer", "item_type": "item", "length": 60},
         "relationships": {"item_assignments": {"data": []}}}
      ],
      "included": [
        {"type": "ItemAssignment", "id": "a1", "attributes": {"assignable_type": "Person"}, "relationships": {"assignable": {"data": {"type": "Person", "id": "p1"}}}},
        {"type": "ItemAssignment", "id": "a2", "attributes": {"assignable_type": "Person"}, "relationships": {"assignable": {"data": {"type": "Person", "id": "p2"}}}},
        {"type": "ItemAssignment", "id": "a3", "attributes": {"assignable_type": "TeamPosition"}, "relationships": {"assignable": {"data": {"type": "TeamPosition", "id": "tp9"}}}},
        {"type": "ItemAssignment", "id": "a4", "attributes": {"assignable_type": "Person"}, "relationships": {"assignable": {"data": {"type": "Person", "id": "p1"}}}}
      ]
    }
    """

    private func parsedItems() -> [PCOTimerItem] {
        PCOClient.parsePlanItems(json(itemsJSON), serviceTypeId: "st", planId: "p")
    }

    private func team() -> [PCOPlanPersonInfo] {
        [PCOPlanPersonInfo(id: "pp1", personId: "p1", name: "Mara Lopez", photoThumbnailURL: "https://example.com/mara.png")]
    }

    private func resolve(
        _ items: [PCOTimerItem],
        resolver: PCOLeaderResolver = PCOLeaderResolver(),
        log: CallLog = CallLog(),
        people: [String: PCOLeaderIdentity] = [:],
        missing: Set<String> = []
    ) async -> [PCOTimerItem] {
        let team = team()
        return await resolver.resolve(
            items,
            loadTeam: { log.record("team"); return team },
            fetchPerson: { id in
                log.record("person:\(id)")
                if missing.contains(id) { throw NSError(domain: "PCOClient", code: 404) }
                return people[id]
            },
            fetchPosition: { id in
                log.record("position:\(id)")
                return id == "tp9" ? "Teaching Pastor" : nil
            }
        )
    }

    func testParsesItemAssignmentsAndDeduplicates() {
        let items = parsedItems()
        let leaders = items[0].details?.leaders ?? []
        XCTAssertEqual(leaders.map(\.personId), ["p1", "p2", nil])
        XCTAssertEqual(leaders.last?.teamPositionId, "tp9")
        XCTAssertTrue(items[1].details?.leaders.isEmpty ?? false)
        XCTAssertTrue(PCOClient.planItemsInclude.contains("item_assignments"))
    }

    func testResolvesFromTeamMembersBeforeFetchingPeople() async {
        let log = CallLog()
        let people = ["p2": PCOLeaderIdentity(name: "Jon Reyes", firstName: "Jon", photoThumbnailURL: nil)]
        let resolved = await resolve(parsedItems(), log: log, people: people)
        let leaders = resolved[0].details?.leaders ?? []
        XCTAssertEqual(leaders.map(\.name), ["Mara Lopez", "Jon Reyes", "Teaching Pastor"])
        XCTAssertEqual(leaders[0].firstName, "Mara")
        XCTAssertEqual(leaders[0].photoThumbnailURL, "https://example.com/mara.png")
        XCTAssertEqual(log.all, ["person:p2", "position:tp9", "team"])
    }

    func testTeamMembersCoverEveryoneSoNothingIsFetched() async {
        var items = parsedItems()
        items[0].details?.leaders = [PCOItemLeader(personId: "p1", name: "")]
        let log = CallLog()
        let resolved = await resolve(items, log: log)
        XCTAssertEqual(resolved[0].details?.leaders.map(\.name), ["Mara Lopez"])
        XCTAssertEqual(log.all, ["team"])
    }

    func testMissingPersonIsDroppedAndNotRefetched() async {
        let resolver = PCOLeaderResolver()
        let log = CallLog()
        let first = await resolve(parsedItems(), resolver: resolver, log: log, missing: ["p2"])
        XCTAssertEqual(first[0].details?.leaders.map(\.name), ["Mara Lopez", "Teaching Pastor"])
        let second = await resolve(parsedItems(), resolver: resolver, log: log, missing: ["p2"])
        XCTAssertEqual(second[0].details?.leaders, first[0].details?.leaders)
        XCTAssertEqual(log.all.filter { $0.hasPrefix("person:") }.count, 1)
        XCTAssertEqual(log.all.filter { $0 == "team" }.count, 1)
    }

    func testPersonIdentityParsingKeepsOnlyHTTPSPhotos() {
        let secure = PCOClient.parsePersonIdentity(json(#"{"data": {"attributes": {"first_name": "Jon", "full_name": "Jon Reyes", "photo_thumbnail_url": "https://example.com/j.png"}}}"#))
        XCTAssertEqual(secure, PCOLeaderIdentity(name: "Jon Reyes", firstName: "Jon", photoThumbnailURL: "https://example.com/j.png"))
        let insecure = PCOClient.parsePersonIdentity(json(#"{"data": {"attributes": {"full_name": "Jon Reyes", "photo_thumbnail_url": "http://example.com/j.png"}}}"#))
        XCTAssertNil(insecure?.photoThumbnailURL)
        XCTAssertEqual(insecure?.firstName, "Jon")
        XCTAssertNil(PCOItemLeader(name: "A", photoThumbnailURL: "http://example.com/a.png").photoURL)
    }

    func testTeamParsingReadsPhotoThumbnail() {
        let parsed = PCOClient.parseTeam(json(#"{"data": [{"type": "PlanPerson", "id": "pp", "attributes": {"name": "Mara Lopez", "photo_thumbnail": "https://example.com/m.png", "status": "C"}, "relationships": {"person": {"data": {"type": "Person", "id": "p1"}}}}]}"#))
        XCTAssertEqual(parsed.first?.photoThumbnailURL, "https://example.com/m.png")
        XCTAssertEqual(parsed.first?.personId, "p1")
    }

    func testBackCompatDecoding() throws {
        let details = try JSONDecoder().decode(PCOItemDetails.self, from: Data(#"{"servicePosition": "pre"}"#.utf8))
        XCTAssertTrue(details.leaders.isEmpty)
        let sparse = try JSONDecoder().decode(PCOItemLeader.self, from: Data(#"{"personId": "p1", "name": "Mara Lopez"}"#.utf8))
        XCTAssertEqual(sparse.firstName, "Mara")
        XCTAssertNil(sparse.photoThumbnailURL)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PCOItemDetails())) as? [String: Any]
        XCTAssertNil(encoded?["leaders"])

        let withLeaders = PCOItemDetails(leaders: [PCOItemLeader(personId: "p1", name: "Mara Lopez", photoThumbnailURL: "https://example.com/m.png")])
        XCTAssertEqual(try JSONDecoder().decode(PCOItemDetails.self, from: JSONEncoder().encode(withLeaders)), withLeaders)
    }

    func testBroadcastTrimmedStripsLeaders() {
        let leaders = [PCOItemLeader(personId: "p1", name: "Mara Lopez", photoThumbnailURL: "https://example.com/m.png")]
        let item = PCOTimerItem(id: "i", title: "Sermon", details: PCOItemDetails(description: "Hi", keyName: "G", leaders: leaders))
        XCTAssertTrue(item.broadcastTrimmed.details?.leaders.isEmpty ?? false)
        let withoutLeader = Set(PagerItemField.allCases).subtracting([.leader])
        XCTAssertTrue(item.broadcastTrimmed(fields: withoutLeader).details?.leaders.isEmpty ?? true)
        let onlyLeaders = PCOTimerItem(id: "j", title: "Prayer", details: PCOItemDetails(leaders: leaders))
        XCTAssertNil(onlyLeaders.broadcastTrimmed(fields: withoutLeader).details)
        let slim = onlyLeaders.broadcastTrimmed(fields: [.leader]).details?.leaders
        XCTAssertEqual(slim?.map(\.firstName), ["Mara"])
        XCTAssertNil(slim?.first?.photoThumbnailURL)
        XCTAssertNil(slim?.first?.personId)
        XCTAssertEqual(onlyLeaders.broadcastTrimmed.details, PCOItemDetails())
    }

    func testLeaderChangesDoNotRaiseAPendingChangesBanner() {
        let base = PCOTimerItem(id: "i", title: "Sermon", details: PCOItemDetails())
        var changed = base
        changed.details?.leaders = [PCOItemLeader(personId: "p1", name: "Mara Lopez")]
        XCTAssertTrue(PCOPlanDiff.changes(from: [base], to: [changed]).isEmpty)
    }

    func testBylineFormatting() {
        let mara = PCOItemLeader(personId: "1", name: "Mara Lopez")
        let jon = PCOItemLeader(personId: "2", name: "Jon Reyes")
        let ana = PCOItemLeader(personId: "3", name: "Ana Diaz")
        XCTAssertNil(PCOItemLeader.byline([]))
        XCTAssertEqual(PCOItemLeader.bylineNames([mara]), "Mara")
        XCTAssertEqual(PCOItemLeader.bylineNames([mara, jon]), "Mara & Jon")
        XCTAssertEqual(PCOItemLeader.bylineNames([mara, jon, ana]), "Mara + 2")
        XCTAssertEqual(PCOItemLeader.byline([mara, jon]), "Led by Mara & Jon")
        XCTAssertEqual(mara.initials, "ML")
        XCTAssertEqual(PCOItemLeader(teamPositionId: "t", name: "Teaching Pastor", firstName: "Teaching Pastor").bylineName, "Teaching Pastor")
    }

    func testNotePillSymbolMapping() {
        let expectations: [(String, String)] = [
            ("Audio", "speaker.wave.2"), ("Sound Cues", "speaker.wave.2"), ("Lighting", "lightbulb"),
            ("Video", "video"), ("Camera 2", "video"), ("Images", "video"),
            ("Media", "photo.on.rectangle"), ("Slides", "photo.on.rectangle"), ("Resolume", "photo.on.rectangle"), ("ProPresenter", "photo.on.rectangle"),
            ("Stage", "figure.stand"), ("Backstage", "figure.stand"),
            ("Director", "megaphone"), ("Producer Notes", "megaphone"),
            ("Timecode", "timer"), ("TC", "timer"), ("Watch", "note.text"), ("Notes", "note.text"),
        ]
        for (category, symbol) in expectations {
            XCTAssertEqual(RunSheetNotePill.symbolName(forCategory: category), symbol, category)
        }
    }

    func testNotePillsFollowColumnVisibility() {
        let item = PCOTimerItem(id: "i", title: "Song", notes: ["Audio": "Reverb up", "Lighting": "", "Stage": "Walk on left"])
        XCTAssertEqual(item.runSheetNotePills(layout: RunSheetLayoutSettings()).map(\.category), ["Audio", "Stage"])
        let hidden = RunSheetLayoutSettings(hiddenColumns: ["note-Audio"])
        XCTAssertEqual(item.runSheetNotePills(layout: hidden).map(\.category), ["Stage"])
        XCTAssertEqual(item.runSheetNotePills(layout: hidden).first?.text, "Walk on left")
    }
}

final class HTMLAttributedConverterTests: XCTestCase {
    private func convert(_ html: String) -> AttributedString { HTMLAttributedConverter.attributedString(fromHTML: html) }
    private func plain(_ html: String) -> String { HTMLAttributedConverter.plainText(fromHTML: html) }

    private func run(_ string: AttributedString, containing word: String) -> AttributedString.Runs.Run? {
        string.runs.first { String(string[$0.range].characters).contains(word) }
    }

    func testInlineColorsAndHighlights() {
        let html = #"<p><span style="color: #ff0000">Red</span> <span style="background-color: rgb(255, 255, 0)">Marked</span> <font color="blue">Blue</font> <mark>Mark</mark></p>"#
        let result = convert(html)
        XCTAssertEqual(run(result, containing: "Red")?[HTMLForegroundColorKey.self], "#FF0000FF")
        XCTAssertEqual(run(result, containing: "Marked")?[HTMLBackgroundColorKey.self], "#FFFF00FF")
        XCTAssertEqual(run(result, containing: "Blue")?[HTMLForegroundColorKey.self], "#0000FFFF")
        XCTAssertNotNil(run(result, containing: "Mark")?[HTMLBackgroundColorKey.self])
        XCTAssertEqual(String(result.characters), "Red Marked Blue Mark")
    }

    func testNestedStylesInheritAndOverride() {
        let html = #"<span style="color:#00ff00;font-weight:bold">Green <span style="font-weight:normal;font-style:italic">plain</span> bold</span> after"#
        let result = convert(html)
        XCTAssertEqual(run(result, containing: "plain")?[HTMLForegroundColorKey.self], "#00FF00FF")
        XCTAssertFalse(run(result, containing: "plain")?.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false)
        XCTAssertTrue(run(result, containing: "plain")?.inlinePresentationIntent?.contains(.emphasized) ?? false)
        XCTAssertTrue(run(result, containing: "bold")?.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false)
        XCTAssertNil(run(result, containing: "after")?[HTMLForegroundColorKey.self])
    }

    func testStrikethroughSizesMonospaceAndBaseline() {
        let result = convert("<s>Gone</s> <span style=\"font-size: 26px\">Big</span> <code>TC 1</code> E=mc<sup>2</sup> H<sub>2</sub>O <small>tiny</small>")
        XCTAssertEqual(run(result, containing: "Gone")?[HTMLStrikethroughKey.self], true)
        XCTAssertEqual(run(result, containing: "Big")?[HTMLFontScaleKey.self], 2)
        XCTAssertEqual(run(result, containing: "TC 1")?[HTMLMonospaceKey.self], true)
        XCTAssertEqual(result.runs.first { String(result[$0.range].characters) == "2" && $0[HTMLBaselineKey.self] == 1 }.map { _ in true }, true)
        XCTAssertNotNil(result.runs.first { $0[HTMLBaselineKey.self] == -1 })
        XCTAssertEqual(run(result, containing: "tiny")?[HTMLFontScaleKey.self], 0.85)
    }

    func testSmallHeadingsRulesAndTables() {
        let result = convert("<h5>Cue</h5><hr><table><tr><th>Who</th><td>Host</td></tr></table>")
        XCTAssertEqual(result.runs.compactMap { $0[HTMLHeadingLevelKey.self] }, [5])
        XCTAssertTrue(String(result.characters).contains("\u{2500}"))
        XCTAssertTrue(String(result.characters).contains("Who   Host"))
        XCTAssertTrue(run(result, containing: "Who")?.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false)
    }

    func testCSSColorParsing() {
        XCTAssertEqual(HTMLColor(css: "#abc")?.hex, "#AABBCCFF")
        XCTAssertEqual(HTMLColor(css: "rgba(0, 0, 0, 0.5)")?.hex, "#00000080")
        XCTAssertEqual(HTMLColor(css: "Navy")?.hex, "#000080FF")
        XCTAssertNil(HTMLColor(css: "inherit"))
        XCTAssertGreaterThan(HTMLColor.contrast(HTMLColor(css: "black")!, HTMLColor(css: "white")!), 20)
    }

    func testPlainTextPassesThroughWithLineBreaks() {
        XCTAssertEqual(plain("Walk on left\nExit right"), "Walk on left\nExit right")
        XCTAssertEqual(plain("Just words"), "Just words")
        XCTAssertEqual(plain("1 < 2 and 3 > 2"), "1 < 2 and 3 > 2")
    }

    func testParagraphsBreaksAndHeadings() {
        XCTAssertEqual(plain("<p>One</p><p>Two<br>three</p>"), "One\n\nTwo\nthree")
        XCTAssertEqual(plain("<div>A</div><div>B</div>"), "A\nB")
        let heading = convert("<h2>Verse 1</h2><p>Line</p>")
        XCTAssertEqual(String(heading.characters), "Verse 1\n\nLine")
        let levels = heading.runs.compactMap { $0[HTMLHeadingLevelKey.self] }
        XCTAssertEqual(levels, [2])
        XCTAssertTrue(heading.runs.first?.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false)
    }

    func testListsBulletsAndNumbers() {
        XCTAssertEqual(plain("<ul><li>Alpha</li><li>Beta</li></ul>"), "\u{2022} Alpha\n\u{2022} Beta")
        XCTAssertEqual(plain("<ol><li>First</li><li>Second</li></ol>"), "1. First\n2. Second")
        XCTAssertEqual(plain("<ul><li>Top<ul><li>Inner</li></ul></li></ul>"), "\u{2022} Top\n    \u{2022} Inner")
    }

    func testEntitiesAreDecoded() {
        XCTAssertEqual(plain("<p>Tom &amp; Jerry &lt;3 &quot;hi&quot; &#65;&#x42; &mdash; caf&eacute;&nbsp;x</p>"), "Tom & Jerry <3 \"hi\" AB \u{2014} caf&eacute; x")
    }

    func testNestedBoldItalicAndUnderline() {
        let text = convert("<p>a <b>bold <i>both</i></b> <u>under</u> <em>it</em></p>")
        XCTAssertEqual(String(text.characters), "a bold both under it")
        var seen: [String: InlinePresentationIntent] = [:]
        var underlined = ""
        for run in text.runs {
            let piece = String(text[run.range].characters)
            if let intent = run.inlinePresentationIntent { seen[piece] = intent }
            if run[HTMLUnderlineKey.self] == true { underlined += piece }
        }
        XCTAssertEqual(seen["bold "], .stronglyEmphasized)
        XCTAssertEqual(seen["both"], [.stronglyEmphasized, .emphasized])
        XCTAssertEqual(seen["it"], .emphasized)
        XCTAssertEqual(underlined, "under")
    }

    func testOnlyHTTPLinksAreKept() {
        let text = convert(#"<a href="https://example.com/a?x=1&amp;y=2">site</a> <a href="javascript:alert(1)">bad</a> <a href="mailto:a@b.c">mail</a>"#)
        XCTAssertEqual(String(text.characters), "site bad mail")
        let links = text.runs.compactMap { $0.link }
        XCTAssertEqual(links, [URL(string: "https://example.com/a?x=1&y=2")!])
    }

    func testScriptStyleImagesAndUnknownTagsAreStripped() {
        XCTAssertEqual(plain(#"<p>Hi<script>alert("x")</script> there<style>p{color:red}</style><img src="https://evil.example/p.png"><iframe src="https://evil.example"></iframe>!</p>"#), "Hi there!")
        XCTAssertEqual(plain("<custom-tag>kept <span class=\"x\">text</span></custom-tag><object>gone</object>"), "kept text")
        XCTAssertEqual(plain("<!-- hidden -->visible"), "visible")
        XCTAssertEqual(plain("<p>open <script>never closed"), "open")
    }

    func testBlockquoteIsIndentedAndItalic() {
        let text = convert("<p>Before</p><blockquote>Quoted</blockquote>")
        XCTAssertEqual(String(text.characters), "Before\n\n    Quoted")
        XCTAssertTrue(text.runs.contains { $0.inlinePresentationIntent == .emphasized })
    }

    func testWhitespaceCollapsesLikeHTML() {
        XCTAssertEqual(plain("<p>  many   spaces\n and\tlines  </p>"), "many spaces and lines")
    }
}

final class RunSheetLayoutDetailsTests: XCTestCase {
    func testDetailsFieldsRoundTripAndDefaults() throws {
        let layout = RunSheetLayoutSettings(sidePaneTab: "details", detailsTextScale: 1.3, detailsUnpinned: true)
        let decoded = try JSONDecoder().decode(RunSheetLayoutSettings.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(decoded, layout)
        XCTAssertTrue(decoded.showsDetailsTab)
        XCTAssertFalse(decoded.followsLiveItem)
        XCTAssertEqual(decoded.effectiveDetailsTextScale, 1.3, accuracy: 0.0001)

        let legacy = try JSONDecoder().decode(RunSheetLayoutSettings.self, from: Data(#"{"hiddenColumns": ["drift"]}"#.utf8))
        XCTAssertFalse(legacy.showsDetailsTab)
        XCTAssertTrue(legacy.followsLiveItem)
        XCTAssertEqual(legacy.effectiveDetailsTextScale, 1.0)
        XCTAssertEqual(RunSheetLayoutSettings(detailsTextScale: 9).effectiveDetailsTextScale, 2.0)
        XCTAssertTrue(RunSheetLayoutSettings().isDefault)
    }

    func testHTMLDetailsAreNotBroadcast() {
        let item = PCOTimerItem(id: "i", title: "Sermon", details: PCOItemDetails(htmlDetails: "<p>Script</p>"))
        XCTAssertNil(item.broadcastTrimmed.details?.htmlDetails)
        XCTAssertNil(item.broadcastTrimmed(fields: Set(PagerItemField.allCases)).details?.htmlDetails)
    }
}
