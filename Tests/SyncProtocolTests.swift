// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

final class SyncHashTests: XCTestCase {
    private let us = SyncHash.unitSeparator
    private let rs = SyncHash.recordSeparator

    func testFNVSpecVectors() {
        XCTAssertEqual(SyncHash.fnv1a64(""), "cbf29ce484222325")
        XCTAssertEqual(SyncHash.fnv1a64("a"), "af63dc4c8601ec8c")
        XCTAssertEqual(SyncHash.fnv1a64("foobar"), "85944171f73967e8")
    }

    func testSeparatorsAreTheSpecBytes() {
        XCTAssertEqual(Array(us.utf8), [0x1F])
        XCTAssertEqual(Array(rs.utf8), [0x1E])
    }

    func testRolesVector() {
        let roles = [
            RoleCue(id: "host", name: "Host", state: .go),
            RoleCue(id: "band", name: "Band", state: .off),
        ]
        XCTAssertEqual(SyncHash.rolesCanonical(roles), "host\(us)Host\(us)GO\(rs)band\(us)Band\(us)OFF\(rs)")
        XCTAssertEqual(SyncHash.roles(roles), "aded3b3c0e486304")
        XCTAssertEqual(SyncHash.fnv1a64("host\(us)Host\(us)GO\(rs)band\(us)Band\(us)OFF\(rs)"), "aded3b3c0e486304")
    }

    func testTimerVectors() {
        let anchor = TimerAnchor(itemId: "item-1", lengthInSeconds: 300, elapsedMs: 120000, anchorMs: 1_760_000_000_000, isRunning: true, isDurationActual: false)
        XCTAssertEqual(SyncHash.timerCanonical(anchor), "item-1\(us)300\(us)1\(us)0\(us)120000\(us)1760000000000")
        XCTAssertEqual(SyncHash.timer(anchor), "20a9d930a0849518")
        XCTAssertEqual(SyncHash.timerCanonical(nil), "none")
        XCTAssertEqual(SyncHash.timer(nil), "3c0d17bad169557b")
    }

    func testMessagesVector() {
        XCTAssertEqual(SyncHash.messagesCanonical(ids: ["m2", "m1"]), "m2\(rs)m1")
        XCTAssertEqual(SyncHash.messages(ids: ["m2", "m1"]), "dddb4a3dc4d94432")
        let older = InterTeamMessage(id: "m1", text: "a", timestamp: Date(timeIntervalSince1970: 100))
        let newer = InterTeamMessage(id: "m2", text: "b", timestamp: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(SyncHash.messages([older, newer]), "dddb4a3dc4d94432")
        XCTAssertEqual(SyncHash.messages([newer, older]), "dddb4a3dc4d94432")
    }

    func testPlanVector() {
        let items = [
            PCOTimerItem(id: "i1", title: "Song", lengthInSeconds: 300, isDurationActual: false),
            PCOTimerItem(id: "i2", title: "Sermon", lengthInSeconds: 2700, isDurationActual: true),
        ]
        XCTAssertEqual(SyncHash.planCanonical(items: items, activeItemIndex: 1), "i1\(us)Song\(us)300\(us)0\(rs)i2\(us)Sermon\(us)2700\(us)1\(rs)1")
        XCTAssertEqual(SyncHash.plan(items: items, activeItemIndex: 1), "218cc3247b5ee3f9")
    }

    func testHashesAlwaysSixteenLowercaseHexDigits() {
        for sample in ["", "x", "\u{1F}", String(repeating: "z", count: 500)] {
            let hash = SyncHash.fnv1a64(sample)
            XCTAssertEqual(hash.count, 16)
            XCTAssertEqual(hash, hash.lowercased())
            XCTAssertNotNil(UInt64(hash, radix: 16))
        }
    }

    func testMismatchesNameTheSectionsThatDiffer() {
        let local = SyncHash.Hashes(roles: "a", timer: "b", plan: "c", messages: "d")
        XCTAssertEqual(local.mismatches(against: local), [])
        XCTAssertEqual(local.mismatches(against: SyncHash.Hashes(roles: "x", timer: "b", plan: "c", messages: "d")), [.roles])
        XCTAssertEqual(local.mismatches(against: SyncHash.Hashes(roles: "a", timer: "x", plan: "x", messages: "x")), [.timer, .messages, .plan])
        XCTAssertEqual(local.mismatches(against: SyncHash.Hashes(roles: "a", timer: "b", messages: "d")), [])
    }
}

final class TimerAnchorTests: XCTestCase {
    private func anchor(elapsed: Int = 0, at anchorMs: Int = 1_000_000, running: Bool = true) -> TimerAnchor {
        TimerAnchor(itemId: "i", lengthInSeconds: 300, elapsedMs: elapsed, anchorMs: anchorMs, isRunning: running, isDurationActual: false)
    }

