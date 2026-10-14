// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

private final class ClockBox {
    var value: Date
    init(_ value: Date) { self.value = value }
    var ms: Int { Int((value.timeIntervalSince1970 * 1000).rounded()) }
}

private final class Outbox {
    var sent: [(packet: CuePacket, target: OutboundTarget)] = []

    func packets(_ type: CuePacket.PacketType) -> [CuePacket] {
        lanPackets(type)
    }

    func targets(_ type: CuePacket.PacketType) -> [OutboundTarget] {
        sent.filter { $0.packet.type == type && !$0.target.isRelay }.map(\.target)
    }

    func relayPackets(_ type: CuePacket.PacketType) -> [CuePacket] {
        sent.filter { $0.packet.type == type && $0.target.isRelay }.map(\.packet)
    }

    func lanPackets(_ type: CuePacket.PacketType) -> [CuePacket] {
        sent.filter { $0.packet.type == type && !$0.target.isRelay }.map(\.packet)
    }

    func clear() { sent = [] }
}

private extension OutboundTarget {
    var isLegacyLAN: Bool { if case .lan(.legacy) = self { return true } else { return false } }
    var isV2LAN: Bool { if case .lan(.v2) = self { return true } else { return false } }
    var isRelay: Bool { if case .relay = self { return true } else { return false } }
    func isConnection(_ id: LANConnectionID) -> Bool { if case .lan(.connection(let other)) = self { return other == id } else { return false } }
}

private final class ConnectionToken {}

@MainActor
class SyncV2TestCase: XCTestCase {
    fileprivate var clock = ClockBox(Date(timeIntervalSince1970: 1_760_000_000))
    fileprivate var outbox = Outbox()
    fileprivate let connectionToken = ConnectionToken()

    var connection: LANConnectionID { LANConnectionID(raw: ObjectIdentifier(connectionToken)) }

    override func setUp() {
        super.setUp()
        clearPersistedState()
        clock = ClockBox(Date(timeIntervalSince1970: 1_760_000_000))
        outbox = Outbox()
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

    fileprivate func makeProducer() -> CueEngine {
        let engine = CueEngine(startsNetworking: false)
        engine.timerClock = { [clock] in clock.value }
        let box = outbox
        engine.outboundObserver = { box.sent.append(($0, $1)) }
        engine.roles = [RoleCue(id: "host", name: "Host"), RoleCue(id: "band", name: "Band")]
        engine.importFlow(title: "Plan", items: [
            PCOTimerItem(id: "a", title: "Song", itemType: "Song", lengthInSeconds: 300),
            PCOTimerItem(id: "b", title: "Sermon", itemType: "Item", lengthInSeconds: 1800),
        ])
        outbox.clear()
        return engine
    }

    fileprivate func makeClient() -> CueEngine {
        let engine = CueEngine(isMasterServer: false, startsNetworking: false)
        engine.timerClock = { [clock] in clock.value }
        let box = outbox
        engine.outboundObserver = { box.sent.append(($0, $1)) }
        return engine
    }

    fileprivate func anchorPacket(rev: Int, anchor: TimerAnchor?, item: PCOTimerItem?) -> CuePacket {
        var packet = CuePacket(type: .timerAnchor, senderId: "producer", timerItem: item)
        packet.rev = rev
        packet.anchor = anchor
        return packet
    }

    fileprivate func ping(version: Int?) -> CuePacket {
        var packet = CuePacket(type: .ping, senderId: "pager")
        packet.proto = version
        return packet
    }
}

@MainActor
final class SyncV2ProducerTests: SyncV2TestCase {
    func testAnchorIsCreatedOnEveryTimerChangingEvent() {
        let engine = makeProducer()
        var anchor = try! XCTUnwrap(engine.currentAnchor)
        XCTAssertEqual(anchor.itemId, "a")
        XCTAssertEqual(anchor.lengthInSeconds, 300)
        XCTAssertEqual(anchor.elapsedMs, 0)
        XCTAssertEqual(anchor.anchorMs, clock.ms)
        XCTAssertTrue(anchor.isRunning)

        clock.value.addTimeInterval(12.5)
        engine.tickTimer()
        engine.toggleTimerRunning()
        anchor = try! XCTUnwrap(engine.currentAnchor)
        XCTAssertFalse(anchor.isRunning)
        XCTAssertEqual(anchor.elapsedMs, 12_500)
        XCTAssertEqual(anchor.anchorMs, clock.ms)
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 12)

        clock.value.addTimeInterval(5)
        engine.toggleTimerRunning()
        anchor = try! XCTUnwrap(engine.currentAnchor)
        XCTAssertTrue(anchor.isRunning)
        XCTAssertEqual(anchor.elapsedMs, 12_500)
        XCTAssertEqual(anchor.anchorMs, clock.ms)

        clock.value.addTimeInterval(3)
        engine.adjustTimerRemainingTime(bySeconds: 60)
        anchor = try! XCTUnwrap(engine.currentAnchor)
        XCTAssertEqual(anchor.lengthInSeconds, 360)
        XCTAssertEqual(anchor.elapsedMs, 15_500)

        engine.setTimerRemainingTime(seconds: 100)
        anchor = try! XCTUnwrap(engine.currentAnchor)
        XCTAssertEqual(anchor.lengthInSeconds, 115)

        engine.resetTimer()
        anchor = try! XCTUnwrap(engine.currentAnchor)
        XCTAssertEqual(anchor.elapsedMs, 0)
        XCTAssertEqual(anchor.anchorMs, clock.ms)

        engine.nextPlanItem()
        anchor = try! XCTUnwrap(engine.currentAnchor)
        XCTAssertEqual(anchor.itemId, "b")
        XCTAssertEqual(anchor.lengthInSeconds, 1800)

        engine.setDurationIsActual(id: "b", isActual: true)
        XCTAssertEqual(engine.currentAnchor?.isDurationActual, true)
    }

    func testEachTimerEventPublishesOneAnchorToV2AndOneTimerUpdateToLegacy() {
        let engine = makeProducer()
        engine.toggleTimerRunning()
        XCTAssertEqual(outbox.packets(.timerAnchor).count, 1)
        XCTAssertEqual(outbox.targets(.timerAnchor).first?.isV2LAN, true)
        XCTAssertEqual(outbox.packets(.timerUpdate).count, 1)
        XCTAssertEqual(outbox.targets(.timerUpdate).first?.isLegacyLAN, true)

        let anchorPacket = outbox.packets(.timerAnchor)[0]
        XCTAssertEqual(anchorPacket.anchor, engine.currentAnchor)
        XCTAssertEqual(anchorPacket.timerItem?.id, "a")
        XCTAssertEqual(anchorPacket.proto, nil)

        engine.toggleTimerRunning()
        engine.resetTimer()
        let revs = outbox.packets(.timerAnchor).compactMap(\.rev)
        XCTAssertEqual(revs, [revs[0], revs[0] + 1, revs[0] + 2])
    }

    func testNoActiveItemPublishesANullAnchor() {
        let engine = makeProducer()
        engine.resetToNewDocument()
        let last = outbox.packets(.timerAnchor).last
        XCTAssertNotNil(last)
        XCTAssertNil(last?.anchor)
        XCTAssertNil(last?.timerItem)
        XCTAssertNil(engine.currentAnchor)
    }

