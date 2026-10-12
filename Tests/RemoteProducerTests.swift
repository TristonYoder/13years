// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

enum RemoteFixtures {
    static func stateJSON(
        rev: Int,
        roleName: String = "Host",
        selected: [String] = ["host"],
        timerElapsed: Int = 10,
        running: Bool = true,
        clients: Int = 1
    ) -> String {
        """
        {"rev":\(rev),"serverNowMs":1760000000000,"appMode":"PRODUCER_CONTROL",
        "network":{"isMasterServer":true,"isLANConnected":true,"isProducerLive":false,"hasSyncedWithProducer":false,"lanPort":13380,"relayEnabled":false,"relayHost":"r"},
        "roles":[{"id":"host","name":"\(roleName)","state":"OFF","lastUpdated":"2026-10-11T15:32:10Z","assignedNoteCategories":[]},
                 {"id":"band","name":"Band","state":"GO","lastUpdated":"2026-10-11T15:32:10Z","assignedNoteCategories":[]}],
        "selectedRoleIds":\(selected.map { "\"\($0)\"" }.joined(separator: ",").wrapped),
        "timer":\(timerJSON(elapsed: timerElapsed, running: running)),
        "plan":{"items":[\(itemJSON(id: "a", elapsed: 0, running: false)),\(itemJSON(id: "b", elapsed: 0, running: false))],"activeItemIndex":1,"isAtEndOfPlan":true,"canLoadNextService":false},
        "messages":[{"id":"m1","sender":"Producer","text":"hi","timestamp":"2026-10-11T15:32:10Z","isHighPriority":false}],
        "pco":{"isConnected":false,"isLiveSyncEnabled":false,"planFilter":"future","serviceTypes":[{"id":"st","name":"Sunday"}],"plans":[],"noteCategories":[]},
        "plotiphar":{"pairingState":"idle","assignmentSyncStatus":"notSynced","roles":[]},
        "settings":{"hourFormatThreshold":"over60Minutes","controlAPIPort":13390,"connectedAPIClients":\(clients)},
        "waypoints":[{"id":"w1","name":"Song 1","slug":"song-1"}],
        "schedules":{"entries":[{"id":"s1","title":"Sunday","startsAt":"2026-10-18T14:00:00Z","goLiveAt":"2026-10-18T13:30:00Z","goLiveOffsetSeconds":1800,"goLiveOffsetMinutes":30,"recurrence":"weekly","isEnabled":true}]}}
        """
    }

    static func itemJSON(id: String, elapsed: Int, running: Bool) -> String {
        "{\"id\":\"\(id)\",\"title\":\"Item \(id)\",\"itemType\":\"Item\",\"sequence\":1,\"lengthInSeconds\":300,\"elapsedSeconds\":\(elapsed),\"isRunning\":\(running),\"notes\":{},\"noteIds\":{},\"isDurationActual\":false,\"waypointIds\":[\"w1\"]}"
    }

    static func timerJSON(elapsed: Int, running: Bool, anchor: String? = nil) -> String {
        let anchorField = anchor.map { ",\"anchor\":\($0)" } ?? ""
        return "{\"item\":\(itemJSON(id: "b", elapsed: elapsed, running: running)),\"index\":1,\"isRunning\":\(running),\"remainingSeconds\":\(300 - elapsed),\"isOvertime\":false,\"formattedRemaining\":\"00:00\",\"isDurationActualForDisplay\":true\(anchorField)}"
    }

    static func event(_ name: String, _ payload: String) -> String {
        "{\"event\":\"\(name)\",\"data\":\(payload)}"
    }

    static func state(rev: Int, roleName: String = "Host") -> ControlAPIState {
        try! ControlAPIJSON.decoder.decode(ControlAPIState.self, from: Data(stateJSON(rev: rev, roleName: roleName).utf8))
    }
}

private extension String {
    var wrapped: String { "[\(self)]" }
}

@MainActor
final class RecordingCommands: RemoteProducerCommanding {
    var sent: [RemoteCommand] = []
    func send(_ command: RemoteCommand) { sent.append(command) }
}

final class RemoteEndpointTests: XCTestCase {
    func testParsesHostWithDefaultPort() {
        let endpoint = RemoteEndpoint.parse("producer.local")
        XCTAssertEqual(endpoint?.host, "producer.local")
        XCTAssertEqual(endpoint?.port, 13390)
    }