    func testRunningAnchorAdvancesWithProducerTime() {
        let a = anchor(elapsed: 120_000)
        XCTAssertEqual(a.elapsedMs(atProducerMs: 1_000_000), 120_000)
        XCTAssertEqual(a.elapsedMs(atProducerMs: 1_000_999), 120_999)
        XCTAssertEqual(a.elapsedSeconds(atProducerMs: 1_000_999), 120)
        XCTAssertEqual(a.elapsedSeconds(atProducerMs: 1_001_000), 121)
        XCTAssertEqual(a.remainingSeconds(atProducerMs: 1_001_000), 179)
    }

    func testPausedAnchorIsFrozen() {
        let a = anchor(elapsed: 45_500, running: false)
        XCTAssertEqual(a.elapsedMs(atProducerMs: 9_999_999), 45_500)
        XCTAssertNil(a.msUntilNextSecond(atProducerMs: 1_000_000))
    }

    func testElapsedNeverGoesBelowZero() {
        XCTAssertEqual(anchor(elapsed: 100).elapsedMs(atProducerMs: 900_000), 0)
    }

    func testOvertimeKeepsCounting() {
        let a = anchor(elapsed: 299_000)
        XCTAssertEqual(a.remainingSeconds(atProducerMs: 1_000_000 + 5_000), -4)
    }

    func testPauseAndResumeAcrossAnchors() {
        let running = anchor(elapsed: 10_000, at: 2_000_000)
        let pausedElapsed = running.elapsedMs(atProducerMs: 2_007_300)
        XCTAssertEqual(pausedElapsed, 17_300)
        let paused = TimerAnchor(itemId: "i", lengthInSeconds: 300, elapsedMs: pausedElapsed, anchorMs: 2_007_300, isRunning: false, isDurationActual: false)
        XCTAssertEqual(paused.elapsedSeconds(atProducerMs: 2_100_000), 17)
        var resumed = paused
        resumed.isRunning = true
        resumed.anchorMs = 2_100_000
        XCTAssertEqual(resumed.elapsedMs(atProducerMs: 2_100_000), 17_300)
        XCTAssertEqual(resumed.elapsedSeconds(atProducerMs: 2_102_700), 20)
        XCTAssertEqual(resumed.elapsedSeconds(atProducerMs: 2_102_699), 19)
    }

    func testDigitsFlipAtAnchorPlusWholeSeconds() {
        let a = anchor(elapsed: 5_250, at: 7_000)
        XCTAssertEqual(a.msUntilNextSecond(atProducerMs: 7_000), 750)
        XCTAssertEqual(a.msUntilNextSecond(atProducerMs: 7_750), 1000)
        XCTAssertEqual(a.elapsedSeconds(atProducerMs: 7_749), 5)
        XCTAssertEqual(a.elapsedSeconds(atProducerMs: 7_750), 6)
    }

    func testApplyingOverridesTheLiveFieldsOfAnItem() {
        let item = PCOTimerItem(id: "i", title: "T", lengthInSeconds: 10, elapsedSeconds: 0, isRunning: false)
        let applied = anchor(elapsed: 3_000).applying(to: item, atProducerMs: 1_002_000)
        XCTAssertEqual(applied.elapsedSeconds, 5)
        XCTAssertTrue(applied.isRunning)
        XCTAssertEqual(applied.lengthInSeconds, 300)
        XCTAssertEqual(applied.title, "T")
    }
}

final class ClockOffsetEstimatorTests: XCTestCase {
    private func sample(offset: Double, rtt: Double, processing: Double = 0, t0: Double = 1_000_000, asymmetry: Double = 0) -> ClockSyncSample {
        let outbound = rtt / 2 + asymmetry
        let inbound = rtt - outbound
        let t1 = t0 + outbound + offset
        let t2 = t1 + processing
        let t3 = t0 + outbound + processing + inbound
        return ClockSyncSample(t0: t0, t1: t1, t2: t2, t3: t3)
    }