    func testTicksSendLegacyTimerAndCueUpdatesButNothingPeriodicToV2ExceptDigest() {
        let engine = makeProducer()
        for _ in 0..<5 {
            clock.value.addTimeInterval(1)
            engine.tickTimer()
        }
        XCTAssertEqual(outbox.packets(.timerUpdate).count, 1)
        XCTAssertEqual(outbox.packets(.cueUpdate).count, 1)
        XCTAssertTrue(outbox.targets(.timerUpdate).allSatisfy(\.isLegacyLAN))
        XCTAssertTrue(outbox.targets(.cueUpdate).allSatisfy(\.isLegacyLAN))
        XCTAssertTrue(outbox.packets(.timerAnchor).isEmpty)
        XCTAssertTrue(outbox.packets(.digest).isEmpty)

        for _ in 0..<5 {
            clock.value.addTimeInterval(1)
            engine.tickTimer()
        }
        XCTAssertEqual(outbox.packets(.digest).count, 1)
        XCTAssertTrue(outbox.targets(.digest).allSatisfy(\.isV2LAN))
        XCTAssertEqual(outbox.packets(.timerUpdate).count, 2)
        XCTAssertTrue(outbox.packets(.timerAnchor).isEmpty)
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 10)
    }

    func testProducerStampsUtcOffsetOnAnchorPongAndLegacyTimerUpdate() {
        let engine = makeProducer()
        var offset = -14400
        engine.timeZoneProvider = { TimeZone(secondsFromGMT: offset)! }
        engine.toggleTimerRunning()
        XCTAssertEqual(outbox.packets(.timerAnchor).first?.utcOffsetSeconds, -14400)
        XCTAssertEqual(outbox.packets(.timerUpdate).first?.utcOffsetSeconds, -14400)
        offset = 19800
        outbox.clear()
        engine.handlePacket(ping(version: 2), origin: .lanServer(connection))
        XCTAssertEqual(outbox.packets(.pong).first?.utcOffsetSeconds, 19800)
        XCTAssertEqual(outbox.packets(.timerAnchor).first?.utcOffsetSeconds, 19800)
        outbox.clear()
        engine.handlePacket(ping(version: nil), origin: .lanServer(connection))
        XCTAssertEqual(outbox.packets(.pong).first?.utcOffsetSeconds, 19800)
    }

    func testUtcOffsetCodableIsBackwardCompatible() throws {
        var packet = CuePacket(type: .pong, senderId: "x")
        let without = try JSONSerialization.jsonObject(with: try XCTUnwrap(packet.encode())) as! [String: Any]
        XCTAssertNil(without["utcOffsetSeconds"])
        XCTAssertNil(CuePacket.decode(from: try XCTUnwrap(packet.encode()))?.utcOffsetSeconds)
        packet.utcOffsetSeconds = -14400
        let with = try JSONSerialization.jsonObject(with: try XCTUnwrap(packet.encode())) as! [String: Any]
        XCTAssertEqual(with["utcOffsetSeconds"] as? Int, -14400)
        XCTAssertEqual(CuePacket.decode(from: try XCTUnwrap(packet.encode()))?.utcOffsetSeconds, -14400)
    }

    func testDigestContentEqualsSyncHashOfTheState() {
        let engine = makeProducer()
        engine.addMessages([InterTeamMessage(id: "m1", text: "hi", timestamp: Date(timeIntervalSince1970: 5))])
        for _ in 0..<10 {
            clock.value.addTimeInterval(1)
            engine.tickTimer()
        }
        let digest = try! XCTUnwrap(outbox.packets(.digest).last)
        XCTAssertEqual(digest.hashes?.roles, SyncHash.roles(engine.roles))
        XCTAssertEqual(digest.hashes?.timer, SyncHash.timer(engine.currentAnchor))
        XCTAssertEqual(digest.hashes?.messages, SyncHash.messages(ids: ["m1"]))
        XCTAssertNil(digest.hashes?.plan)
        XCTAssertEqual(digest.digestMs, clock.ms)
        XCTAssertNotNil(digest.rev)
    }

    func testV2PingIsAnsweredOnlyToThatConnectionWithPongAnchorAndDigest() {
        let engine = makeProducer()
        engine.handlePacket(ping(version: 2), origin: .lanServer(connection))
        XCTAssertEqual(outbox.sent.map(\.packet.type), [.pong, .timerAnchor, .digest])
        XCTAssertTrue(outbox.sent.allSatisfy { $0.target.isConnection(connection) })
        let pong = outbox.packets(.pong)[0]
        XCTAssertEqual(pong.proto, 2)
        XCTAssertEqual(pong.roleCues?.count, 2)
        XCTAssertEqual(pong.rev, outbox.packets(.digest)[0].rev)
        XCTAssertEqual(outbox.packets(.timerAnchor)[0].anchor, engine.currentAnchor)
    }

    func testLegacyPingStillGetsOnePongForLegacyConnections() {
        let engine = makeProducer()
        engine.handlePacket(ping(version: nil), origin: .lanServer(connection))
        XCTAssertEqual(outbox.sent.filter { !$0.target.isRelay }.map(\.packet.type), [.pong])
        XCTAssertTrue(outbox.targets(.pong)[0].isLegacyLAN)
        XCTAssertNil(outbox.packets(.pong)[0].proto)
        XCTAssertNil(outbox.packets(.pong)[0].rev)
    }

    func testV2PingOverRelayMarksRelayAndLeavesLegacyReplyIntact() {
        let engine = makeProducer()
        engine.handlePacket(ping(version: 2), origin: .relay)
        XCTAssertFalse(outbox.targets(.pong).contains { $0.isLegacyLAN })
        XCTAssertEqual(outbox.relayPackets(.pong).count, 1)
        XCTAssertEqual(outbox.relayPackets(.pong)[0].rev, outbox.relayPackets(.digest)[0].rev)
        XCTAssertEqual(outbox.relayPackets(.pong)[0].to, "pager")
        XCTAssertEqual(outbox.relayPackets(.timerAnchor).count, 1)
        XCTAssertEqual(outbox.relayPackets(.digest).count, 1)
        outbox.clear()
        engine.toggleTimerRunning()
        XCTAssertEqual(outbox.relayPackets(.timerAnchor).count, 1)
        XCTAssertEqual(outbox.relayPackets(.timerUpdate).count, 1)
    }

    func testCueStateChangesSendDeltaToV2AndFullUpdateToLegacy() {
        let engine = makeProducer()
        engine.handlePacket(ping(version: 2), origin: .lanServer(connection))
        outbox.clear()

        engine.setCueForRole(id: "host", state: .go)
        XCTAssertEqual(outbox.packets(.cueDelta).count, 1)
        XCTAssertTrue(outbox.targets(.cueDelta)[0].isV2LAN)
        let delta = outbox.packets(.cueDelta)[0]
        XCTAssertEqual(delta.cueDeltas?.map(\.id), ["host"])
        XCTAssertEqual(delta.cueDeltas?.first?.state, .go)
        XCTAssertNotNil(delta.rev)
        XCTAssertEqual(outbox.packets(.cueUpdate).count, 1)
        XCTAssertTrue(outbox.targets(.cueUpdate)[0].isLegacyLAN)
        XCTAssertNotNil(outbox.packets(.cueUpdate)[0].timerItem)
        XCTAssertNil(outbox.packets(.cueUpdate)[0].rev)
    }

    func testStructuralChangesSendAFullCueUpdateToV2() {
        let engine = makeProducer()
        engine.handlePacket(ping(version: 2), origin: .lanServer(connection))
        outbox.clear()

        engine.renameRole(id: "host", name: "Lead")
        let v2 = zip(outbox.packets(.cueUpdate), outbox.targets(.cueUpdate)).filter { $0.1.isV2LAN }.map(\.0)
        XCTAssertEqual(v2.count, 1)
        XCTAssertEqual(v2[0].roleCues?.first?.name, "Lead")
        XCTAssertNil(v2[0].timerItem)
        XCTAssertNotNil(v2[0].rev)
        XCTAssertTrue(outbox.packets(.cueDelta).isEmpty)
    }

    func testRevIncreasesAcrossStateChangingBroadcasts() {
        let engine = makeProducer()
        engine.setCueForRole(id: "host", state: .standby)
        engine.toggleTimerRunning()
        engine.renameRole(id: "band", name: "Players")
        let revs = outbox.sent.compactMap { $0.target.isV2LAN ? $0.packet.rev : nil }
        XCTAssertEqual(revs.count, 3)
        XCTAssertEqual(revs, revs.sorted())
        XCTAssertEqual(Set(revs).count, 3)
    }

    func testSyncRequestsGetAReplyToThatConnectionOnly() throws {
        let engine = makeProducer()
        var request = CuePacket(type: .sync, senderId: "pager")
        request.t0 = 1234
        request.receivedAtMs = 1_760_000_000_123.4
        engine.handlePacket(request, origin: .lanServer(connection))
        XCTAssertEqual(outbox.sent.count, 1)
        XCTAssertTrue(outbox.sent[0].target.isConnection(connection))
        let reply = outbox.sent[0].packet
        XCTAssertEqual(reply.type, .syncReply)
        XCTAssertEqual(reply.t0, 1234)
        XCTAssertEqual(reply.t1, 1_760_000_000_123)
        let wire = try XCTUnwrap(CuePacket.decode(from: XCTUnwrap(reply.encode())))
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(wire.t2), try XCTUnwrap(wire.t1))
    }

    func testExternalChangesToTheTimerAreReanchoredAndPublished() {
        let engine = makeProducer()
        clock.value.addTimeInterval(20)
        engine.tickTimer()
        outbox.clear()
        engine.activeTimerItem?.elapsedSeconds = 300
        engine.evaluateMasterTimer()
        XCTAssertEqual(outbox.packets(.timerAnchor).count, 1)
        XCTAssertEqual(engine.currentAnchor?.elapsedMs, 300_000)
        engine.evaluateMasterTimer()
        XCTAssertEqual(outbox.packets(.timerAnchor).count, 1)
    }

    func testPublishedElapsedFlipsAtAnchorBoundariesAndOnlyWhenTheIntegerChanges() {
        let engine = makeProducer()
        var changes = 0
        let observation = engine.$activeTimerItem.dropFirst().sink { _ in changes += 1 }
        let anchorMs = try! XCTUnwrap(engine.currentAnchor).anchorMs
        for offset in stride(from: 100, through: 3_900, by: 100) {
            clock.value = Date(timeIntervalSince1970: Double(anchorMs + offset) / 1000)
            engine.evaluateMasterTimer()
            XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, offset / 1000, "at +\(offset)")
        }
        XCTAssertEqual(changes, 3)
        observation.cancel()
    }

    func testPausedTimeIsNotCountedAfterAnchoredResume() {
        let engine = makeProducer()
        clock.value.addTimeInterval(10.4)
        engine.toggleTimerRunning()
        clock.value.addTimeInterval(500)
        engine.evaluateMasterTimer()
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 10)
        engine.toggleTimerRunning()
        clock.value.addTimeInterval(0.6)
        engine.evaluateMasterTimer()
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 11)
    }
}