    func testParsesHostAndPort() {
        let endpoint = RemoteEndpoint.parse("  192.168.1.20:14000 ")
        XCTAssertEqual(endpoint?.host, "192.168.1.20")
        XCTAssertEqual(endpoint?.port, 14000)
    }

    func testParsesBracketedIPv6WithPort() {
        let endpoint = RemoteEndpoint.parse("[fe80::1]:14000")
        XCTAssertEqual(endpoint?.host, "fe80::1")
        XCTAssertEqual(endpoint?.port, 14000)
        XCTAssertEqual(endpoint?.url(path: "/v1/health")?.absoluteString, "http://[fe80::1]:14000/v1/health")
    }

    func testParsesBareIPv6AndBracketedWithoutPort() {
        XCTAssertEqual(RemoteEndpoint.parse("::1")?.port, 13390)
        XCTAssertEqual(RemoteEndpoint.parse("[::1]")?.host, "::1")
    }

    func testStripsSchemeAndPath() {
        let endpoint = RemoteEndpoint.parse("http://10.0.0.5:13390/v1/state")
        XCTAssertEqual(endpoint?.host, "10.0.0.5")
        XCTAssertEqual(endpoint?.socketURL?.absoluteString, "ws://10.0.0.5:13390/v1/socket")
    }

    func testRejectsInvalidAddresses() {
        for bad in ["", "   ", "host:", "host:0", "host:70000", "host:abc", "999.1.1.1", "a b", "[::1", "[::1]x", "[nope]:1", "a..b", "1:2:3", ":13390"] {
            XCTAssertNil(RemoteEndpoint.parse(bad), bad)
        }
    }
}