    func testSymmetricSampleRecoversOffsetAndRTT() {
        let s = sample(offset: 1234, rtt: 40, processing: 3)
        XCTAssertEqual(s.rtt, 40, accuracy: 0.0001)
        XCTAssertEqual(s.offset, 1234, accuracy: 0.0001)
    }

    func testAsymmetricPathBiasesOffsetByTheExtraOutboundDelay() {
        let s = sample(offset: 500, rtt: 60, asymmetry: 20)
        XCTAssertEqual(s.rtt, 60, accuracy: 0.0001)
        XCTAssertEqual(s.offset, 500 + 20, accuracy: 0.0001)
    }

    func testPicksTheMinimumRTTSampleOfTheLastEight() {
        var estimator = ClockOffsetEstimator()
        estimator.add(sample(offset: 100, rtt: 80, asymmetry: 30))
        estimator.add(sample(offset: 100, rtt: 10))
        estimator.add(sample(offset: 100, rtt: 50, asymmetry: 20))
        XCTAssertEqual(estimator.best?.rtt ?? 0, 10, accuracy: 0.0001)
        XCTAssertEqual(estimator.offsetMs ?? 0, 100, accuracy: 0.0001)
    }

    func testKeepsOnlyEightSamplesAndForgetsTheOldBest() {
        var estimator = ClockOffsetEstimator()
        estimator.add(sample(offset: 1000, rtt: 2))
        for _ in 0..<8 { estimator.add(sample(offset: 1000, rtt: 30)) }
        XCTAssertEqual(estimator.samples.count, 8)
        XCTAssertEqual(estimator.best?.rtt ?? 0, 30, accuracy: 0.0001)
    }

    func testFirstEstimateJumpsAndLargeChangesJump() {
        var estimator = ClockOffsetEstimator()
        estimator.add(sample(offset: 5000, rtt: 20))
        XCTAssertEqual(estimator.offsetMs ?? 0, 5000, accuracy: 0.0001)
        estimator.add(sample(offset: 5100, rtt: 5))
        XCTAssertEqual(estimator.offsetMs ?? 0, 5100, accuracy: 0.0001)
    }

    func testSmallChangesSlewByAQuarter() {
        var estimator = ClockOffsetEstimator()
        estimator.add(sample(offset: 5000, rtt: 20))
        estimator.add(sample(offset: 5016, rtt: 5))
        XCTAssertEqual(estimator.offsetMs ?? 0, 5004, accuracy: 0.0001)
        estimator.add(sample(offset: 5016, rtt: 4))
        XCTAssertEqual(estimator.offsetMs ?? 0, 5004 + 12 * 0.25, accuracy: 0.0001)
    }

    func testNegativeRTTSamplesAreRejected() {
        var estimator = ClockOffsetEstimator()
        XCTAssertFalse(estimator.add(ClockSyncSample(t0: 100, t1: 500, t2: 900, t3: 200)))
        XCTAssertNil(estimator.offsetMs)
        XCTAssertNil(estimator.producerNowMs(localNowMs: 1))
    }

    func testProducerNowAddsTheOffset() {
        var estimator = ClockOffsetEstimator()
        estimator.add(sample(offset: -250, rtt: 10))
        XCTAssertEqual(estimator.producerNowMs(localNowMs: 10_000) ?? 0, 9_750, accuracy: 0.0001)
        estimator.reset()
        XCTAssertNil(estimator.offsetMs)
        XCTAssertTrue(estimator.samples.isEmpty)
    }
}

final class SyncRevisionGateTests: XCTestCase {
    func testIgnoresLowerRevsAndAcceptsEqualOrHigher() {
        var gate = SyncRevisionGate()
        XCTAssertTrue(gate.accept(5))
        XCTAssertFalse(gate.accept(4))
        XCTAssertTrue(gate.accept(5))
        XCTAssertTrue(gate.accept(9))
        XCTAssertFalse(gate.accept(8))
        XCTAssertEqual(gate.highest, 9)
    }