@MainActor
final class SyncV2ClientTests: SyncV2TestCase {
    private func establishOffset(_ engine: CueEngine, offsetMs: Double) {
        let t0 = clock.value.timeIntervalSince1970 * 1000
        engine.syncV2.estimator.add(ClockSyncSample(t0: t0, t1: t0 + offsetMs, t2: t0 + offsetMs, t3: t0))
    }

    private func runningAnchor(elapsedMs: Int, anchorMs: Int, running: Bool = true, id: String = "a") -> TimerAnchor {
        TimerAnchor(itemId: id, lengthInSeconds: 300, elapsedMs: elapsedMs, anchorMs: anchorMs, isRunning: running, isDurationActual: false)
    }

    func testClientAnnouncesProtoTwoInItsCatchUpPing() {
        let engine = makeClient()
        engine.requestCatchUp()
        let ping = try! XCTUnwrap(outbox.lanPackets(.ping).first)
        XCTAssertEqual(ping.proto, 2)
    }

    func testBurstStartsWithOneSyncAndFollowsWithFourMore() async {
        let engine = makeClient()
        engine.startSyncBurst()
        XCTAssertEqual(outbox.lanPackets(.sync).count, 1)
        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(outbox.lanPackets(.sync).count, 5)
        XCTAssertEqual(engine.syncV2.pendingSyncT0.count >= 1, true)
    }

    func testSyncRepliesFeedTheEstimatorOnlyForPendingRequests() {
        let engine = makeClient()
        engine.sendSyncSample()
        let t0 = try! XCTUnwrap(outbox.lanPackets(.sync).first?.t0)
        var stray = CuePacket(type: .syncReply, senderId: "producer")
        stray.t0 = t0 + 1
        stray.t1 = t0 + 5000
        stray.t2 = t0 + 5000
        stray.receivedAtMs = Double(t0) + 10
        engine.handlePacket(stray)
        XCTAssertNil(engine.syncV2.estimator.offsetMs)

        var reply = stray
        reply.t0 = t0
        reply.to = engine.deviceId
        engine.handlePacket(reply)
        XCTAssertEqual(engine.syncV2.estimator.offsetMs ?? 0, 5000 - 5, accuracy: 0.001)
        XCTAssertTrue(engine.syncV2.producerIsV2)
        engine.handlePacket(reply)
        XCTAssertEqual(engine.syncV2.estimator.samples.count, 1)
    }

    func testTimerIsComputedFromAnchorAndOffsetNotFromTheLocalClock() {
        let engine = makeClient()
        establishOffset(engine, offsetMs: 5_000)
        let producerNow = clock.ms + 5_000
        let item = PCOTimerItem(id: "a", title: "Song", lengthInSeconds: 300, elapsedSeconds: 0, isRunning: true)
        engine.handlePacket(anchorPacket(rev: 1, anchor: runningAnchor(elapsedMs: 10_000, anchorMs: producerNow - 2_500), item: item))
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 12)
        XCTAssertEqual(engine.activeTimerItem?.isRunning, true)

