// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

@MainActor
final class ControlAPIV2Tests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_760_000_000)

    override func setUp() {
        super.setUp()
        clearPersistedState()
        clock = Date(timeIntervalSince1970: 1_760_000_000)
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

    private func makeEngine() -> CueEngine {
        let engine = CueEngine(startsNetworking: false)
        engine.timerClock = { [unowned self] in self.clock }
        engine.roles = [RoleCue(id: "host", name: "Host", state: .go), RoleCue(id: "band", name: "Band")]
        engine.importFlow(title: "Plan", items: [
            PCOTimerItem(id: "i1", title: "Song", itemType: "Song", lengthInSeconds: 300),
            PCOTimerItem(id: "i2", title: "Sermon", itemType: "Item", lengthInSeconds: 2700, isDurationActual: true),
        ])
        return engine
    }

    private func command(_ op: String, _ body: String? = nil, id: String = "1") -> ControlAPICommand {
        var json = "{\"id\":\"\(id)\",\"op\":\"\(op)\""
        if let body { json += ",\"body\":\(body)" }
        json += "}"
        return try! ControlAPIJSON.decoder.decode(ControlAPICommand.self, from: Data(json.utf8))
    }

    private func object(_ data: AnyJSON?) -> [String: AnyJSON] {
        if case .object(let fields)? = data { return fields }
        return [:]
    }

    private func number(_ value: AnyJSON?) -> Double? {
        if case .number(let number)? = value { return number }
        return nil
    }

    func testProtoOpNegotiatesVersionTwoPerConnection() {
        let router = ControlAPIRouter(engine: makeEngine())
        let first = ControlAPIConnection()
        let second = ControlAPIConnection()
        XCTAssertFalse(first.isV2)
        let reply = router.handleCommand(command("proto", #"{"version":2}"#), connection: first)
        XCTAssertEqual(reply.status, 200)
        XCTAssertEqual(reply.id, "1")
        XCTAssertEqual(number(object(reply.data)["version"]), 2)
        XCTAssertTrue(first.isV2)
        XCTAssertFalse(second.isV2)
    }

    func testProtoOpRejectsUnknownVersionsAndNonSocketUse() {
        let router = ControlAPIRouter(engine: makeEngine())
        let connection = ControlAPIConnection()
        XCTAssertEqual(router.handleCommand(command("proto", #"{"version":3}"#), connection: connection).status, 400)
        XCTAssertFalse(connection.isV2)
        XCTAssertEqual(router.handleCommand(command("proto", "{}"), connection: connection).status, 400)
        XCTAssertEqual(router.handleCommand(command("proto", #"{"version":2}"#)).status, 400)
        let rest = router.handle(HTTPRequest(method: "POST", path: "/v1/proto", body: Data(#"{"version":2}"#.utf8)))
        XCTAssertEqual(rest.status, 400)
        _ = router.handleCommand(command("proto", #"{"version":2}"#), connection: connection)
        XCTAssertEqual(router.handleCommand(command("proto", #"{"version":1}"#), connection: connection).status, 200)
        XCTAssertFalse(connection.isV2)
    }

    func testSyncOpReturnsEchoedT0AndOrderedServerTimes() {
        let router = ControlAPIRouter(engine: makeEngine())
        let reply = router.handleCommand(command("sync", #"{"t0":1760000000100}"#), receivedAtMs: 1_760_000_000_150)
        XCTAssertEqual(reply.status, 200)
        let fields = object(reply.data)
        XCTAssertEqual(number(fields["t0"]), 1_760_000_000_100)
        XCTAssertEqual(number(fields["t1"]), 1_760_000_000_150)
        let t2 = number(fields["t2"]) ?? 0
        XCTAssertGreaterThanOrEqual(t2, Double(Int(Date().timeIntervalSince1970 * 1000)) - 5_000)
    }

    func testSyncRouteMatchesTheOp() throws {
        let router = ControlAPIRouter(engine: makeEngine())
        let response = router.handle(HTTPRequest(method: "POST", path: "/v1/sync", body: Data(#"{"t0":42}"#.utf8)), receivedAtMs: 77)
        XCTAssertEqual(response.status, 200)
        let reply = try JSONDecoder().decode(ControlAPISyncReply.self, from: response.body)
        XCTAssertEqual(reply.t0, 42)
        XCTAssertEqual(reply.t1, 77)
        XCTAssertGreaterThan(reply.t2, 77)
        XCTAssertEqual(router.handle(HTTPRequest(method: "GET", path: "/v1/sync", body: Data())).status, 405)
        XCTAssertEqual(router.handle(HTTPRequest(method: "POST", path: "/v1/sync", body: Data("{}".utf8))).status, 400)
    }

    func testSyncOpDefaultsT1ToNowWhenNoReceiptTimeIsGiven() {
        let router = ControlAPIRouter(engine: makeEngine())
        let before = Int(Date().timeIntervalSince1970 * 1000)
        let reply = router.handleCommand(command("sync", #"{"t0":1}"#))
        let t1 = Int(number(object(reply.data)["t1"]) ?? 0)
        let t2 = Int(number(object(reply.data)["t2"]) ?? 0)
        XCTAssertGreaterThanOrEqual(t1, before - 1)
        XCTAssertGreaterThanOrEqual(t2, t1)
    }

    func testActiveTimerCarriesTheAnchorInEveryTimerBearingResponse() throws {
        let engine = makeEngine()
        let router = ControlAPIRouter(engine: engine)
        clock.addTimeInterval(7.25)
        engine.tickTimer()
        engine.toggleTimerRunning()
        let anchor = try XCTUnwrap(engine.currentAnchor)

        let state = router.snapshot()
        XCTAssertEqual(state.timer?.anchor, anchor)
        XCTAssertEqual(router.timerSnapshot().timer?.anchor, anchor)
        XCTAssertEqual(anchor.itemId, "i1")
        XCTAssertEqual(anchor.elapsedMs, 7_250)
        XCTAssertFalse(anchor.isRunning)

        let response = router.handle(HTTPRequest(method: "GET", path: "/v1/plan/active", body: Data()))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        let wire = try XCTUnwrap(json["anchor"] as? [String: Any])
        XCTAssertEqual(Set(wire.keys), ["itemId", "lengthInSeconds", "elapsedMs", "anchorMs", "isRunning", "isDurationActual"])
        XCTAssertEqual(wire["elapsedMs"] as? Int, 7_250)
    }

    func testSnapshotWithoutATimerOmitsTheAnchor() throws {
        let engine = CueEngine(startsNetworking: false)
        engine.resetToNewDocument()
        let router = ControlAPIRouter(engine: engine)
        XCTAssertNil(router.snapshot().timer)
    }

    func testOldSnapshotsWithoutAnAnchorStillDecode() throws {
        let state = RemoteFixtures.state(rev: 1)
        XCTAssertNil(state.timer?.anchor)
    }

    func testDigestEqualsSyncHashOfTheSnapshot() {
        let engine = makeEngine()
        engine.addMessages([
            InterTeamMessage(id: "m1", text: "a", timestamp: Date(timeIntervalSince1970: 10)),
            InterTeamMessage(id: "m2", text: "b", timestamp: Date(timeIntervalSince1970: 20)),
        ])
        let router = ControlAPIRouter(engine: engine)
        let snapshot = router.snapshot()
        let digest = router.digest()
        XCTAssertEqual(digest.hashes.roles, SyncHash.roles(snapshot.roles))
        XCTAssertEqual(digest.hashes.timer, SyncHash.timer(snapshot.timer?.anchor))
        XCTAssertEqual(digest.hashes.plan, SyncHash.plan(items: snapshot.plan.items, activeItemIndex: snapshot.plan.activeItemIndex))
        XCTAssertEqual(digest.hashes.messages, SyncHash.messages(snapshot.messages))
        XCTAssertEqual(digest.hashes.messages, SyncHash.messages(ids: ["m2", "m1"]))
        XCTAssertEqual(digest.rev, snapshot.rev)
        XCTAssertGreaterThan(digest.serverNowMs, 0)
    }

    func testDigestChangesWhenTheStateChanges() {
        let engine = makeEngine()
        let router = ControlAPIRouter(engine: engine)
        let before = router.digest().hashes
        engine.setCueForRole(id: "band", state: .go)
        XCTAssertNotEqual(router.digest().hashes.roles, before.roles)
        XCTAssertEqual(router.digest().hashes.plan, before.plan)
        engine.toggleTimerRunning()
        XCTAssertNotEqual(router.digest().hashes.timer, before.timer)
        engine.renameRole(id: "host", name: "Lead")
        engine.updatePlanItem(id: "i1", title: "Renamed", itemType: "Song", lengthInSeconds: 300)
        XCTAssertNotEqual(router.digest().hashes.plan, before.plan)
    }

    private func makeHub(_ engine: CueEngine) -> (ControlAPIEventHub, [(String, ControlAPIServer.BroadcastAudience)], () -> [(String, ControlAPIServer.BroadcastAudience)]) {
        let router = ControlAPIRouter(engine: engine)
        let server = ControlAPIServer(router: router)
        let hub = ControlAPIEventHub(engine: engine, server: server, router: router)
        let log = HubLog()
        hub.outbound = { log.entries.append(($0, $1)) }
        hubStorage = (hub, server, router)
        return (hub, [], { log.entries })
    }

    private var hubStorage: (ControlAPIEventHub, ControlAPIServer, ControlAPIRouter)?

    private func events(_ log: [(String, ControlAPIServer.BroadcastAudience)], _ name: String, _ audience: ControlAPIServer.BroadcastAudience) -> [[String: Any]] {
        log.compactMap { entry -> [String: Any]? in
            guard let json = try? JSONSerialization.jsonObject(with: Data(entry.0.utf8)) as? [String: Any],
                  json["event"] as? String == name else { return nil }
            switch (entry.1, audience) {
            case (.all, _): return json
            case (.legacy, .legacy), (.v2, .v2): return json
            default: return nil
            }
        }
    }

    func testV2SocketsGetTimerEventsOnlyOnChangeWhileLegacyKeepsTickingEverySecond() {
        let engine = makeEngine()
        let (hub, _, log) = makeHub(engine)
        hub.flush()
        let baseline = log().count

        for _ in 0..<3 {
            clock.addTimeInterval(1)
            engine.tickTimer()
            hub.flush()
        }
        var sent = Array(log().dropFirst(baseline))
        XCTAssertEqual(events(sent, "timer", .legacy).count, 3)
        XCTAssertEqual(events(sent, "timer", .v2).count, 0)
        XCTAssertTrue(sent.allSatisfy { $0.1 == .legacy })

        engine.toggleTimerRunning()
        hub.flush()
        sent = Array(log().dropFirst(baseline + 3))
        XCTAssertTrue(sent.contains { $0.1 == .v2 })
        let v2Timer = events(sent, "timer", .v2)
        XCTAssertEqual(v2Timer.count, 1)
        let data = v2Timer[0]["data"] as? [String: Any]
        let timer = data?["timer"] as? [String: Any]
        let anchor = timer?["anchor"] as? [String: Any]
        XCTAssertEqual(anchor?["isRunning"] as? Bool, false)
    }

    func testStateEventsGoToEverySocketUnchanged() {
        let engine = makeEngine()
        let (hub, _, log) = makeHub(engine)
        hub.flush()
        _ = engine.addWaypoint(name: "Other")
        hub.flush()
        let states = log().filter { entry in
            (try? JSONSerialization.jsonObject(with: Data(entry.0.utf8)) as? [String: Any])?["event"] as? String == "state"
        }
        XCTAssertEqual(states.count, 2)
        XCTAssertTrue(states.allSatisfy { $0.1 == .all })
    }

    func testDigestEventIsSentToV2SocketsOnlyAndMatchesSyncHash() throws {
        let engine = makeEngine()
        let (hub, _, log) = makeHub(engine)
        hub.sendDigest()
        let entry = try XCTUnwrap(log().last)
        XCTAssertEqual(entry.1, .v2)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(entry.0.utf8)) as? [String: Any])
        XCTAssertEqual(json["event"] as? String, "digest")
        let data = try XCTUnwrap(json["data"] as? [String: Any])
        let hashes = try XCTUnwrap(data["hashes"] as? [String: String])
        XCTAssertEqual(Set(hashes.keys), ["roles", "timer", "plan", "messages"])
        XCTAssertEqual(hashes["roles"], SyncHash.roles(engine.roles))
        XCTAssertEqual(hashes["plan"], SyncHash.plan(items: engine.planItems, activeItemIndex: engine.activeItemIndex))
        XCTAssertEqual(hashes["timer"], SyncHash.timer(engine.currentAnchor))
        XCTAssertNotNil(data["rev"] as? Int)
        XCTAssertNotNil(data["serverNowMs"] as? Int)
    }

    func testHubBuildsAndSendsNothingWhileNoSocketIsConnected() {
        let engine = makeEngine()
        let (hub, _, log) = makeHub(engine)
        var connected = false
        hub.hasClients = { connected }
        hub.flush()
        hub.sendDigest()
        engine.toggleTimerRunning()
        hub.flush()
        XCTAssertTrue(log().isEmpty)
        connected = true
        hub.flush()
        XCTAssertEqual(events(log(), "state", .all).count, 1)
    }

    func testEpochRidesOnHelloTimerAndDigestData() throws {
        let engine = makeEngine()
        let (hub, _, log) = makeHub(engine)
        let router = ControlAPIRouter(engine: engine)
        XCTAssertEqual(router.snapshot().epoch, engine.syncV2.epoch)
        XCTAssertEqual(router.digest().epoch, engine.syncV2.epoch)
        XCTAssertEqual(router.timerSnapshot().epoch, engine.syncV2.epoch)
        hub.flush()
        clock.addTimeInterval(1)
        engine.tickTimer()
        hub.flush()
        let timer = try XCTUnwrap(events(log(), "timer", .legacy).last)
        XCTAssertEqual((timer["data"] as? [String: Any])?["epoch"] as? Int, engine.syncV2.epoch)
        hub.sendDigest()
        let digest = try XCTUnwrap(events(log(), "digest", .v2).last)
        XCTAssertEqual((digest["data"] as? [String: Any])?["epoch"] as? Int, engine.syncV2.epoch)
    }
}

private final class HubLog: @unchecked Sendable {
    var entries: [(String, ControlAPIServer.BroadcastAudience)] = []
}

extension ControlAPIServer.BroadcastAudience: Equatable {}