@MainActor
final class RemoteCommandTests: XCTestCase {
    private func json(_ request: RemoteCommand.Request) -> [String: Any]? {
        request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    func testRouteShapes() {
        XCTAssertEqual(RemoteCommand.cueSelected(.go).request.path, "/v1/cues/selected")
        XCTAssertEqual(json(RemoteCommand.cueSelected(.go).request)?["state"] as? String, "GO")
        XCTAssertEqual(RemoteCommand.cueRole(id: "a b", state: .standby).request.path, "/v1/roles/a%20b/cue")
        XCTAssertEqual(RemoteCommand.select(roleIds: ["x"]).request.method, "PUT")
        XCTAssertEqual(RemoteCommand.planItemRemove(id: "i").request.method, "DELETE")
        XCTAssertEqual(RemoteCommand.waypointRename(ref: "w", name: "N").request.method, "PATCH")
        XCTAssertEqual(RemoteCommand.clearMessages.request, .init(method: "DELETE", path: "/v1/messages", body: nil))
        XCTAssertEqual(RemoteCommand.pcoSelectServiceType(id: nil).request.body, Data("{\"id\":null}".utf8))
        XCTAssertNil(json(RemoteCommand.waypointAssign(ref: "w", itemId: nil).request)?["itemId"])
    }

    func testMirrorForwardsMutationsWithoutChangingLocalState() {
        let sink = RecordingCommands()
        let engine = CueEngine(mirroring: sink)
        engine.apply(remoteState: RemoteFixtures.state(rev: 1))
        let before = engine.roles

        engine.setCueForSelectedRoles(.go)
        engine.setCueForRole(id: "host", state: .standby)
        engine.clearAllCues()
        engine.toggleTimerRunning()
        engine.resetTimer()
        engine.adjustTimerRemainingTime(bySeconds: 30)
        engine.setTimerRemainingTime(seconds: 90)
        engine.setActiveTimerActualOverride(true)
        engine.nextPlanItem()
        engine.previousPlanItem(startTimer: false)
        engine.setActivePlanItem(id: "a")
        _ = engine.fireWaypoint("song-1")
        engine.sendMessage("hello", targetRoleId: "host")
        engine.clearActiveNotification()
        engine.clearMessageHistory()
        engine.goLiveWithSchedule(id: "s1")
        engine.removeRole(id: "band")
        engine.renameRole(id: "host", name: "Lead")
        engine.addPlanItem(title: "New", itemType: "Item", lengthInSeconds: 60)
        engine.removePlanItem(id: "a")
        engine.movePlanItems(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        engine.updatePlanItem(id: "a", title: "T", itemType: "Song", lengthInSeconds: 10, notes: ["Lights": "dim"], isDurationActual: true)
        engine.assignWaypoint("w1", toItemId: "a")
        engine.createWaypointAndAssign(name: "Song 2", toItemId: "a")
        engine.removeWaypoint(id: "w1")
        engine.removeServiceSchedule(id: "s1")
        engine.updateServiceSchedule(id: "s1", isEnabled: false)
        engine.selectPCOServiceType("st")
        engine.clearPCOServiceTypeSelection()
        engine.fetchPCOPlan(serviceTypeId: "st", planId: "p")
        engine.importFlow(title: "T", items: [PCOTimerItem(title: "A|B", itemType: "Song", lengthInSeconds: 125)])

        XCTAssertEqual(engine.roles, before)
        XCTAssertEqual(engine.planItems.map(\.id), ["a", "b"])
        XCTAssertEqual(engine.waypoints.count, 1)
        XCTAssertEqual(engine.serviceSchedules.count, 1)
        XCTAssertEqual(sink.sent.first, .cueSelected(.go))
        XCTAssertTrue(sink.sent.contains(.timerPause))
        XCTAssertTrue(sink.sent.contains(.planNext(startTimer: true)))
        XCTAssertTrue(sink.sent.contains(.waypointGo(ref: "w1", startTimer: true)))
        XCTAssertTrue(sink.sent.contains(.planReorder(itemIds: ["b", "a"])))
        XCTAssertTrue(sink.sent.contains(.planImport(text: "A/B | Song | 2:05", title: "T")))
        XCTAssertTrue(sink.sent.contains(.waypointAssign(ref: "Song 2", itemId: "a")))
        XCTAssertTrue(sink.sent.contains(.pcoSelectServiceType(id: nil)))
        XCTAssertEqual(sink.sent.count, 32)
    }

    func testMirrorRoleSelectionIsOptimisticAndKeepsOneSelected() {
        let sink = RecordingCommands()
        let engine = CueEngine(mirroring: sink)
        engine.apply(remoteState: RemoteFixtures.state(rev: 1))
        engine.toggleRoleSelection("band")
        XCTAssertEqual(engine.selectedRoleIds, ["host", "band"])
        XCTAssertEqual(sink.sent.last, .select(roleIds: ["band", "host"]))
        engine.toggleRoleSelection("band")
        engine.toggleRoleSelection("host")
        XCTAssertEqual(engine.selectedRoleIds, ["host"])
        XCTAssertEqual(sink.sent.count, 2)
    }
}

@MainActor
final class MirrorEngineTests: XCTestCase {
    func testApplyMapsRemoteStateOntoPublishedProperties() {
        let engine = CueEngine(mirroring: nil)
        engine.apply(remoteState: RemoteFixtures.state(rev: 5, roleName: "Lead"))
        XCTAssertEqual(engine.roles.map(\.name), ["Lead", "Band"])
        XCTAssertEqual(engine.roles[1].state, .go)
        XCTAssertEqual(engine.selectedRoleIds, ["host"])
        XCTAssertEqual(engine.planItems.count, 2)
        XCTAssertEqual(engine.activeItemIndex, 1)
        XCTAssertEqual(engine.activeTimerItem?.id, "b")
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 10)
        XCTAssertEqual(engine.activeTimerItem?.isRunning, true)
        XCTAssertTrue(engine.activeTimerActualForDisplay)
        XCTAssertEqual(engine.waypoints.map(\.name), ["Song 1"])
        XCTAssertEqual(engine.serviceSchedules.first?.recurrence, .weekly)
        XCTAssertEqual(engine.serviceSchedules.first?.goLiveOffsetSeconds, 1800)
        XCTAssertEqual(engine.recentMessages.map(\.text), ["hi"])
        XCTAssertEqual(engine.hourFormatThreshold, .over60Minutes)
        XCTAssertEqual(engine.pcoServiceTypes.map(\.name), ["Sunday"])
        XCTAssertTrue(engine.isAtEndOfPlan)
    }

    func testMirrorNeverWritesPersistentState() {
        let defaults = UserDefaults.standard
        let before = defaults.dictionaryRepresentation() as NSDictionary
        let sink = RecordingCommands()
        let engine = CueEngine(mirroring: sink)
        engine.apply(remoteState: RemoteFixtures.state(rev: 1))
        engine.apply(remoteState: RemoteFixtures.state(rev: 2, roleName: "Changed"))
        engine.hourFormatThreshold = .never
        engine.pcoUserName = "x"
        engine.isPCOLiveSyncEnabled = true
        engine.roles = [RoleCue(name: "Local")]
        engine.waypoints = [Waypoint(name: "Local")]
        engine.serviceSchedules = []
        engine.recentMessages = []
        engine.notificationsClearedAt = Date()
        engine.planItems = []
        engine.activeItemIndex = 0
        engine.signOutOfPCO()
        engine.signInWithPCO()
        engine.resetToNewDocument()
        engine.toggleMasterMode()
        engine.startNetworking()
        _ = engine.pingDevice(atIP: "127.0.0.1")
        engine.tickTimer()
        let after = defaults.dictionaryRepresentation() as NSDictionary
        XCTAssertEqual(before, after)
        XCTAssertTrue(sink.sent.isEmpty)
    }

    func testMirrorDoesNotDisturbLocalEnginePersistence() {
        let local = CueEngine()
        local.roles = [RoleCue(id: "mine", name: "Mine")]
        let stored = UserDefaults.standard.data(forKey: "persistedRoles")
        let mirror = CueEngine(mirroring: nil)
        mirror.apply(remoteState: RemoteFixtures.state(rev: 1))
        XCTAssertEqual(UserDefaults.standard.data(forKey: "persistedRoles"), stored)
        XCTAssertEqual(local.roles.map(\.id), ["mine"])
        UserDefaults.standard.removeObject(forKey: "persistedRoles")
    }
}

final class RemoteStateTrackerTests: XCTestCase {
    func testStaleSnapshotsAreIgnoredAndHelloResetsTheGuard() {
        var tracker = RemoteStateTracker()
        XCTAssertTrue(tracker.accept(RemoteFixtures.state(rev: 10)))
        XCTAssertFalse(tracker.accept(RemoteFixtures.state(rev: 9)))
        XCTAssertFalse(tracker.accept(RemoteFixtures.state(rev: 10)))
        XCTAssertTrue(tracker.accept(RemoteFixtures.state(rev: 11)))
        tracker.hello(RemoteFixtures.state(rev: 2))
        XCTAssertEqual(tracker.lastRev, 2)
        XCTAssertTrue(tracker.accept(RemoteFixtures.state(rev: 3)))
    }