        clock.value.addTimeInterval(0.6)
        engine.refreshHeldTimer()
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 13)

        engine.handlePacket(anchorPacket(rev: 2, anchor: runningAnchor(elapsedMs: 13_100, anchorMs: producerNow + 600, running: false), item: item))
        clock.value.addTimeInterval(60)
        engine.refreshHeldTimer()
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 13)
        XCTAssertEqual(engine.activeTimerItem?.isRunning, false)
    }

    func testAnchorBeforeAnyOffsetFallsBackToThePacketsOwnItemThenSwitchesToLocalMath() {
        let engine = makeClient()
        let producerNow = clock.ms
        let item = PCOTimerItem(id: "a", title: "Song", lengthInSeconds: 300, elapsedSeconds: 7, isRunning: true)
        engine.handlePacket(anchorPacket(rev: 1, anchor: runningAnchor(elapsedMs: 7_000, anchorMs: producerNow), item: item))
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 7)
        establishOffset(engine, offsetMs: 0)
        clock.value.addTimeInterval(2.2)
        engine.refreshHeldTimer()
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 9)
    }

    func testNullAnchorClearsTheTimer() {
        let engine = makeClient()
        establishOffset(engine, offsetMs: 0)
        let item = PCOTimerItem(id: "a", title: "Song", lengthInSeconds: 300, isRunning: true)
        engine.handlePacket(anchorPacket(rev: 1, anchor: runningAnchor(elapsedMs: 0, anchorMs: clock.ms), item: item))
        XCTAssertNotNil(engine.activeTimerItem)
        engine.handlePacket(anchorPacket(rev: 2, anchor: nil, item: nil))
        XCTAssertNil(engine.activeTimerItem)
        XCTAssertNil(engine.currentAnchor)
    }

    func testLegacyTimerAndCueUpdatesAreIgnoredForTheTimerOnceAnchored() {
        let engine = makeClient()
        establishOffset(engine, offsetMs: 0)
        let item = PCOTimerItem(id: "a", title: "Song", lengthInSeconds: 300, elapsedSeconds: 0, isRunning: true)
        engine.handlePacket(anchorPacket(rev: 1, anchor: runningAnchor(elapsedMs: 50_000, anchorMs: clock.ms), item: item))
        var stale = item
        stale.elapsedSeconds = 999
        engine.handlePacket(CuePacket(type: .timerUpdate, senderId: "producer", timerItem: stale))
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 50)
        engine.handlePacket(CuePacket(type: .cueUpdate, senderId: "producer", roleCues: [RoleCue(id: "x", name: "X")], timerItem: stale))
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 50)
        XCTAssertEqual(engine.roles.map(\.id), ["x"])
    }

    func testLegacyProducerKeepsTheOldBehaviour() {
        let engine = makeClient()
        let item = PCOTimerItem(id: "a", title: "Song", lengthInSeconds: 300, elapsedSeconds: 40, isRunning: true)
        engine.handlePacket(CuePacket(type: .timerUpdate, senderId: "producer", timerItem: item))
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 40)
        XCTAssertFalse(engine.syncV2.producerIsV2)
        engine.tickTimer()
        clock.value.addTimeInterval(7)
        engine.tickTimer()
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 47)
        var newer = item
        newer.elapsedSeconds = 100
        engine.handlePacket(CuePacket(type: .cueUpdate, senderId: "producer", roleCues: [RoleCue(id: "r", name: "R")], timerItem: newer))
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 100)
        XCTAssertTrue(engine.outboxIsQuiet(outbox))
    }

    func testLowerRevPacketsAreIgnoredAndAPongRebasesAfterAReconnect() {
        let engine = makeClient()
        engine.roles = [RoleCue(id: "host", name: "Host")]
        func delta(_ rev: Int, _ state: CueState) -> CuePacket {
            var packet = CuePacket(type: .cueDelta, senderId: "producer")
            packet.rev = rev
            packet.cueDeltas = [CueDelta(id: "host", state: state, lastUpdated: Date())]
            return packet
        }
        engine.handlePacket(delta(5, .go))
        XCTAssertEqual(engine.roles.first?.state, .go)
        engine.handlePacket(delta(4, .off))
        XCTAssertEqual(engine.roles.first?.state, .go)
        engine.handlePacket(delta(6, .standby))
        XCTAssertEqual(engine.roles.first?.state, .standby)

        var pong = CuePacket(type: .pong, senderId: "producer", roleCues: [RoleCue(id: "host", name: "Host", state: .off)], messages: [])
        pong.proto = 2
        pong.rev = 1
        engine.handlePacket(pong)
        engine.handlePacket(delta(2, .go))
        XCTAssertEqual(engine.roles.first?.state, .go)
        engine.handlePacket(delta(1, .off))
        XCTAssertEqual(engine.roles.first?.state, .go)
    }

    func testCueDeltaForAnUnknownRoleAsksForACatchUp() {
        let engine = makeClient()
        engine.roles = [RoleCue(id: "host", name: "Host")]
        var packet = CuePacket(type: .cueDelta, senderId: "producer")
        packet.rev = 1
        packet.cueDeltas = [CueDelta(id: "ghost", state: .go, lastUpdated: Date())]
        engine.handlePacket(packet)
        XCTAssertEqual(outbox.lanPackets(.ping).count, 1)
    }

    private func digest(rev: Int, hashes: SyncHash.Hashes) -> CuePacket {
        var packet = CuePacket(type: .digest, senderId: "producer")
        packet.rev = rev
        packet.hashes = hashes
        return packet
    }

    func testMatchingDigestNeedsNoAction() {
        let engine = makeClient()
        engine.roles = [RoleCue(id: "host", name: "Host", state: .go)]
        engine.handlePacket(digest(rev: 1, hashes: engine.localHashes()))
        XCTAssertTrue(outbox.lanPackets(.ping).isEmpty)
        XCTAssertTrue(engine.syncV2.producerIsV2)
    }

    func testDigestMismatchRequestsExactlyOneCatchUp() {
        let engine = makeClient()
        engine.roles = [RoleCue(id: "host", name: "Host", state: .go)]
        var hashes = engine.localHashes()
        hashes.roles = SyncHash.roles([RoleCue(id: "host", name: "Host", state: .off)])
        engine.handlePacket(digest(rev: 1, hashes: hashes))
        engine.handlePacket(digest(rev: 2, hashes: hashes))
        XCTAssertEqual(outbox.lanPackets(.ping).count, 1)
        XCTAssertEqual(outbox.lanPackets(.ping)[0].proto, 2)
    }

    func testEachDifferingSectionTriggersACatchUp() {
        for section in [SyncHash.Section.roles, .timer, .messages] {
            let engine = makeClient()
            outbox.clear()
            var hashes = engine.localHashes()
            switch section {
            case .roles: hashes.roles = "0000000000000000"
            case .timer: hashes.timer = SyncHash.timer(TimerAnchor(itemId: "z", lengthInSeconds: 1, elapsedMs: 0, anchorMs: 0, isRunning: false, isDurationActual: false))
            default: hashes.messages = SyncHash.messages(ids: ["unknown"])
            }
            engine.handlePacket(digest(rev: 1, hashes: hashes))
            XCTAssertEqual(outbox.lanPackets(.ping).count, 1, "\(section)")
        }
    }

    func testV2PongReplacesMessagesAndAnswersTheCatchUp() {
        let engine = makeClient()
        engine.addMessages([InterTeamMessage(id: "stale", text: "x", timestamp: Date(timeIntervalSince1970: 1))])
        var wrong = engine.localHashes()
        wrong.roles = "ffffffffffffffff"
        engine.handlePacket(digest(rev: 1, hashes: wrong))
        XCTAssertTrue(engine.syncV2.catchUpInFlight)
        var pong = CuePacket(type: .pong, senderId: "producer", roleCues: [], messages: [InterTeamMessage(id: "fresh", text: "y", timestamp: Date(timeIntervalSince1970: 2))])
        pong.proto = 2
        pong.rev = 1
        engine.handlePacket(pong)
        XCTAssertEqual(engine.recentMessages.map(\.id), ["fresh"])
        XCTAssertFalse(engine.syncV2.catchUpInFlight)
    }

    func testStalenessIsTwentyFiveSecondsForV2AndTwelveForLegacy() {
        let engine = makeClient()
        engine.lastProducerPacketAt = Date().addingTimeInterval(-20)
        engine.tickTimer()
        XCTAssertFalse(engine.isProducerLive)

        engine.handlePacket(digest(rev: 1, hashes: engine.localHashes()))
        engine.lastProducerPacketAt = Date().addingTimeInterval(-20)
        engine.tickTimer()
        XCTAssertTrue(engine.isProducerLive)
        engine.lastProducerPacketAt = Date().addingTimeInterval(-30)
        engine.tickTimer()
        XCTAssertFalse(engine.isProducerLive)
    }

    func testEveryV2PacketCountsAsLiveness() {
        let engine = makeClient()
        XCTAssertFalse(engine.isProducerLive)
        engine.handlePacket(digest(rev: 1, hashes: engine.localHashes()))
        XCTAssertTrue(engine.isProducerLive)
        XCTAssertTrue(engine.hasSyncedWithProducer)
    }

    func testForegroundSendsOneSyncAndAMasterIgnoresIt() {
        let engine = makeClient()
        engine.deviceDidBecomeActive()
        XCTAssertEqual(outbox.lanPackets(.sync).count, 1)
        outbox.clear()
        let producer = makeProducer()
        producer.deviceDidBecomeActive()
        XCTAssertTrue(outbox.lanPackets(.sync).isEmpty)
    }

    func testThirtySecondSyncCadenceOnlyForV2Producers() {
        let engine = makeClient()
        for _ in 0..<30 { engine.tickTimer() }
        XCTAssertTrue(outbox.lanPackets(.sync).isEmpty)
        engine.handlePacket(digest(rev: 1, hashes: engine.localHashes()))
        outbox.clear()
        for _ in 0..<30 { engine.tickTimer() }
        XCTAssertEqual(outbox.lanPackets(.sync).count, 1)
    }
}

