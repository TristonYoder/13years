// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class DocumentLoadRouterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearPersistedState()
    }

    override func tearDown() {
        clearPersistedState()
        super.tearDown()
    }

    private func clearPersistedState() {
        for key in ["persistedFlow", "persistedRoles", "waypoints", "serviceSchedules", "recentMessages", "hourFormatThreshold"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func put(_ engine: CueEngine, _ body: ControlAPIRequests.DocumentLoadBody, method: String = "PUT") throws -> HTTPResponse {
        try put(engine, raw: ControlAPIJSON.encoder.encode(body), method: method)
    }

    private func put(_ engine: CueEngine, raw: Data, method: String = "PUT") -> HTTPResponse {
        ControlAPIRouter(engine: engine).handle(HTTPRequest(method: method, path: "/v1/document", body: raw))
    }

    private func richItems() -> [PCOTimerItem] {
        [
            PCOTimerItem(id: "h", title: "Pre-Service", itemType: "Header", lengthInSeconds: 0),
            PCOTimerItem(
                id: "a", title: "Welcome", itemType: "Item", lengthInSeconds: 120, elapsedSeconds: 7,
                notes: ["Lights": "dim"], noteIds: ["Lights": "n1"],
                pcoServiceTypeId: "st", pcoPlanId: "plan", isDurationActual: true, waypointIds: ["w1"]
            ),
            PCOTimerItem(id: "b", title: "Song", itemType: "Song", lengthInSeconds: 270, waypointIds: ["w1", "w2"])
        ]
    }

    func testDocumentModeKeepsEveryFieldAndActiveIndex() throws {
        let engine = CueEngine()
        let waypoints = [Waypoint(id: "w1", name: "Open"), Waypoint(id: "w2", name: "Close")]
        let body = ControlAPIRequests.DocumentLoadBody(
            items: richItems(),
            activeItemIndex: 2,
            roles: [RoleCue(id: "r1", name: "Host", personName: "Sam", state: .go, assignedNoteCategories: ["Lights"])],
            replaceRoles: true,
            waypoints: waypoints,
            settings: .init(hourFormatThreshold: "never")
        )
        let response = try put(engine, body)
        XCTAssertEqual(response.status, 200)

        let state = try ControlAPIJSON.decoder.decode(ControlAPIState.self, from: response.body)
        XCTAssertEqual(state.plan.items.count, 3)
        XCTAssertEqual(state.plan.activeItemIndex, 2)

        XCTAssertEqual(engine.planItems.map(\.id), ["h", "a", "b"])
        let welcome = try XCTUnwrap(engine.planItems.first { $0.id == "a" })
        XCTAssertEqual(welcome.notes, ["Lights": "dim"])
        XCTAssertEqual(welcome.noteIds, ["Lights": "n1"])
        XCTAssertEqual(welcome.pcoServiceTypeId, "st")
        XCTAssertEqual(welcome.pcoPlanId, "plan")
        XCTAssertTrue(welcome.isDurationActual)
        XCTAssertEqual(welcome.waypointIds, ["w1"])
        XCTAssertEqual(welcome.elapsedSeconds, 7)
        XCTAssertEqual(engine.planItems.last?.waypointIds, ["w1", "w2"])
        XCTAssertEqual(engine.waypoints, waypoints)
        XCTAssertEqual(engine.activeItemIndex, 2)
        XCTAssertEqual(engine.activeTimerItem?.id, "b")
        XCTAssertEqual(engine.hourFormatThreshold, .never)
        XCTAssertEqual(engine.roles.map(\.id), ["r1"])
        XCTAssertEqual(engine.roles.first?.personName, "Sam")
        XCTAssertEqual(engine.roles.first?.assignedNoteCategories, ["Lights"])
        XCTAssertEqual(engine.roles.first?.state, .off)
        XCTAssertTrue(engine.planItems.allSatisfy { !$0.isRunning })
    }

    func testPlanModeMatchesImportFlow() throws {
        let engine = CueEngine()
        let reference = CueEngine()
        reference.importFlow(title: "Sunday", items: richItems())

        let response = try put(engine, ControlAPIRequests.DocumentLoadBody(title: "Sunday", items: richItems()))
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(engine.planItems, reference.planItems)
        XCTAssertEqual(engine.activeItemIndex, 1)
        XCTAssertEqual(engine.activeTimerItem?.id, "a")
        XCTAssertEqual(engine.planItems.first?.servicePlanTitle, "Sunday")
        XCTAssertEqual(engine.planItems[1].notes, ["Lights": "dim"])
        XCTAssertEqual(engine.planItems[1].elapsedSeconds, 0)
    }

    func testRolesReplacedOnlyWhenAskedAndOtherwiseMerged() throws {
        let engine = CueEngine()
        engine.roles = [RoleCue(id: "keep", name: "Keep", state: .go), RoleCue(id: "other", name: "Other")]
        let incoming = [RoleCue(id: "keep", name: "Renamed", personName: "Pat", assignedNoteCategories: ["A"]), RoleCue(id: "new", name: "New", state: .go)]

        var body = ControlAPIRequests.DocumentLoadBody(items: [PCOTimerItem(id: "i", title: "I")], activeItemIndex: 0, roles: incoming, replaceRoles: false)
        XCTAssertEqual(try put(engine, body).status, 200)
        XCTAssertEqual(engine.roles.map(\.id), ["keep", "other", "new"])
        XCTAssertEqual(engine.roles[0].name, "Renamed")
        XCTAssertEqual(engine.roles[0].personName, "Pat")
        XCTAssertEqual(engine.roles[0].assignedNoteCategories, ["A"])
        XCTAssertEqual(engine.roles[0].state, .go)
        XCTAssertEqual(engine.roles[2].state, .off)

        body.replaceRoles = true
        XCTAssertEqual(try put(engine, body).status, 200)
        XCTAssertEqual(engine.roles.map(\.id), ["keep", "new"])
        XCTAssertTrue(engine.roles.allSatisfy { $0.state == .off })

        engine.roles = [RoleCue(id: "solo", name: "Solo", state: .go)]
        XCTAssertEqual(try put(engine, ControlAPIRequests.DocumentLoadBody(items: [PCOTimerItem(id: "i", title: "I")])).status, 200)
        XCTAssertEqual(engine.roles.map(\.id), ["solo"])
        XCTAssertEqual(engine.roles.first?.state, .go)
    }

    func testEmptyItemsClearThePlan() throws {
        let engine = CueEngine()
        engine.importFlow(title: "Old", items: richItems())
        XCTAssertEqual(try put(engine, ControlAPIRequests.DocumentLoadBody(items: [], activeItemIndex: 0)).status, 200)
        XCTAssertTrue(engine.planItems.isEmpty)
        XCTAssertNil(engine.activeTimerItem)
    }

    func testPostIsAcceptedAndOtherMethodsAreNot() throws {
        let engine = CueEngine()
        let body = ControlAPIRequests.DocumentLoadBody(items: [PCOTimerItem(id: "i", title: "I")], activeItemIndex: 0)
        XCTAssertEqual(try put(engine, body, method: "POST").status, 200)
        XCTAssertEqual(try put(engine, body, method: "GET").status, 405)
        XCTAssertEqual(try put(engine, body, method: "DELETE").status, 405)
    }

    func testRejectsBadBodies() throws {
        let engine = CueEngine()
        engine.importFlow(title: "Keep", items: [PCOTimerItem(id: "keep", title: "Keep")])

        XCTAssertEqual(put(engine, raw: Data()).status, 400)
        XCTAssertEqual(put(engine, raw: Data("{".utf8)).status, 400)
        XCTAssertEqual(put(engine, raw: Data("{\"title\":\"x\"}".utf8)).status, 400)

        let one = PCOTimerItem(id: "i", title: "I")
        XCTAssertEqual(try put(engine, .init(items: [one], activeItemIndex: 1)).status, 400)
        XCTAssertEqual(try put(engine, .init(items: [one], activeItemIndex: -1)).status, 400)
        XCTAssertEqual(try put(engine, .init(items: [one, one])).status, 400)
        XCTAssertEqual(try put(engine, .init(items: [one], settings: .init(hourFormatThreshold: "bogus"))).status, 400)
        XCTAssertEqual(try put(engine, .init(title: String(repeating: "x", count: ContentLimits.title + 1), items: [one])).status, 400)
        XCTAssertEqual(try put(engine, .init(items: [PCOTimerItem(id: "t", title: String(repeating: "x", count: ContentLimits.title + 1))])).status, 400)
        XCTAssertEqual(try put(engine, .init(items: [PCOTimerItem(id: "n", title: "N", notes: ["a": String(repeating: "x", count: ContentLimits.noteValue + 1)])])).status, 400)
        XCTAssertEqual(try put(engine, .init(items: [one], roles: [RoleCue(id: "d", name: "A"), RoleCue(id: "d", name: "B")])).status, 400)

        XCTAssertEqual(engine.planItems.map(\.id), ["keep"])
    }

    func testEnforcesCountLimitsWith409() throws {
        let engine = CueEngine()
        let tooMany = (0...ContentLimits.maxPlanItems).map { PCOTimerItem(id: "i\($0)", title: "I") }
        XCTAssertEqual(try put(engine, .init(items: tooMany)).status, 409)
        let tooManyRoles = (0...ContentLimits.maxRoles).map { RoleCue(id: "r\($0)", name: "R") }
        XCTAssertEqual(try put(engine, .init(items: [], roles: tooManyRoles)).status, 409)
        let tooManyWaypoints = (0...ContentLimits.maxWaypoints).map { Waypoint(id: "w\($0)", name: "W") }
        XCTAssertEqual(try put(engine, .init(items: [], waypoints: tooManyWaypoints)).status, 409)
        XCTAssertTrue(engine.planItems.isEmpty || engine.planItems.count <= ContentLimits.maxPlanItems)
    }

    func testSocketOpDocumentLoadsToo() throws {
        let engine = CueEngine()
        let body = try ControlAPIJSON.encoder.encode(ControlAPIRequests.DocumentLoadBody(items: [PCOTimerItem(id: "s", title: "S")], activeItemIndex: 0))
        let command = try JSONDecoder().decode(ControlAPICommand.self, from: Data("{\"id\":\"1\",\"op\":\"document\",\"body\":\(String(data: body, encoding: .utf8)!)}".utf8))
        let reply = ControlAPIRouter(engine: engine).handleCommand(command)
        XCTAssertEqual(reply.status, 200)
        XCTAssertEqual(engine.planItems.map(\.id), ["s"])
    }
}

@MainActor
final class DocumentLoadMirrorTests: XCTestCase {
    private func decodeBody(_ command: RemoteCommand?) throws -> ControlAPIRequests.DocumentLoadBody {
        guard case .loadDocument(let data)? = command else {
            XCTFail("Expected loadDocument, got \(String(describing: command))")
            throw CocoaError(.coderInvalidValue)
        }
        return try ControlAPIJSON.decoder.decode(ControlAPIRequests.DocumentLoadBody.self, from: data)
    }

    private func document() -> ProducerDocument {
        ProducerDocument(
            roles: [RoleCue(id: "r1", name: "Host", personName: "Sam", assignedNoteCategories: ["Lights"])],
            selectedRoleIds: ["r1"],
            waypoints: [Waypoint(id: "w1", name: "Open")],
            serviceSchedules: [ServiceSchedule(id: "s1", title: "Sunday", startsAt: Date(timeIntervalSince1970: 1_800_000_000), recurrence: .weekly)],
            planItems: [
                PCOTimerItem(id: "a", title: "Welcome", lengthInSeconds: 90, notes: ["Lights": "dim"], noteIds: ["Lights": "n1"], pcoServiceTypeId: "st", pcoPlanId: "p", isDurationActual: true, waypointIds: ["w1"]),
                PCOTimerItem(id: "b", title: "Song", itemType: "Song")
            ],
            activeItemIndex: 1,
            settings: .init(hourFormatThreshold: .over60Minutes, pcoDefaultServiceTypeId: nil, plotipharRelayHost: "")
        )
    }

    func testCommandMapsToPutDocumentAndIsNotRetriedBlindly() {
        let command = RemoteCommand.loadDocument(body: Data("{}".utf8))
        XCTAssertEqual(command.request.method, "PUT")
        XCTAssertEqual(command.request.path, "/v1/document")
        XCTAssertEqual(command.request.body, Data("{}".utf8))
        XCTAssertFalse(command.isIdempotent)
    }

    func testOpeningADocumentInMirrorSendsItWholeAndLeavesMirrorUntouched() throws {
        let sink = RecordingCommands()
        let engine = CueEngine(mirroring: sink)
        engine.apply(remoteState: RemoteFixtures.state(rev: 1))
        let before = (engine.roles, engine.planItems, engine.waypoints, engine.serviceSchedules, engine.activeItemIndex)

        try engine.loadDocumentIntoRemote(document())

        XCTAssertEqual(sink.sent.count, 1)
        let body = try decodeBody(sink.sent.first)
        XCTAssertEqual(body.items.map(\.id), ["a", "b"])
        XCTAssertEqual(body.items[0].notes, ["Lights": "dim"])
        XCTAssertEqual(body.items[0].noteIds, ["Lights": "n1"])
        XCTAssertEqual(body.items[0].pcoPlanId, "p")
        XCTAssertEqual(body.items[0].waypointIds, ["w1"])
        XCTAssertTrue(body.items[0].isDurationActual)
        XCTAssertEqual(body.activeItemIndex, 1)
        XCTAssertEqual(body.replaceRoles, true)
        XCTAssertEqual(body.roles?.first?.personName, "Sam")
        XCTAssertEqual(body.roles?.first?.assignedNoteCategories, ["Lights"])
        XCTAssertEqual(body.waypoints?.map(\.name), ["Open"])
        XCTAssertEqual(body.schedules?.first?.recurrence, .weekly)
        XCTAssertEqual(body.settings?.hourFormatThreshold, "over60Minutes")
        XCTAssertEqual(body.selectedRoleIds, ["r1"])

        XCTAssertEqual(before.0, engine.roles)
        XCTAssertEqual(before.1, engine.planItems)
        XCTAssertEqual(before.2, engine.waypoints)
        XCTAssertEqual(before.3, engine.serviceSchedules)
        XCTAssertEqual(before.4, engine.activeItemIndex)
    }

    func testImportFlowInMirrorSendsFullFidelityPlan() throws {
        let sink = RecordingCommands()
        let engine = CueEngine(mirroring: sink)
        engine.apply(remoteState: RemoteFixtures.state(rev: 1))
        let items = [PCOTimerItem(id: "n", title: "A|B", itemType: "Song", lengthInSeconds: 125, notes: ["Lights": "x"], noteIds: ["Lights": "9"], pcoServiceTypeId: "st", pcoPlanId: "p", waypointIds: ["w1"])]

        engine.importFlow(title: "Sunday", items: items)

        let body = try decodeBody(sink.sent.last)
        XCTAssertEqual(body.title, "Sunday")
        XCTAssertNil(body.activeItemIndex)
        XCTAssertEqual(body.items.first?.title, "A|B")
        XCTAssertEqual(body.items.first?.notes, ["Lights": "x"])
        XCTAssertEqual(body.items.first?.noteIds, ["Lights": "9"])
        XCTAssertEqual(body.items.first?.waypointIds, ["w1"])
        XCTAssertEqual(engine.planItems.map(\.id), ["a", "b"])
        XCTAssertFalse(sink.sent.contains { if case .planImport = $0 { return true } else { return false } })
    }

    func testOversizedPlansAreRefusedLocally() {
        let sink = RecordingCommands()
        let engine = CueEngine(mirroring: sink)
        let huge = (0..<400).map { PCOTimerItem(id: "i\($0)", title: "T", notes: ["a": String(repeating: "x", count: ContentLimits.noteValue)]) }
        XCTAssertFalse(engine.loadPlanIntoRemote(title: nil, items: huge))
        XCTAssertTrue(sink.sent.isEmpty)
        XCTAssertNotNil(engine.pcoLastError)
    }

    func testSendingFromAnEngineThatIsNotAMirrorThrows() {
        let engine = CueEngine()
        XCTAssertThrowsError(try engine.loadDocumentIntoRemote(document())) { error in
            XCTAssertEqual(error as? RemoteLoadError, .notMirror)
        }
    }

    func testMirrorPCOActionsAreRemoteCommandsNotLocalFetches() {
        let sink = RecordingCommands()
        let engine = CueEngine(mirroring: sink)

        engine.setPlanFilter(.past)
        engine.clearPCOServiceTypeSelection()
        engine.selectPCOServiceType("st")
        engine.fetchPCOServiceTypes()
        engine.fetchPCOPlans()
        engine.loadNextService()
        engine.fetchPCOPlan(serviceTypeId: "st", planId: "p")
        engine.signOutOfPCO()

        XCTAssertEqual(sink.sent, [
            .pcoPlanFilter(PCOClient.PCOPlanFilter.past.rawValue),
            .pcoSelectServiceType(id: nil),
            .pcoSelectServiceType(id: "st"),
            .pcoRefreshServiceTypes,
            .pcoRefreshPlans,
            .planNextService,
            .pcoSync(serviceTypeId: "st", planId: "p"),
            .pcoSignOut
        ])
        XCTAssertNil(engine.pcoLastError)
    }

    func testMirrorEventTimeCommandsForwardToTheProducer() {
        let sink = RecordingCommands()
        let engine = CueEngine(mirroring: sink)
        var state = RemoteFixtures.state(rev: 1)
        state.eventTimes = .init(
            entries: [
                .init(id: "t1", name: nil, day: nil, startTime: TimeOfDay(hour: 9, minute: 0), displayName: "9:00", pcoPlanTimeId: nil),
                .init(id: "t2", name: "Late", day: .weekday(1), startTime: TimeOfDay(hour: 11, minute: 0), displayName: "11:00", pcoPlanTimeId: nil)
            ],
            liveId: "t1",
            nextId: "t2"
        )
        engine.apply(remoteState: state)

        XCTAssertEqual(engine.eventTimes.map(\.id), ["t1", "t2"])
        XCTAssertEqual(engine.eventTimes[1].day, .weekday(1))
        XCTAssertEqual(engine.nextEventTime?.id, "t2")

        engine.setLiveEventTime(id: "t2")
        engine.advanceToNextEventTime()
        engine.removeEventTime(id: "t1")
        engine.addEventTime(name: "Evening", day: .date(year: 2026, month: 10, day: 18), startTime: TimeOfDay(hour: 18, minute: 30))
        XCTAssertEqual(sink.sent, [
            .eventTimeLive(id: "t2"),
            .eventTimeNext,
            .eventTimeDelete(id: "t1"),
            .eventTimeCreate(name: "Evening", day: "2026-10-18", startTime: "18:30")
        ])
    }

    func testMirrorPCOStatusComesFromTheRemoteState() {
        let engine = CueEngine(mirroring: RecordingCommands())
        var state = RemoteFixtures.state(rev: 1)
        state.pco.isConnected = true
        state.pco.userName = "Remote Person"
        engine.apply(remoteState: state)
        XCTAssertTrue(engine.isPCOConnected)
        XCTAssertEqual(engine.pcoUserName, "Remote Person")
    }
}