    func testTimerEventMergesIntoHeldSnapshot() throws {
        var tracker = RemoteStateTracker()
        let slim = ControlAPITimerState(rev: 5, serverNowMs: 1, timer: nil)
        XCTAssertFalse(tracker.merge(timer: slim))
        tracker.hello(RemoteFixtures.state(rev: 4))
        let timer = try ControlAPIJSON.decoder.decode(ControlAPIState.ActiveTimer.self, from: Data(RemoteFixtures.timerJSON(elapsed: 99, running: false).utf8))
        XCTAssertTrue(tracker.merge(timer: ControlAPITimerState(rev: 5, serverNowMs: 7, timer: timer)))
        XCTAssertEqual(tracker.state?.timer?.item.elapsedSeconds, 99)
        XCTAssertEqual(tracker.state?.rev, 5)
        XCTAssertEqual(tracker.state?.roles.count, 2)
        XCTAssertFalse(tracker.merge(timer: ControlAPITimerState(rev: 5, serverNowMs: 8, timer: nil)))
    }
}

final class ProducerDiscoveryMappingTests: XCTestCase {
    func testMapsTXTRecordToEndpoint() {
        let producer = DiscoveredProducer.make(serviceName: "Studio Mac", txt: ["ip": "10.0.0.7", "apiport": "14000"], ownAddresses: [])
        XCTAssertEqual(producer?.endpoint.host, "10.0.0.7")
        XCTAssertEqual(producer?.endpoint.port, 14000)
        XCTAssertEqual(producer?.displayName, "Studio Mac")
    }