private extension CueEngine {
    func outboxIsQuiet(_ outbox: Outbox) -> Bool {
        outbox.sent.allSatisfy { $0.packet.type != .sync }
    }
}

private final class MonoBox {
    var ms: Double = 1_000_000
}

@MainActor
final class SyncV21Tests: SyncV2TestCase {
    private var mono = MonoBox()

    override func setUp() {
        super.setUp()
        mono = MonoBox()
    }

    private func client() -> CueEngine {
        let engine = makeClient()
        let box = mono
        engine.monotonicMsClock = { box.ms }
        return engine
    }

    private func digest(rev: Int, epoch: Int? = nil, to: String? = nil, hashes: SyncHash.Hashes) -> CuePacket {
        var packet = CuePacket(type: .digest, senderId: "producer", timestamp: clock.value.timeIntervalSince1970)
        packet.rev = rev
        packet.epoch = epoch
        packet.to = to
        packet.hashes = hashes
        return packet
    }

    private func anchor(rev: Int, epoch: Int? = 1, to: String? = nil, elapsedMs: Int = 10_000, running: Bool = true) -> CuePacket {
        let item = PCOTimerItem(id: "a", title: "Song", lengthInSeconds: 300, elapsedSeconds: elapsedMs / 1000, isRunning: running)
        let value = TimerAnchor(itemId: "a", lengthInSeconds: 300, elapsedMs: elapsedMs, anchorMs: clock.ms, isRunning: running, isDurationActual: false)
        var packet = anchorPacket(rev: rev, anchor: value, item: item)
        packet.epoch = epoch
        packet.to = to
        packet.timestamp = clock.value.timeIntervalSince1970
        return packet
    }

    private func giveOffset(_ engine: CueEngine, _ offsetMs: Double = 0) {
        let t0 = clock.value.timeIntervalSince1970 * 1000
        engine.syncV2.estimator.add(ClockSyncSample(t0: t0, t1: t0 + offsetMs, t2: t0 + offsetMs, t3: t0, monotonicMs: mono.ms), nowMonotonicMs: mono.ms)
    }

    private func v2Client() -> CueEngine {
        let engine = client()
        engine.handlePacket(digest(rev: 0, epoch: 1, hashes: engine.localHashes()))
        giveOffset(engine)
        outbox.clear()
        return engine
    }

    func testProducerStampsItsEpochOnEveryV2Packet() {
        let producer = makeProducer()
        let epoch = producer.syncV2.epoch
        XCTAssertTrue((1...Int(Int32.max)).contains(epoch))
        producer.handlePacket(ping(version: 2), origin: .lanServer(connection))
        producer.toggleTimerRunning()
        producer.setCueForRole(id: "band", state: .go)
        producer.tickTimer()
        var sync = CuePacket(type: .sync, senderId: "pager")
        sync.t0 = 5
        producer.handlePacket(sync, origin: .lanServer(connection))
        for type in [CuePacket.PacketType.pong, .timerAnchor, .digest, .cueDelta, .syncReply] {
            let packets = outbox.sent.map(\.packet).filter { $0.type == type }
            XCTAssertFalse(packets.isEmpty, type.rawValue)
            XCTAssertTrue(packets.allSatisfy { $0.epoch == epoch }, type.rawValue)
        }
    }

    func testCatchUpPacketsAndSyncRepliesAreAddressedToTheRequester() {
        let producer = makeProducer()
        producer.handlePacket(ping(version: 2), origin: .lanServer(connection))
        XCTAssertTrue(outbox.sent.allSatisfy { $0.packet.to == "pager" })
        var sync = CuePacket(type: .sync, senderId: "other")
        sync.t0 = 9
        outbox.clear()
        producer.handlePacket(sync, origin: .relay)
        XCTAssertEqual(outbox.relayPackets(.syncReply).first?.to, "other")
    }

    func testCatchUpPongCapsMessagesAtTwentyAndFourKilobytesDroppingTheOldest() throws {
        let producer = makeProducer()
        let long = String(repeating: "x", count: 400)
        producer.addMessages((0..<60).map { InterTeamMessage(id: "m\($0)", text: long, timestamp: Date(timeIntervalSince1970: Double($0))) })
        producer.handlePacket(ping(version: 2), origin: .relay)
        let pong = try XCTUnwrap(outbox.relayPackets(.pong).first)
        let data = try XCTUnwrap(pong.encode())
        XCTAssertLessThanOrEqual(data.count, 4096)
        let messages = try XCTUnwrap(pong.messages)
        XCTAssertLessThanOrEqual(messages.count, 20)
        XCTAssertGreaterThan(messages.count, 0)
        XCTAssertEqual(messages.map(\.id), (0..<messages.count).map { "m\(59 - $0)" })
        XCTAssertEqual(pong.proto, 2)
        XCTAssertNotNil(pong.rev)
        XCTAssertNotNil(pong.epoch)

        let few = makeProducer()
        few.recentMessages = []
        few.addMessages((0..<5).map { InterTeamMessage(id: "s\($0)", text: "hi", timestamp: Date(timeIntervalSince1970: Double($0))) })
        outbox.clear()
        few.handlePacket(ping(version: 2), origin: .relay)
        XCTAssertEqual(outbox.relayPackets(.pong).first?.messages?.count, 5)
    }

