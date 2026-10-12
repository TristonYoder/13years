// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
import Network

final class HTTPBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedHealth: String
    private var storedFailure: URLError.Code?
    init(deviceId: String?) { storedHealth = Self.health(deviceId) }
    static func health(_ deviceId: String?) -> String {
        let id = deviceId.map { ",\"deviceId\":\"\($0)\"" } ?? ""
        return "{\"service\":\"13 Years Control API\",\"version\":\"1.0.0\",\"device\":\"Studio\",\"role\":\"master\"\(id)}"
    }
    var health: String {
        get { lock.lock(); defer { lock.unlock() }; return storedHealth }
        set { lock.lock(); storedHealth = newValue; lock.unlock() }
    }
    var failure: URLError.Code? {
        get { lock.lock(); defer { lock.unlock() }; return storedFailure }
        set { lock.lock(); storedFailure = newValue; lock.unlock() }
    }
}

@MainActor
final class RemoteHardeningTests: XCTestCase {
    private let fast = RemoteProducerSession.Timing(pingInterval: 60, pongTimeout: 0.05, helloTimeout: 1, retryDelays: [0.01], maxReconnectAttempts: 2)

    private func makeSession(
        sockets: [FakeSocket],
        box: HTTPBox = HTTPBox(deviceId: "A"),
        ownDeviceId: String? = "ME",
        handler: (@Sendable (String, URL, Data?) throws -> (Int, Data))? = nil
    ) -> RemoteProducerSession {
        var queue = sockets
        return RemoteProducerSession(
            endpoint: RemoteEndpoint(host: "127.0.0.1", name: "127.0.0.1"),
            http: FakeHTTP { method, url, body in
                if url.path == "/v1/health" {
                    if let code = box.failure { throw URLError(code) }
                    return (200, Data(box.health.utf8))
                }
                if let handler { return try handler(method, url, body) }
                return (404, Data())
            },
            socketFactory: { _ in queue.isEmpty ? FakeSocket() : queue.removeFirst() },
            timing: fast,
            ownDeviceId: ownDeviceId
        )
    }

    private func hello(rev: Int = 10) -> FakeSocket {
        let socket = FakeSocket()
        socket.helloOnOpen = RemoteFixtures.event("hello", RemoteFixtures.stateJSON(rev: rev))
        return socket
    }