    func testDefaultsPortAndSkipsMissingOrOwnAddresses() {
        XCTAssertEqual(DiscoveredProducer.make(serviceName: "A", txt: ["ip": "10.0.0.7"], ownAddresses: [])?.endpoint.port, 13390)
        XCTAssertEqual(DiscoveredProducer.make(serviceName: "A", txt: ["ip": "10.0.0.7", "apiport": "0"], ownAddresses: [])?.endpoint.port, 13390)
        XCTAssertNil(DiscoveredProducer.make(serviceName: "A", txt: [:], ownAddresses: []))
        XCTAssertNil(DiscoveredProducer.make(serviceName: "Me", txt: ["ip": "10.0.0.2"], ownAddresses: ["10.0.0.2"]))
    }
}

@MainActor
final class FakeSocket: RemoteSocket {
    var onText: ((String) -> Void)?
    var onClose: ((String) -> Void)?
    var pingResult = true
    var didOpen = false
    var didClose = false
    var helloOnOpen: String?
    var sent: [String] = []

    func send(_ text: String) { sent.append(text) }

    func open() {
        didOpen = true
        if let helloOnOpen {
            let handler = onText
            DispatchQueue.main.async { handler?(helloOnOpen) }
        }
    }
    func ping(timeout: TimeInterval) async -> Bool { pingResult }
    func close() { didClose = true }
}

struct FakeHTTP: RemoteProducerHTTP {
    var handler: @Sendable (String, URL, Data?) throws -> (Int, Data)
    func perform(method: String, url: URL, body: Data?) async throws -> (status: Int, data: Data) {
        let result = try handler(method, url, body)
        return (result.0, result.1)
    }
}

@MainActor
final class RemoteProducerSessionTests: XCTestCase {
    private let healthBody = Data("{\"service\":\"13 Years Control API\",\"version\":\"1.0.0\",\"device\":\"Studio\",\"role\":\"master\"}".utf8)
    private let fast = RemoteProducerSession.Timing(pingInterval: 0.05, pongTimeout: 0.05, helloTimeout: 1, retryDelays: [0.01])

    private func makeSession(
        sockets: [FakeSocket],
        http: FakeHTTP? = nil
    ) -> (RemoteProducerSession, () -> [FakeSocket]) {
        var queue = sockets
        var opened: [FakeSocket] = []
        let body = healthBody
        let session = RemoteProducerSession(
            endpoint: RemoteEndpoint(host: "127.0.0.1", name: "127.0.0.1"),
            http: http ?? FakeHTTP { _, url, _ in
                if url.path == "/v1/health" { return (200, body) }
                return (404, Data())
            },
            socketFactory: { _ in
                let socket = queue.isEmpty ? FakeSocket() : queue.removeFirst()
                opened.append(socket)
                return socket
            },
            timing: fast
        )
        return (session, { opened })
    }

    private func hello(rev: Int, roleName: String = "Host") -> FakeSocket {
        let socket = FakeSocket()
        socket.helloOnOpen = RemoteFixtures.event("hello", RemoteFixtures.stateJSON(rev: rev, roleName: roleName))
        return socket
    }