    func testV2PongReplacesTheMessageList() {
        let engine = v2Client()
        engine.addMessages((0..<5).map { InterTeamMessage(id: "old\($0)", text: "o", timestamp: Date(timeIntervalSince1970: Double($0))) })
        var pong = CuePacket(type: .pong, senderId: "producer", messages: [
            InterTeamMessage(id: "n1", text: "a", timestamp: Date(timeIntervalSince1970: 100)),
            InterTeamMessage(id: "n2", text: "b", timestamp: Date(timeIntervalSince1970: 200)),
        ])
        pong.rev = 3
        pong.proto = 2
        engine.handlePacket(pong)
        XCTAssertEqual(engine.recentMessages.map(\.id), ["n2", "n1"])
    }

    func testPeerPingSyncAndProtoNeverMarkTheProducerAsV2() {
        let engine = client()
        engine.handlePacket(ping(version: 2))
        var sync = CuePacket(type: .sync, senderId: "peer")
        sync.t0 = 1
        sync.proto = 2
        engine.handlePacket(sync)
        var legacyPong = CuePacket(type: .pong, senderId: "producer")
        legacyPong.proto = 2
        engine.handlePacket(legacyPong)
        var foreignReply = CuePacket(type: .syncReply, senderId: "producer")
        foreignReply.t0 = 1
        foreignReply.t1 = 2
        foreignReply.t2 = 3
        engine.handlePacket(foreignReply)
        XCTAssertFalse(engine.syncV2.producerIsV2)

        var v2Pong = CuePacket(type: .pong, senderId: "producer")
        v2Pong.rev = 4
        engine.handlePacket(v2Pong)
        XCTAssertTrue(engine.syncV2.producerIsV2)
    }

    func testAddressedSyncReplyMarksV2AndOthersAreIgnored() {
        let engine = client()
        engine.sendSyncSample()
        let t0 = outbox.lanPackets(.sync)[0].t0!
        var reply = CuePacket(type: .syncReply, senderId: "producer")
        reply.t0 = t0
        reply.t1 = t0 + 5
        reply.t2 = t0 + 5
        reply.receivedAtMs = Double(t0) + 10
        reply.to = "somebody-else"
        engine.handlePacket(reply)
        XCTAssertNil(engine.syncV2.estimator.offsetMs)
        XCTAssertFalse(engine.syncV2.producerIsV2)
        reply.to = engine.deviceId
        engine.handlePacket(reply)
        XCTAssertNotNil(engine.syncV2.estimator.offsetMs)
        XCTAssertTrue(engine.syncV2.producerIsV2)
    }

    func testPacketsAddressedToAnotherPagerAreIgnoredAndOwnOnesApplied() {
        let engine = v2Client()
        var pong = CuePacket(type: .pong, senderId: "producer", roleCues: [RoleCue(id: "x", name: "X")])
        pong.rev = 9
        pong.to = "someone-else"
        engine.handlePacket(pong)
        XCTAssertFalse(engine.roles.contains { $0.id == "x" })
        pong.to = engine.deviceId
        engine.handlePacket(pong)
        XCTAssertTrue(engine.roles.contains { $0.id == "x" })
        engine.handlePacket(anchor(rev: 20, to: "someone-else"))
        XCTAssertNil(engine.syncV2.held)
    }

    func testNewEpochDiscardsAnchorGateSamplesAndCatchesUp() {
        let engine = v2Client()
        engine.handlePacket(anchor(rev: 50, epoch: 1))
        XCTAssertNotNil(engine.syncV2.held)
        XCTAssertEqual(engine.activeTimerItem?.isRunning, true)
        outbox.clear()

        engine.handlePacket(digest(rev: 2, epoch: 2, hashes: engine.localHashes()))
        XCTAssertNil(engine.syncV2.held)
        XCTAssertNil(engine.syncV2.estimator.offsetMs)
        XCTAssertNil(engine.syncV2.gate.highest)
        XCTAssertEqual(engine.syncV2.producerEpoch, 2)
        XCTAssertEqual(engine.activeTimerItem?.isRunning, false)
        XCTAssertEqual(outbox.lanPackets(.ping).count, 1)
        XCTAssertEqual(outbox.lanPackets(.ping).first?.proto, 2)
        XCTAssertEqual(outbox.lanPackets(.sync).count, 1)

        engine.handlePacket(anchor(rev: 3, epoch: 2))
        XCTAssertNotNil(engine.syncV2.held)
    }

    func testLowerRevAfterRestartIsAcceptedOnlyThroughANewEpoch() {
        let engine = v2Client()
        engine.handlePacket(anchor(rev: 500, epoch: 1))
        engine.handlePacket(anchor(rev: 3, epoch: 1, elapsedMs: 99_000))
        XCTAssertEqual(engine.syncV2.held?.anchor.elapsedMs, 10_000)
        engine.handlePacket(anchor(rev: 3, epoch: 2, elapsedMs: 99_000))
        XCTAssertEqual(engine.syncV2.held?.anchor.elapsedMs, 99_000)
    }

    func testStrictRevGateAndBigJumpRule() {
        let engine = v2Client()
        engine.handlePacket(anchor(rev: 5))
        engine.handlePacket(anchor(rev: 5, elapsedMs: 77_000))
        XCTAssertEqual(engine.syncV2.held?.anchor.elapsedMs, 10_000)
        engine.handlePacket(anchor(rev: 4, elapsedMs: 77_000))
        XCTAssertEqual(engine.syncV2.held?.anchor.elapsedMs, 10_000)
        engine.handlePacket(anchor(rev: 5 + 1_000_001, elapsedMs: 77_000))
        XCTAssertEqual(engine.syncV2.held?.anchor.elapsedMs, 10_000)
        engine.handlePacket(anchor(rev: Int.max, elapsedMs: 77_000))
        XCTAssertEqual(engine.syncV2.held?.anchor.elapsedMs, 10_000)
        engine.handlePacket(anchor(rev: 6, elapsedMs: 20_000))
        XCTAssertEqual(engine.syncV2.held?.anchor.elapsedMs, 20_000)
        var pong = CuePacket(type: .pong, senderId: "producer")
        pong.rev = 1
        engine.handlePacket(pong)
        engine.handlePacket(anchor(rev: 2, elapsedMs: 30_000))
        XCTAssertEqual(engine.syncV2.held?.anchor.elapsedMs, 30_000)
    }

    func testAddressedCatchUpAnchorAtThePongRevIsAccepted() {
        let engine = v2Client()
        var pong = CuePacket(type: .pong, senderId: "producer")
        pong.rev = 8
        pong.to = engine.deviceId
        engine.handlePacket(pong)
        engine.handlePacket(anchor(rev: 8, to: engine.deviceId))
        XCTAssertNotNil(engine.syncV2.held)
    }

    func testDigestAtHeldRevIsVerifiedButNeverAdvancesTheGate() {
        let engine = v2Client()
        engine.handlePacket(anchor(rev: 5))
        engine.handlePacket(digest(rev: 5, epoch: 1, hashes: engine.localHashes()))
        XCTAssertEqual(engine.syncV2.gate.highest, 5)
        engine.handlePacket(digest(rev: 40, epoch: 1, hashes: engine.localHashes()))
        XCTAssertEqual(engine.syncV2.gate.highest, 5)
        engine.handlePacket(anchor(rev: 6, elapsedMs: 42_000))
        XCTAssertEqual(engine.syncV2.held?.anchor.elapsedMs, 42_000)
        outbox.clear()
        engine.handlePacket(digest(rev: 1, epoch: 1, hashes: SyncHash.Hashes(roles: "x", timer: "x", messages: "x")))
        XCTAssertTrue(outbox.lanPackets(.ping).isEmpty)
    }