    func testPacketsWithoutARevAreAlwaysAccepted() {
        var gate = SyncRevisionGate()
        XCTAssertTrue(gate.accept(10))
        XCTAssertTrue(gate.accept(nil))
        XCTAssertEqual(gate.highest, 10)
    }

    func testRebaseAcceptsALowerRevAfterAProducerRestart() {
        var gate = SyncRevisionGate()
        XCTAssertTrue(gate.accept(500))
        gate.rebase(to: 3)
        XCTAssertTrue(gate.accept(4))
        XCTAssertFalse(gate.accept(2))
        gate.reset()
        XCTAssertTrue(gate.accept(1))
    }
}

final class CuePacketV2CodecTests: XCTestCase {
    func testLegacyPacketJSONCarriesNoV2Keys() throws {
        let packet = CuePacket(type: .timerUpdate, senderId: "p", timerItem: PCOTimerItem(title: "T"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(packet.encode())) as? [String: Any])
        for key in ["proto", "t0", "t1", "t2", "rev", "anchor", "cueDeltas", "digestMs", "hashes"] {
            XCTAssertNil(object[key], key)
        }
        XCTAssertEqual(object["type"] as? String, "TIMER_UPDATE")
    }

    func testOldPacketJSONStillDecodes() throws {
        let json = #"{"type":"PING","timestamp":1,"senderId":"x"}"#
        let packet = try XCTUnwrap(CuePacket.decode(from: Data(json.utf8)))
        XCTAssertEqual(packet.type, .ping)
        XCTAssertNil(packet.proto)
        XCTAssertNotNil(packet.receivedAtMs)
    }

    func testUnknownTypesStillFailToDecodeForOldPeersButNotForNewOnes() {
        let json = #"{"type":"TIMER_ANCHOR","timestamp":1,"senderId":"x","rev":3,"anchor":null}"#
        let packet = CuePacket.decode(from: Data(json.utf8))
        XCTAssertEqual(packet?.type, .timerAnchor)
        XCTAssertNil(packet?.anchor)
        XCTAssertEqual(packet?.rev, 3)
    }

    func testAnchorPacketRoundTripsAndEncodesNullAnchor() throws {
        var packet = CuePacket(type: .timerAnchor, senderId: "p")
        packet.rev = 7
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(packet.encode())) as? [String: Any])
        XCTAssertTrue(object["anchor"] is NSNull)
        XCTAssertNil(object["timerItem"])

        packet.anchor = TimerAnchor(itemId: "i", lengthInSeconds: 10, elapsedMs: 5, anchorMs: 6, isRunning: true, isDurationActual: false)
        let decoded = try XCTUnwrap(CuePacket.decode(from: XCTUnwrap(packet.encode())))
        XCTAssertEqual(decoded.anchor, packet.anchor)
        XCTAssertEqual(decoded.rev, 7)
    }

    func testSyncReplyGetsASendTimestampWhenEncoded() throws {
        var reply = CuePacket(type: .syncReply, senderId: "p")
        reply.t0 = 10
        reply.t1 = 20
        let before = Int(SyncClock.nowMs())
        let decoded = try XCTUnwrap(CuePacket.decode(from: XCTUnwrap(reply.encode())))
        XCTAssertEqual(decoded.t0, 10)
        XCTAssertEqual(decoded.t1, 20)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(decoded.t2), before)
    }

    func testCueDeltaRoundTrips() throws {
        var packet = CuePacket(type: .cueDelta, senderId: "p")
        packet.cueDeltas = [CueDelta(id: "host", state: .go, lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))]
        let decoded = try XCTUnwrap(CuePacket.decode(from: XCTUnwrap(packet.encode())))
        XCTAssertEqual(decoded.cueDeltas, packet.cueDeltas)
    }

    func testDigestPacketKeys() throws {
        var packet = CuePacket(type: .digest, senderId: "p")
        packet.rev = 2
        packet.digestMs = 1_760_000_000_000
        packet.hashes = SyncHash.Hashes(roles: "r", timer: "t", messages: "m")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(packet.encode())) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "DIGEST")
        XCTAssertEqual(object["digestMs"] as? Int, 1_760_000_000_000)
        let hashes = try XCTUnwrap(object["hashes"] as? [String: String])
        XCTAssertEqual(hashes, ["roles": "r", "timer": "t", "messages": "m"])
    }
}