    private func waitUntil(_ timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    func testConnectsAppliesHelloAndGuardsRevisions() async {
        let socket = hello(rev: 10)
        let (session, _) = makeSession(sockets: [socket])
        await session.connect()
        XCTAssertEqual(session.connection, .connected)
        XCTAssertEqual(session.displayName, "Studio")
        XCTAssertEqual(session.engine.roles.first?.name, "Host")

        socket.onText?(RemoteFixtures.event("state", RemoteFixtures.stateJSON(rev: 9, roleName: "Old")))
        XCTAssertEqual(session.engine.roles.first?.name, "Host")
        socket.onText?(RemoteFixtures.event("state", RemoteFixtures.stateJSON(rev: 11, roleName: "New")))
        XCTAssertEqual(session.engine.roles.first?.name, "New")
        socket.onText?(RemoteFixtures.event("timer", "{\"rev\":12,\"serverNowMs\":1,\"timer\":\(RemoteFixtures.timerJSON(elapsed: 42, running: false))}"))
        XCTAssertEqual(session.engine.activeTimerItem?.elapsedSeconds, 42)
        XCTAssertEqual(session.engine.activeTimerItem?.isRunning, false)
        XCTAssertEqual(session.engine.roles.first?.name, "New")
        session.disconnect()
        XCTAssertEqual(session.connection, .disconnected)
        XCTAssertTrue(socket.didClose)
    }

    func testFailsWhenProducerIsUnreachable() async {
        let (session, _) = makeSession(sockets: [], http: FakeHTTP { _, _, _ in throw URLError(.cannotConnectToHost) })
        await session.connect()
        guard case .failed(let reason) = session.connection else { return XCTFail("expected failure") }
        XCTAssertTrue(reason.contains("Control API"))
    }

    func testRejectsNonProducerHealth() async {
        let (session, _) = makeSession(sockets: [], http: FakeHTTP { _, _, _ in (200, Data("{\"service\":\"other\",\"version\":\"1\",\"device\":\"x\",\"role\":\"y\"}".utf8)) })
        await session.connect()
        XCTAssertNotEqual(session.connection, .connected)
    }

    func testDeadSocketReconnectsAndHelloResetsTheGuard() async {
        let first = hello(rev: 500)
        let second = hello(rev: 3, roleName: "Fresh")
        let (session, opened) = makeSession(sockets: [first, second])
        await session.connect()
        first.pingResult = false
        await waitUntil { session.connection == .reconnecting || opened().count > 1 }
        await waitUntil { session.connection == .connected && opened().count == 2 }
        XCTAssertEqual(opened().count, 2)
        XCTAssertEqual(session.connection, .connected)
        XCTAssertEqual(session.engine.roles.first?.name, "Fresh")
        XCTAssertEqual(session.state?.rev, 3)
        session.disconnect()
    }

    func testCommandsAreBlockedUntilLiveAndReplySnapshotsFeedTheGuard() async {
        let body = healthBody
        let replyState = RemoteFixtures.stateJSON(rev: 20, roleName: "FromReply")
        let log = LockedLog()
        let http = FakeHTTP { method, url, requestBody in
            if url.path == "/v1/health" { return (200, body) }
            log.add("\(method) \(url.path) \(requestBody.flatMap { String(data: $0, encoding: .utf8) } ?? "")")
            if url.path == "/v1/timer/reset" { return (409, Data("{\"error\":\"No active plan item\"}".utf8)) }
            return (200, Data(replyState.utf8))
        }
        let (session, _) = makeSession(sockets: [hello(rev: 10)], http: http)
        session.send(.clearCues)
        XCTAssertNotNil(session.lastError)
        XCTAssertTrue(log.entries.isEmpty)

        await session.connect()
        session.send(.cueSelected(.go))
        await waitUntil { session.engine.roles.first?.name == "FromReply" }
        XCTAssertEqual(session.engine.roles.first?.name, "FromReply")
        XCTAssertEqual(log.entries.first, "POST /v1/cues/selected {\"state\":\"GO\"}")

        session.send(.timerReset)
        await waitUntil { session.lastError == "No active plan item" }
        XCTAssertEqual(session.lastError, "No active plan item")
        session.disconnect()
    }
}

final class LockedLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var entries: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    func add(_ entry: String) { lock.lock(); storage.append(entry); lock.unlock() }
}

@MainActor
final class RemoteProducerLiveTests: XCTestCase {
    func testConnectsToLocalProducerWhenItIsRunning() async throws {
        let endpoint = RemoteEndpoint(host: "127.0.0.1")
        guard (try? await RemoteProducerSession.fetchHealth(of: endpoint)) != nil else {
            throw XCTSkip("No Producer with the Control API on localhost:13390")
        }
        let session = RemoteProducerSession(endpoint: endpoint)
        await session.connect()
        XCTAssertEqual(session.connection, .connected)
        let state = try XCTUnwrap(session.state)
        XCTAssertEqual(session.engine.roles, state.roles)
        XCTAssertEqual(session.engine.planItems, state.plan.items)
        let before = state.selectedRoleIds
        session.send(.select(roleIds: before))
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertNil(session.lastError)
        XCTAssertEqual(session.engine.selectedRoleIds, Set(before))
        XCTAssertGreaterThanOrEqual(session.state?.rev ?? 0, state.rev)
        session.disconnect()
    }
}