    func testLegacyUpdatesFromABelievedV2ProducerTriggerOneCatchUpPerFiveSeconds() {
        let engine = v2Client()
        let legacy = CuePacket(type: .cueUpdate, senderId: "producer", roleCues: engine.roles)
        engine.handlePacket(legacy, origin: .lanClient)
        XCTAssertEqual(outbox.lanPackets(.ping).count, 1)
        engine.handlePacket(legacy, origin: .lanClient)
        XCTAssertEqual(outbox.lanPackets(.ping).count, 1)
        mono.ms += 5_001
        engine.handlePacket(CuePacket(type: .timerUpdate, senderId: "producer", timerItem: PCOTimerItem(title: "T")), origin: .lanClient)
        XCTAssertEqual(outbox.lanPackets(.ping).count, 2)
    }

    func testLegacyUpdatesOverTheRelayAreNormalWhileV2PacketsKeepArriving() {
        let engine = v2Client()
        engine.handlePacket(CuePacket(type: .cueUpdate, senderId: "producer", roleCues: engine.roles), origin: .relay)
        XCTAssertTrue(outbox.lanPackets(.ping).isEmpty)
        mono.ms += 13_000
        engine.handlePacket(CuePacket(type: .cueUpdate, senderId: "producer", roleCues: engine.roles), origin: .relay)
        XCTAssertEqual(outbox.lanPackets(.ping).count, 1)
    }

    func testPersistentMessageMismatchBacksOffToOneCatchUpPerThirtySeconds() {
        let engine = v2Client()
        engine.addMessages([InterTeamMessage(id: "extra", text: "e", timestamp: Date(timeIntervalSince1970: 1))])
        var remote = engine.localHashes()
        remote.messages = "ffffffffffffffff"
        func deliver() {
            engine.syncV2.catchUpInFlight = false
            engine.handlePacket(digest(rev: 0, epoch: 1, hashes: remote))
        }
        deliver()
        deliver()
        XCTAssertEqual(outbox.lanPackets(.ping).count, 2)
        deliver()
        deliver()
        XCTAssertEqual(outbox.lanPackets(.ping).count, 2)
        mono.ms += 31_000
        deliver()
        XCTAssertEqual(outbox.lanPackets(.ping).count, 3)
        deliver()
        XCTAssertEqual(outbox.lanPackets(.ping).count, 3)
    }

    func testRolesMismatchAlwaysCatchesUpImmediately() {
        let engine = v2Client()
        var remote = engine.localHashes()
        remote.roles = "ffffffffffffffff"
        for _ in 0..<4 {
            engine.syncV2.catchUpInFlight = false
            engine.handlePacket(digest(rev: 0, epoch: 1, hashes: remote))
        }
        XCTAssertEqual(outbox.lanPackets(.ping).count, 4)
    }

    func testEstimatorIgnoresStaleSamplesAndDropsOldOnesAfterAClockStep() {
        var estimator = ClockOffsetEstimator()
        func sample(offset: Double, rtt: Double, at mono: Double) -> ClockSyncSample {
            ClockSyncSample(t0: 1_000, t1: 1_000 + offset + rtt / 2, t2: 1_000 + offset + rtt / 2, t3: 1_000 + rtt, monotonicMs: mono)
        }
        estimator.add(sample(offset: 100, rtt: 2, at: 0), nowMonotonicMs: 0)
        estimator.add(sample(offset: 101, rtt: 30, at: 10_000), nowMonotonicMs: 10_000)
        XCTAssertEqual(estimator.samples.count, 2)
        estimator.add(sample(offset: 102, rtt: 40, at: 95_000), nowMonotonicMs: 95_000)
        XCTAssertEqual(estimator.samples.count, 2)
        XCTAssertEqual(estimator.best?.effectiveRtt ?? 0, 30, accuracy: 0.001)

        estimator.add(sample(offset: 3_600_100, rtt: 40, at: 96_000), nowMonotonicMs: 96_000)
        XCTAssertEqual(estimator.samples.count, 1)
        XCTAssertEqual(estimator.offsetMs ?? 0, 3_600_100, accuracy: 0.001)
    }

    func testEstimatorRoundingBoundsAndImplausibleReplies() {
        var estimator = ClockOffsetEstimator()
        XCTAssertTrue(estimator.add(ClockSyncSample(t0: 100, t1: 100, t2: 101, t3: 99)))
        XCTAssertEqual(estimator.best?.effectiveRtt, 0)
        XCTAssertFalse(estimator.add(ClockSyncSample(t0: 100, t1: 500, t2: 900, t3: 200)))
        XCTAssertFalse(estimator.add(ClockSyncSample(t0: 0, t1: 0, t2: 0, t3: 10_001)))
        XCTAssertTrue(estimator.add(ClockSyncSample(t0: 0, t1: 0, t2: 0, t3: 10_000)))
        var fresh = ClockOffsetEstimator()
        XCTAssertFalse(fresh.add(ClockSyncSample(t0: 0, t1: 86_400_001, t2: 86_400_001, t3: 0)))
        XCTAssertFalse(fresh.add(ClockSyncSample(t0: 0, t1: -86_400_001, t2: -86_400_001, t3: 0)))
        XCTAssertFalse(fresh.add(ClockSyncSample(t0: .nan, t1: 0, t2: 0, t3: 0)))
        XCTAssertTrue(fresh.add(ClockSyncSample(t0: 0, t1: 86_400_000, t2: 86_400_000, t3: 0)))
    }

    func testClockChangeWakeAndReconnectClearSamplesAndBurst() {
        let engine = v2Client()
        XCTAssertFalse(engine.syncV2.estimator.samples.isEmpty)
        engine.systemClockDidChange()
        XCTAssertTrue(engine.syncV2.estimator.samples.isEmpty)
        XCTAssertNotNil(engine.syncV2.estimator.offsetMs)
        XCTAssertEqual(outbox.lanPackets(.sync).count, 1)

        giveOffset(engine)
        outbox.clear()
        engine.deviceDidBecomeActive()
        XCTAssertTrue(engine.syncV2.estimator.samples.isEmpty)
        XCTAssertEqual(outbox.lanPackets(.sync).count, 1)

        giveOffset(engine)
        outbox.clear()
        engine.relayDidConnect()
        XCTAssertTrue(engine.syncV2.estimator.samples.isEmpty)
        XCTAssertEqual(outbox.lanPackets(.ping).first?.proto, 2)
        XCTAssertEqual(outbox.relayPackets(.ping).count, 1)
        XCTAssertEqual(outbox.lanPackets(.sync).count, 1)
        XCTAssertTrue(engine.syncV2.relayLinked)
    }

    func testSampleReceiveTimeIsStoredForAging() {
        let engine = client()
        engine.sendSyncSample()
        let t0 = outbox.lanPackets(.sync)[0].t0!
        var reply = CuePacket(type: .syncReply, senderId: "producer")
        reply.t0 = t0
        reply.t1 = t0
        reply.t2 = t0
        reply.to = engine.deviceId
        reply.receivedAtMs = Double(t0)
        engine.handlePacket(reply)
        XCTAssertEqual(engine.syncV2.estimator.samples.first?.monotonicMs, mono.ms)
    }

