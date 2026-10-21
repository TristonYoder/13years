// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class NextItemTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_760_000_000)
    private var sent: [(packet: CuePacket, target: OutboundTarget)] = []

    override func setUp() {
        super.setUp()
        clearPersistedState()
        clock = Date(timeIntervalSince1970: 1_760_000_000)
        sent = []
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

    private func makeProducer(items: [PCOTimerItem]? = nil) -> CueEngine {
        let engine = CueEngine(startsNetworking: false)
        engine.timerClock = { [unowned self] in self.clock }
        engine.outboundObserver = { [unowned self] packet, target in self.sent.append((packet, target)) }
        engine.roles = [
            RoleCue(id: "host", name: "Host", assignedNoteCategories: ["Host"]),
            RoleCue(id: "band", name: "Band"),
        ]
        engine.importFlow(title: "Plan", items: items ?? [
            PCOTimerItem(id: "a", title: "Song", itemType: "Song", lengthInSeconds: 300),
            PCOTimerItem(id: "h", title: "Section", itemType: "Header"),
            PCOTimerItem(id: "b", title: "Sermon", itemType: "Item", lengthInSeconds: 1800, notes: ["Host": "Walk on", "Lighting": "Cue 12"]),
        ])
        sent = []
        return engine
    }

    private func packets(_ type: CuePacket.PacketType) -> [CuePacket] {
        sent.filter { $0.packet.type == type }.map(\.packet)
    }

    func testNextItemSkipsHeaders() {
        let engine = makeProducer()
        XCTAssertEqual(engine.derivedNextPlanItem?.id, "b")
        XCTAssertEqual(engine.nextItemForBroadcast?.id, "b")
    }

    func testNextItemIsNilAtTheLastItem() {
        let engine = makeProducer()
        engine.nextPlanItem()
        XCTAssertEqual(engine.activeTimerItem?.id, "b")
        XCTAssertNil(engine.nextItemForBroadcast)
    }

    func testNextItemNotesAreLimitedToAssignedCategories() {
        let engine = makeProducer()
        XCTAssertEqual(engine.nextItemForBroadcast?.notes, ["Host": "Walk on"])
        XCTAssertEqual(engine.derivedNextPlanItem?.notes.count, 2)
    }

    func testAnchorAndLegacyPacketsCarryNextItem() {
        let engine = makeProducer()
        engine.toggleTimerRunning()
        XCTAssertEqual(packets(.timerAnchor).last?.nextItem?.id, "b")
        XCTAssertEqual(packets(.timerUpdate).last?.nextItem?.id, "b")
        sent = []
        engine.broadcastCatchUp()
        XCTAssertEqual(packets(.pong).last?.nextItem?.id, "b")
        sent = []
        engine.nextPlanItem()
        XCTAssertNil(packets(.timerAnchor).last?.nextItem)
        XCTAssertNil(packets(.timerUpdate).last?.nextItem)
    }

    func testCueUpdateCarriesNextItem() {
        let engine = makeProducer()
        engine.setCueForRole(id: "host", state: .go)
        XCTAssertEqual(packets(.cueUpdate).first?.nextItem?.id, "b")
    }

    func testPlanEditRebroadcastsAnchorAndLegacyTimerUpdate() {
        let engine = makeProducer()
        let revBefore = engine.syncV2.rev
        engine.planItems.insert(PCOTimerItem(id: "n", title: "Welcome", itemType: "Item", lengthInSeconds: 60), at: 1)
        let anchors = packets(.timerAnchor)
        XCTAssertEqual(anchors.count, 1)
        XCTAssertEqual(anchors[0].nextItem?.id, "n")
        XCTAssertGreaterThan(anchors[0].rev ?? 0, revBefore)
        XCTAssertEqual(packets(.timerUpdate).last?.nextItem?.id, "n")
    }

    func testNoRebroadcastWhenNextItemIsUnchanged() {
        let engine = makeProducer()
        engine.planItems[0].title = "Song renamed"
        engine.planItems[2].lengthInSeconds = 1800
        XCTAssertTrue(packets(.timerAnchor).isEmpty)
    }

    func testRoleNoteCategoryChangeRebroadcasts() {
        let engine = makeProducer()
        engine.roles[1].assignedNoteCategories = ["Lighting"]
        let anchor = packets(.timerAnchor).last
        XCTAssertEqual(anchor?.nextItem?.notes, ["Host": "Walk on", "Lighting": "Cue 12"])
    }

    func testReorderRebroadcasts() {
        let engine = makeProducer()
        engine.planItems.swapAt(1, 2)
        XCTAssertTrue(packets(.timerAnchor).isEmpty)
        engine.planItems.removeAll { $0.id == "b" }
        XCTAssertNil(packets(.timerAnchor).last?.nextItem)
        XCTAssertEqual(packets(.timerAnchor).count, 1)
    }

    func testV2PongStaysWithinTheByteLimitByDroppingMessagesThenLongNotes() {
        let engine = makeProducer(items: [
            PCOTimerItem(id: "a", title: "Song", lengthInSeconds: 300),
            PCOTimerItem(id: "b", title: "Sermon", notes: ["Host": String(repeating: "x", count: 3500), "Band": "short"]),
        ])
        engine.roles[0].assignedNoteCategories = ["Host", "Band"]
        for index in 0..<20 {
            engine.recentMessages.append(InterTeamMessage(id: "m\(index)", sender: "P", text: String(repeating: "m", count: 200)))
        }
        let pong = engine.makeV2CatchUpPong(to: nil)
        XCTAssertLessThanOrEqual(pong.encode()?.count ?? Int.max, CueEngine.maxCatchUpPongBytes)
        XCTAssertEqual(pong.messages?.count, 0)
        XCTAssertNil(pong.nextItem?.notes["Host"])
        XCTAssertEqual(pong.nextItem?.notes["Band"], "short")
        XCTAssertEqual(pong.nextItem?.id, "b")
    }

    func testSmallPongKeepsNotesAndMessages() {
        let engine = makeProducer()
        engine.recentMessages = [InterTeamMessage(id: "m", sender: "P", text: "hi")]
        let pong = engine.makeV2CatchUpPong(to: nil)
        XCTAssertEqual(pong.messages?.count, 1)
        XCTAssertEqual(pong.nextItem?.notes["Host"], "Walk on")
    }

    func testNextItemIsNotPartOfTheDigest() {
        let engine = makeProducer()
        let before = engine.currentHashes()
        engine.planItems[2].notes["Host"] = "Changed"
        XCTAssertEqual(engine.currentHashes(), before)
    }

    func testPacketCodableRoundTripAndAbsence() throws {
        var packet = CuePacket(type: .timerUpdate, senderId: "p")
        let encodedWithout = try XCTUnwrap(packet.encode())
        XCTAssertFalse(String(decoding: encodedWithout, as: UTF8.self).contains("nextItem"))
        packet.nextItem = CueNextItem(id: "x", title: "T", itemType: "Item", lengthInSeconds: 5, notes: ["A": "b"])
        let decoded = try XCTUnwrap(CuePacket.decode(from: try XCTUnwrap(packet.encode())))
        XCTAssertEqual(decoded.nextItem, packet.nextItem)
    }

    private func makeClient() -> CueEngine {
        let engine = CueEngine(isMasterServer: false, startsNetworking: false)
        engine.timerClock = { [unowned self] in self.clock }
        engine.outboundObserver = { _, _ in }
        return engine
    }

    private func anchorPacket(rev: Int, next: CueNextItem?, withItem: Bool = true) -> CuePacket {
        let item = PCOTimerItem(id: "a", title: "Song", lengthInSeconds: 300)
        var packet = CuePacket(type: .timerAnchor, senderId: "producer", timerItem: withItem ? item : nil)
        packet.rev = rev
        packet.epoch = 1
        packet.nextItem = next
        if withItem {
            packet.anchor = TimerAnchor(itemId: "a", lengthInSeconds: 300, elapsedMs: 0, anchorMs: Int(clock.timeIntervalSince1970 * 1000), isRunning: false, isDurationActual: false)
        }
        return packet
    }

    func testClientDecodesNextItemFromAnchorAndClearsIt() {
        let client = makeClient()
        let next = CueNextItem(id: "b", title: "Sermon", itemType: "Item", lengthInSeconds: 1800, notes: ["Host": "Walk on"])
        client.handlePacket(anchorPacket(rev: 1, next: next))
        XCTAssertEqual(client.nextItem?.id, "b")
        XCTAssertEqual(client.nextItem?.title, "Sermon")
        XCTAssertEqual(client.nextItem?.notes, ["Host": "Walk on"])
        client.handlePacket(anchorPacket(rev: 2, next: nil))
        XCTAssertNil(client.nextItem)
        client.handlePacket(anchorPacket(rev: 3, next: next))
        client.handlePacket(anchorPacket(rev: 4, next: nil, withItem: false))
        XCTAssertNil(client.nextItem)
    }

    func testClientDecodesNextItemFromLegacyPacketsAndPong() {
        let client = makeClient()
        let next = CueNextItem(id: "b", title: "Sermon", itemType: "Item", lengthInSeconds: 1800, notes: [:])
        let item = PCOTimerItem(id: "a", title: "Song", lengthInSeconds: 300)
        var update = CuePacket(type: .timerUpdate, senderId: "producer", timerItem: item)
        update.nextItem = next
        client.handlePacket(update)
        XCTAssertEqual(client.nextItem?.id, "b")
        client.handlePacket(CuePacket(type: .timerUpdate, senderId: "producer", timerItem: item))
        XCTAssertNil(client.nextItem)
        var pong = CuePacket(type: .pong, senderId: "producer", timerItem: item)
        pong.nextItem = next
        client.handlePacket(pong)
        XCTAssertEqual(client.nextItem?.id, "b")
    }

    private func presentation(plan: [PCOTimerItem], index: Int = 0, received: PCOTimerItem? = nil, roles: [RoleCue]? = nil) -> PagerPresentationState {
        PagerPresentationState(
            roles: roles ?? [RoleCue(id: "host", name: "Host", assignedNoteCategories: ["Host"])],
            planItems: plan,
            activeItemIndex: index,
            activeTimerItem: nil,
            recentMessages: [],
            selectedRoleId: "host",
            isProducerLive: true,
            isLANConnected: true,
            connectedMasterName: nil,
            hourFormatThreshold: .over90Minutes,
            clockFormat: .twelveHour,
            receivedNextItem: received
        )
    }

    func testPresentationUsesReceivedNextItemWhenThePlanIsEmpty() {
        let received = PCOTimerItem(id: "b", title: "Sermon", notes: ["Host": "Walk on", "Lighting": "Cue"])
        let state = presentation(plan: [], received: received)
        XCTAssertEqual(state.nextItem?.id, "b")
        XCTAssertEqual(state.nextNotes.map(\.category), ["Host"])
        XCTAssertEqual(state.nextNotes.map(\.text), ["Walk on"])
    }

    func testPresentationPrefersThePlanAndSkipsHeaders() {
        let plan = [
            PCOTimerItem(id: "a", title: "A"),
            PCOTimerItem(id: "h", title: "H", itemType: "Header"),
            PCOTimerItem(id: "b", title: "B"),
        ]
        let state = presentation(plan: plan, received: PCOTimerItem(id: "z", title: "Z"))
        XCTAssertEqual(state.nextItem?.id, "b")
        XCTAssertNil(presentation(plan: plan, index: 2).nextItem)
    }

    func testOffShowsNoCueWord() {
        XCTAssertEqual(PagerPresentationState.cueWordText(for: .off), "")
        XCTAssertEqual(PagerPresentationState.cueWordText(for: .standby), CueState.standby.displayName.uppercased())
        XCTAssertEqual(PagerPresentationState.cueWordText(for: .go), CueState.go.displayName.uppercased())
    }

    func testControlAPITimerCarriesFullNextItem() throws {
        let engine = makeProducer()
        let router = ControlAPIRouter(engine: engine)
        let timer = try XCTUnwrap(router.snapshot().timer)
        XCTAssertEqual(timer.nextItem?.id, "b")
        XCTAssertEqual(timer.nextItem?.notes.count, 2)
        let slim = try XCTUnwrap(router.timerSnapshot().timer)
        XCTAssertEqual(slim.nextItem?.id, "b")
        let json = try ControlAPIJSON.encoder.encode(router.timerSnapshot())
        XCTAssertTrue(String(decoding: json, as: UTF8.self).contains("\"nextItem\""))
        engine.nextPlanItem()
        XCTAssertNil(try XCTUnwrap(router.snapshot().timer).nextItem)
    }
}