    private func waitUntil(_ timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    func testMirrorCueSelectedSendsOneCommandPerSelectedRole() {
        let sink = RecordingCommands()
        let engine = CueEngine(mirroring: sink)
        engine.apply(remoteState: RemoteFixtures.state(rev: 1))
        engine.toggleRoleSelection("band")
        sink.sent.removeAll()
        engine.setCueForSelectedRoles(.go)
        XCTAssertEqual(sink.sent, [.cueRole(id: "band", state: .go), .cueRole(id: "host", state: .go)])
    }

    func testFailedSelectionRollsBackToHeldState() async {
        let session = makeSession(sockets: [hello()]) { _, url, _ in
            url.path == "/v1/selection" ? (409, Data("{\"error\":\"Nope\",\"detail\":\"Because\"}".utf8)) : (404, Data())
        }
        await session.connect()
        session.engine.toggleRoleSelection("band")
        XCTAssertEqual(session.engine.selectedRoleIds, ["host", "band"])
        await waitUntil { session.lastError != nil }
        XCTAssertEqual(session.engine.selectedRoleIds, ["host"])
        XCTAssertEqual(session.recentErrors.last?.detail, "Because")
        session.disconnect()
    }

    func testTimeoutWordingAndRetryRules() async {
        let log = LockedLog()
        let session = makeSession(sockets: [hello()]) { method, url, _ in
            log.add("\(method) \(url.path)")
            throw URLError(.timedOut)
        }
        await session.connect()
        session.send(.planNext(startTimer: true))
        await waitUntil { session.lastError != nil }
        XCTAssertEqual(log.entries.filter { $0 == "POST /v1/plan/next" }.count, 1)
        XCTAssertTrue(session.recentErrors.last?.detail?.contains("may have been applied — check the state before retrying") == true)

        session.dismissError()
        session.send(.clearCues)
        await waitUntil { session.lastError != nil }
        XCTAssertEqual(log.entries.filter { $0 == "POST /v1/cues/clear" }.count, 2)
        session.disconnect()
    }

    func testStaleQueuedCommandsAreDropped() async {
        let log = LockedLog()
        let session = makeSession(sockets: [hello()]) { method, url, _ in
            log.add("\(method) \(url.path)")
            return (200, Data())
        }
        await session.connect()
        var offset: TimeInterval = 0
        session.now = { Date().addingTimeInterval(offset) }
        session.send(.clearCues)
        offset = 5
        await waitUntil { session.lastError != nil }
        XCTAssertTrue(log.entries.isEmpty)
        XCTAssertNotNil(session.lastError)
        session.disconnect()
    }

    func testCommandQueuedBeforeConnectionLossIsDropped() async {
        let log = LockedLog()
        let first = hello()
        let session = makeSession(sockets: [first, hello(rev: 20)]) { method, url, _ in
            log.add("\(method) \(url.path)")
            return (200, Data())
        }
        await session.connect()
        first.pingResult = false
        session.send(.clearCues)
        await session.checkLiveness()
        XCTAssertEqual(session.connection, .reconnecting)
        XCTAssertTrue(session.isResyncing)
        await waitUntil { session.connection == .connected }
        XCTAssertEqual(session.connection, .connected)
        XCTAssertFalse(session.isResyncing)
        XCTAssertTrue(log.entries.isEmpty)
        session.disconnect()
    }

    func testDifferentProducerOnReconnectFails() async {
        let box = HTTPBox(deviceId: "A")
        let first = hello()
        let session = makeSession(sockets: [first, hello()], box: box)
        await session.connect()
        box.health = HTTPBox.health("B")
        first.pingResult = false
        await session.checkLiveness()
        await waitUntil { if case .failed = session.connection { return true } else { return false } }
        guard case .failed(let reason) = session.connection else { return XCTFail("expected failure, got \(session.connection)") }
        XCTAssertTrue(reason.contains("different Producer"))
    }

    func testStallsAfterRepeatedFailuresAndRecoversOnReconnectNow() async {
        let box = HTTPBox(deviceId: "A")
        let first = hello()
        let session = makeSession(sockets: [first, hello(rev: 30)], box: box)
        await session.connect()
        box.failure = .cannotConnectToHost
        first.pingResult = false
        await session.checkLiveness()
        await waitUntil { session.connection == .stalled(.refused) }
        XCTAssertEqual(session.connection, .stalled(.refused))

        box.failure = .timedOut
        session.reconnectNow()
        await waitUntil { session.connection == .stalled(.unreachable) }
        XCTAssertEqual(session.connection, .stalled(.unreachable))

        box.failure = nil
        session.reconnectNow()
        await waitUntil { session.connection == .connected }
        XCTAssertEqual(session.connection, .connected)
        session.disconnect()
    }

    func testConnectingToSelfIsRefused() async {
        let session = makeSession(sockets: [hello()], box: HTTPBox(deviceId: "ME"))
        await session.connect()
        guard case .failed(let reason) = session.connection else { return XCTFail("expected failure") }
        XCTAssertTrue(reason.contains("this device"))
    }

    func testWaypointCreateThenAssignUsesReplyId() async {
        let log = LockedLog()
        let session = makeSession(sockets: [hello()]) { method, url, body in
            log.add("\(method) \(url.path) \(body.flatMap { String(data: $0, encoding: .utf8) } ?? "")")
            if url.path == "/v1/waypoints" { return (201, Data("{\"id\":\"w9\",\"name\":\"Song 2\",\"slug\":\"song-2\"}".utf8)) }
            return (200, Data())
        }
        await session.connect()
        session.engine.createWaypointAndAssign(name: "Song 2", toItemId: "a")
        await waitUntil { log.entries.count >= 2 }
        XCTAssertEqual(log.entries, ["POST /v1/waypoints {\"name\":\"Song 2\"}", "POST /v1/waypoints/w9/assign {\"itemId\":\"a\"}"])
        session.disconnect()
    }

    func testWaypointAssignSkippedWhenCreateConflicts() async {
        let log = LockedLog()
        let session = makeSession(sockets: [hello()]) { method, url, _ in
            log.add("\(method) \(url.path)")
            return (409, Data("{\"error\":\"A waypoint with this name already exists\"}".utf8))
        }
        await session.connect()
        session.engine.createWaypointAndAssign(name: "Song 2", toItemId: "a")
        await waitUntil { session.lastError != nil }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(log.entries, ["POST /v1/waypoints"])
        session.disconnect()
    }

    func testErrorsKeepLastThreeForTenSeconds() async {
        let session = makeSession(sockets: [hello()])
        await session.connect()
        for _ in 0..<5 { session.send(.timerReset) }
        await waitUntil { session.recentErrors.count == 3 }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(session.recentErrors.count, 3)
        session.now = { Date().addingTimeInterval(11) }
        session.pruneErrors()
        XCTAssertTrue(session.recentErrors.isEmpty)
        XCTAssertNil(session.lastError)
        session.disconnect()
    }

    func testMirrorPersistHelpersAreSkippedWhenMirroring() {
        let before = UserDefaults.standard.dictionaryRepresentation().count
        let engine = CueEngine(mirroring: nil)
        engine.apply(remoteState: RemoteFixtures.state(rev: 1))
        engine.apply(remoteState: RemoteFixtures.state(rev: 2, roleName: "Changed"))
        XCTAssertEqual(UserDefaults.standard.dictionaryRepresentation().count, before)
    }
}

final class RemoteDiscoveryHardeningTests: XCTestCase {
    func testPrefersResolvedHostAndFallsBackToTXTIp() {
        let resolved = DiscoveredProducer.make(serviceName: "A", txt: ["ip": "10.0.0.7"], ownAddresses: [], resolvedHost: "fe80::1")
        XCTAssertEqual(resolved?.endpoint.host, "fe80::1")
        XCTAssertEqual(DiscoveredProducer.make(serviceName: "A", txt: ["ip": "10.0.0.7"], ownAddresses: [])?.endpoint.host, "10.0.0.7")
        XCTAssertEqual(DiscoveredProducer.make(serviceName: "A", txt: [:], ownAddresses: [], resolvedHost: "10.0.0.9")?.endpoint.host, "10.0.0.9")
    }

