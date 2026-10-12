// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

@MainActor
final class RemoteProducerSyncTests: XCTestCase {
    private let healthBody = Data("{\"service\":\"13 Years Control API\",\"version\":\"1.0.0\",\"device\":\"Studio\",\"role\":\"master\"}".utf8)
    private let fast = RemoteProducerSession.Timing(pingInterval: 5, pongTimeout: 1, helloTimeout: 1, retryDelays: [0.01])
    private var nowMs = 1_760_000_000_000.0

    private func makeSession(socket: FakeSocket, log: LockedLog? = nil, stateBody: String? = nil) -> RemoteProducerSession {
        let health = healthBody
        let session = RemoteProducerSession(
            endpoint: RemoteEndpoint(host: "127.0.0.1", name: "127.0.0.1"),
            http: FakeHTTP { method, url, _ in
                log?.add("\(method) \(url.path)")
                if url.path == "/v1/health" { return (200, health) }
                if url.path == "/v1/state", let stateBody { return (200, Data(stateBody.utf8)) }
                return (404, Data())
            },
            socketFactory: { _ in socket },
            timing: fast
        )
        session.clock = { [unowned self] in self.nowMs }
        session.syncBurstSpacing = 0.005
        session.syncInterval = 3600
        session.engine.timerClock = { [unowned self] in Date(timeIntervalSince1970: self.nowMs / 1000) }
        return session
    }

    private func helloSocket(anchor: String? = nil) -> FakeSocket {
        let socket = FakeSocket()
        socket.helloOnOpen = RemoteFixtures.event("hello", RemoteFixtures.stateJSON(rev: 10))
        return socket
    }