    func testFirstV2PacketWithoutAnOffsetStartsOneBurst() {
        let engine = client()
        engine.handlePacket(digest(rev: 1, epoch: 1, hashes: engine.localHashes()))
        XCTAssertEqual(outbox.lanPackets(.sync).count, 1)
        engine.handlePacket(anchor(rev: 2))
        XCTAssertEqual(outbox.lanPackets(.sync).count, 1)
        mono.ms += 3_001
        engine.handlePacket(anchor(rev: 3))
        XCTAssertEqual(outbox.lanPackets(.sync).count, 2)
        XCTAssertEqual(outbox.relayPackets(.sync).count, 2)
    }

    func testHeldAnchorAccruesFromLocalReceiveTimeUntilAnOffsetExists() {
        let engine = client()
        engine.handlePacket(anchor(rev: 1, elapsedMs: 10_000))
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 10)
        mono.ms += 2_500
        engine.refreshHeldTimer()
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 12)
        XCTAssertNil(engine.syncV2.estimator.offsetMs)
    }

    func testRelayLinkFlagFollowsTheConnectionWithoutTouchingSyncState() {
        let engine = v2Client()
        engine.relayDidConnect()
        XCTAssertTrue(engine.syncV2.relayLinked)
        engine.relayDidDisconnect()
        XCTAssertFalse(engine.syncV2.relayLinked)
        XCTAssertTrue(engine.syncV2.producerIsV2)
    }

    func testHostileAnchorsNeverCrashAndAreRejectedAtDecode() throws {
        func decode(_ anchor: String) -> CuePacket? {
            CuePacket.decode(from: Data(#"{"type":"TIMER_ANCHOR","timestamp":1,"senderId":"x","rev":1,"anchor":\#(anchor)}"#.utf8))
        }
        let big = decode(#"{"itemId":"a","lengthInSeconds":9223372036854775807,"elapsedMs":9223372036854775807,"anchorMs":-9223372036854775808,"isRunning":true,"isDurationActual":false}"#)
        XCTAssertNil(big?.anchor)
        XCTAssertEqual(big?.anchorRejected, true)
        let negative = decode(#"{"itemId":"a","lengthInSeconds":-1,"elapsedMs":0,"anchorMs":0,"isRunning":true,"isDurationActual":false}"#)
        XCTAssertEqual(negative?.anchorRejected, true)
        let overElapsed = decode(#"{"itemId":"a","lengthInSeconds":300,"elapsedMs":604800001,"anchorMs":0,"isRunning":true,"isDurationActual":false}"#)
        XCTAssertEqual(overElapsed?.anchorRejected, true)
        let overLength = decode(#"{"itemId":"a","lengthInSeconds":604801,"elapsedMs":0,"anchorMs":0,"isRunning":true,"isDurationActual":false}"#)
        XCTAssertEqual(overLength?.anchorRejected, true)
        let edge = decode(#"{"itemId":"a","lengthInSeconds":604800,"elapsedMs":604800000,"anchorMs":9223372036854775807,"isRunning":true,"isDurationActual":false}"#)
        XCTAssertEqual(edge?.anchorRejected, false)
        XCTAssertNotNil(edge?.anchor)
        let null = decode("null")
        XCTAssertEqual(null?.anchorRejected, false)
        XCTAssertNil(null?.anchor)

        let engine = v2Client()
        engine.handlePacket(anchor(rev: 5))
        var forged = try XCTUnwrap(big)
        forged.rev = 6
        engine.handlePacket(forged)
        XCTAssertNotNil(engine.syncV2.held)

        let extreme = TimerAnchor(itemId: "a", lengthInSeconds: Int.min, elapsedMs: Int.max, anchorMs: Int.min, isRunning: true, isDurationActual: false)
        _ = extreme.elapsedMs(atProducerMs: Int.max)
        _ = extreme.remainingSeconds(atProducerMs: Int.max)
        _ = extreme.msUntilNextSecond(atProducerMs: Int.min)
        let hostileItem = PCOTimerItem(id: "h", title: "h", lengthInSeconds: Int.min, elapsedSeconds: Int.max, isRunning: true)
        _ = hostileItem.remainingSeconds
        _ = hostileItem.formattedRemainingTime
        var mutable = hostileItem
        mutable.adjustRemainingTime(bySeconds: Int.max)
        mutable.setRemainingTime(seconds: Int.max)
        var gate = SyncRevisionGate()
        XCTAssertTrue(gate.accept(Int.min))
        XCTAssertFalse(gate.accept(Int.max, allowJump: false))
        let item = PCOTimerItem(id: "z", title: "z", lengthInSeconds: 10, elapsedSeconds: Int.max, isRunning: true)
        engine.handlePacket(CuePacket(type: .timerUpdate, senderId: "producer", timerItem: item))
        engine.tickTimer()
        engine.tickTimer()
    }

    func testOneShotProducerTimerAlignsToTheAnchorSecondBoundary() {
        let producer = makeProducer()
        _ = producer.currentAnchor
        XCTAssertNotNil(producer.syncV2.producerWorkItem)
        XCTAssertEqual(producer.syncV2.producerTickDelayMs, 1_001)

        clock.value.addTimeInterval(12.25)
        producer.armProducerDisplayTick()
        XCTAssertEqual(producer.syncV2.producerTickDelayMs, 751)

        producer.toggleTimerRunning()
        XCTAssertNil(producer.syncV2.producerWorkItem)
        XCTAssertNil(producer.syncV2.producerTickDelayMs)

        producer.toggleTimerRunning()
        XCTAssertEqual(producer.syncV2.producerTickDelayMs, 751)
    }

    func testPagersAndMirrorsCreateNoDisplayTimer() {
        let pager = client()
        pager.handlePacket(anchor(rev: 1))
        pager.tickTimer()
        XCTAssertNil(pager.syncV2.producerWorkItem)
        pager.armProducerDisplayTick()
        XCTAssertNil(pager.syncV2.producerWorkItem)

        let mirror = CueEngine(mirroring: nil)
        mirror.armProducerDisplayTick()
        mirror.tickTimer()
        XCTAssertNil(mirror.syncV2.producerWorkItem)
    }

    func testPacketCodecCarriesEpochAndTo() throws {
        var packet = CuePacket(type: .digest, senderId: "p")
        packet.epoch = 12345
        packet.to = "pager"
        let decoded = try XCTUnwrap(CuePacket.decode(from: XCTUnwrap(packet.encode())))
        XCTAssertEqual(decoded.epoch, 12345)
        XCTAssertEqual(decoded.to, "pager")
        let legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(CuePacket(type: .ping, senderId: "p").encode())) as? [String: Any])
        XCTAssertNil(legacy["epoch"])
        XCTAssertNil(legacy["to"])
    }

    func testLocalMessageOrderBreaksTimestampTiesByIdAscending() {
        let producer = makeProducer()
        let stamp = Date(timeIntervalSince1970: 50)
        producer.addMessages([
            InterTeamMessage(id: "b", text: "b", timestamp: stamp),
            InterTeamMessage(id: "a", text: "a", timestamp: stamp),
            InterTeamMessage(id: "c", text: "c", timestamp: Date(timeIntervalSince1970: 60)),
        ])
        XCTAssertEqual(producer.recentMessages.map(\.id), ["c", "a", "b"])
    }
}