    func testExcludesSelfByDeviceId() {
        XCTAssertNil(DiscoveredProducer.make(serviceName: "Me", txt: ["ip": "10.0.0.7", "did": "ME"], ownAddresses: [], ownDeviceId: "ME"))
        let other = DiscoveredProducer.make(serviceName: "Them", txt: ["ip": "10.0.0.7", "did": "THEM"], ownAddresses: [], ownDeviceId: "ME")
        XCTAssertEqual(other?.deviceId, "THEM")
    }

    @MainActor
    func testProbeBackoffGrowsAndCaps() {
        XCTAssertEqual(ProducerDiscovery.nextInterval(afterQuietRounds: 0), 3)
        XCTAssertEqual(ProducerDiscovery.nextInterval(afterQuietRounds: 1), 6)
        XCTAssertEqual(ProducerDiscovery.nextInterval(afterQuietRounds: 10), 15)
    }

    func testWaitingStateMapsToPermissionHint() {
        XCTAssertEqual(BrowseIssue.from(waiting: .dns(-65570)), .localNetworkDenied)
        XCTAssertTrue(BrowseIssue.localNetworkDenied.message.contains("Local Network"))
        if case .waiting = BrowseIssue.from(waiting: .posix(.ENETDOWN)) {} else { XCTFail("expected waiting") }
    }

    @MainActor
    func testRefusalIsDistinguishedFromUnreachable() {
        XCTAssertTrue(RemoteProducerSession.isRefusal(URLError(.cannotConnectToHost)))
        XCTAssertFalse(RemoteProducerSession.isRefusal(URLError(.timedOut)))
    }
}