    private func waitUntil(_ timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    private func sentOps(_ socket: FakeSocket) -> [[String: Any]] {
        socket.sent.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    private func answerSyncs(_ socket: FakeSocket, offset: Double, rtt: Double = 20) {
        for op in sentOps(socket) where op["op"] as? String == "sync" {
            let id = op["id"] as! String
            let t0 = (op["body"] as! [String: Any])["t0"] as! Int
            let t1 = Int(Double(t0) + rtt / 2 + offset)
            let reply = "{\"id\":\"\(id)\",\"status\":200,\"data\":{\"t0\":\(t0),\"t1\":\(t1),\"t2\":\(t1)}}"
            nowMs = Double(t0) + rtt
            socket.onText?(reply)
        }
    }

    func testSendsProtoTwoAfterHelloAndStartsSyncWhenAccepted() async {
        let socket = helloSocket()
        let session = makeSession(socket: socket)
        await session.connect()
        XCTAssertEqual(session.connection, .connected)
        let first = sentOps(socket).first
        XCTAssertEqual(first?["op"] as? String, "proto")
        XCTAssertEqual((first?["body"] as? [String: Any])?["version"] as? Int, 2)
        XCTAssertFalse(session.isProtocolV2)
        XCTAssertEqual(sentOps(socket).count, 1)

        socket.onText?("{\"id\":\"proto\",\"status\":200,\"data\":{\"version\":2}}")
        XCTAssertTrue(session.isProtocolV2)
        await waitUntil { sentOps(socket).filter { $0["op"] as? String == "sync" }.count == 5 }
        XCTAssertEqual(sentOps(socket).filter { $0["op"] as? String == "sync" }.count, 5)
        session.disconnect()
    }

    func testProducerThatRejectsProtoStaysOnLegacyBehaviour() async {
        let socket = helloSocket()
        let session = makeSession(socket: socket)
        await session.connect()
        socket.onText?("{\"id\":\"proto\",\"status\":404,\"error\":\"Unknown path\"}")
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(session.isProtocolV2)
        XCTAssertEqual(sentOps(socket).count, 1)
        socket.onText?(RemoteFixtures.event("timer", "{\"rev\":11,\"serverNowMs\":1,\"timer\":\(RemoteFixtures.timerJSON(elapsed: 33, running: true))}"))
        XCTAssertEqual(session.engine.activeTimerItem?.elapsedSeconds, 33)
        session.disconnect()
    }

    func testSyncRepliesSetTheMirrorOffsetAndTheTimerRunsLocallyFromTheAnchor() async {
        let socket = helloSocket()
        let session = makeSession(socket: socket)
        await session.connect()
        socket.onText?("{\"id\":\"proto\",\"status\":200,\"data\":{\"version\":2}}")
        await waitUntil { sentOps(socket).filter { $0["op"] as? String == "sync" }.count == 5 }
        answerSyncs(socket, offset: 3_000)
        let offset = session.engine.syncedProducerNowMs.map { $0 - nowMs }
        XCTAssertEqual(offset ?? 0, 3_000, accuracy: 1)

        let producerNow = Int(nowMs) + 3_000
        let anchor = "{\"itemId\":\"b\",\"lengthInSeconds\":300,\"elapsedMs\":20000,\"anchorMs\":\(producerNow - 1500),\"isRunning\":true,\"isDurationActual\":true}"
        socket.onText?(RemoteFixtures.event("timer", "{\"rev\":12,\"serverNowMs\":1,\"timer\":\(RemoteFixtures.timerJSON(elapsed: 20, running: true, anchor: anchor))}"))
        XCTAssertEqual(session.engine.activeTimerItem?.elapsedSeconds, 21)
        nowMs += 600
        session.engine.refreshHeldTimer()
        XCTAssertEqual(session.engine.activeTimerItem?.elapsedSeconds, 22)

        let paused = "{\"itemId\":\"b\",\"lengthInSeconds\":300,\"elapsedMs\":22400,\"anchorMs\":\(producerNow + 600),\"isRunning\":false,\"isDurationActual\":true}"
        socket.onText?(RemoteFixtures.event("timer", "{\"rev\":13,\"serverNowMs\":1,\"timer\":\(RemoteFixtures.timerJSON(elapsed: 22, running: false, anchor: paused))}"))
        nowMs += 60_000
        session.engine.refreshHeldTimer()
        XCTAssertEqual(session.engine.activeTimerItem?.elapsedSeconds, 22)
        XCTAssertEqual(session.engine.activeTimerItem?.isRunning, false)
        session.disconnect()
        XCTAssertNil(session.engine.syncedProducerNowMs)
    }

    func testMatchingDigestDoesNothingAndMismatchFallsBackToStateFetch() async throws {
        let socket = helloSocket()
        let log = LockedLog()
        let fresh = RemoteFixtures.stateJSON(rev: 40, roleName: "Fresh")
        let session = makeSession(socket: socket, log: log, stateBody: fresh)
        await session.connect()
        let hashes = session.engine.mirrorHashes()
        func digest(_ hashes: SyncHash.Hashes, rev: Int) -> String {
            let plan = hashes.plan ?? ""
            return RemoteFixtures.event("digest", "{\"rev\":\(rev),\"serverNowMs\":1,\"hashes\":{\"roles\":\"\(hashes.roles)\",\"timer\":\"\(hashes.timer)\",\"plan\":\"\(plan)\",\"messages\":\"\(hashes.messages)\"}}")
        }
        socket.onText?(digest(hashes, rev: 11))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(log.entries.contains("GET /v1/state"))

        var wrong = hashes
        wrong.roles = "0000000000000000"
        socket.onText?(digest(wrong, rev: 12))
        await waitUntil { session.engine.roles.first?.name == "Fresh" }
        XCTAssertTrue(log.entries.contains("GET /v1/state"))
        XCTAssertEqual(session.engine.roles.first?.name, "Fresh")
        XCTAssertEqual(session.state?.rev, 40)
        session.disconnect()
    }

    func testStaleDigestsAreIgnored() async {
        let socket = helloSocket()
        let log = LockedLog()
        let session = makeSession(socket: socket, log: log, stateBody: RemoteFixtures.stateJSON(rev: 40))
        await session.connect()
        socket.onText?(RemoteFixtures.event("digest", "{\"rev\":3,\"serverNowMs\":1,\"hashes\":{\"roles\":\"x\",\"timer\":\"x\",\"plan\":\"x\",\"messages\":\"x\"}}"))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(log.entries.contains("GET /v1/state"))
        session.disconnect()
    }

    func testResyncSendsOneMoreSampleOnlyWhenNegotiated() async {
        let socket = helloSocket()
        let session = makeSession(socket: socket)
        await session.connect()
        session.resync()
        XCTAssertEqual(sentOps(socket).count, 1)
        socket.onText?("{\"id\":\"proto\",\"status\":200,\"data\":{\"version\":2}}")
        await waitUntil { sentOps(socket).filter { $0["op"] as? String == "sync" }.count == 5 }
        session.resync()
        XCTAssertEqual(sentOps(socket).filter { $0["op"] as? String == "sync" }.count, 6)
        session.disconnect()
    }
}
