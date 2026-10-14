// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class ProducerClockTests: XCTestCase {
    private func date(_ ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }

    func testProducerDateAppliesPositiveAndNegativeOffsets() {
        let local = date(1_000_200)
        XCTAssertEqual(ProducerClock.producerDate(localNow: local, offsetMs: 256).timeIntervalSince1970, 1_000.456, accuracy: 0.0001)
        XCTAssertEqual(ProducerClock.producerDate(localNow: local, offsetMs: -300).timeIntervalSince1970, 999.9, accuracy: 0.0001)
        XCTAssertEqual(ProducerClock.producerDate(localNow: local, offsetMs: nil), local)
    }

    func testMsUntilNextProducerSecond() {
        XCTAssertEqual(ProducerClock.msUntilNextProducerSecond(localNow: date(1_000_200), offsetMs: 256), 544)
        XCTAssertEqual(ProducerClock.msUntilNextProducerSecond(localNow: date(1_000_200), offsetMs: -300), 100)
        XCTAssertEqual(ProducerClock.msUntilNextProducerSecond(localNow: date(1_000_200), offsetMs: nil), 800)
        XCTAssertEqual(ProducerClock.msUntilNextProducerSecond(localNow: date(1_000_999), offsetMs: 0), 1)
        XCTAssertEqual(ProducerClock.msUntilNextProducerSecond(localNow: date(1_001_000), offsetMs: 0), 1000)
    }

    func testFlipDatesLandOnProducerSecondBoundaries() {
        let offset = 256.0
        let flips = ProducerClock.flipDates(from: date(1_000_200), offsetMs: offset, count: 4)
        XCTAssertEqual(flips.count, 4)
        for flip in flips {
            let producerMs = flip.timeIntervalSince1970 * 1000 + offset
            XCTAssertEqual(producerMs.truncatingRemainder(dividingBy: 1000), 0, accuracy: 1)
        }
        XCTAssertEqual(flips[1].timeIntervalSince(flips[0]), 1, accuracy: 0.002)
    }

    func testCurrentFlipDateIsBoundaryAtOrBeforeNow() {
        let now = date(1_000_200)
        let flip = ProducerClock.currentFlipDate(at: now, offsetMs: 256)
        XCTAssertEqual(flip.timeIntervalSince1970 * 1000, 999_744, accuracy: 0.01)
        XCTAssertLessThanOrEqual(flip, now)
    }

    func testFormattingUsesProducerUtcOffset() {
        let local = Date(timeIntervalSince1970: 1_767_539_228.7)
        XCTAssertEqual(ProducerClock.formatted(localNow: local, info: ProducerClockInfo(offsetMs: 0, utcOffsetSeconds: 0)), "15:07:08")
        XCTAssertEqual(ProducerClock.formatted(localNow: local, info: ProducerClockInfo(offsetMs: 400, utcOffsetSeconds: 0)), "15:07:09")
        XCTAssertEqual(ProducerClock.formatted(localNow: local, info: ProducerClockInfo(offsetMs: 0, utcOffsetSeconds: -14400)), "11:07:08")
        XCTAssertEqual(ProducerClock.formatted(localNow: local, info: ProducerClockInfo(offsetMs: 0, utcOffsetSeconds: 19800)), "20:37:08")
    }

    func testTimeZoneFallsBackToCurrent() {
        XCTAssertEqual(ProducerClock.timeZone(utcOffsetSeconds: nil), .current)
        XCTAssertEqual(ProducerClock.timeZone(utcOffsetSeconds: 3600).secondsFromGMT(), 3600)
    }

    func testMirrorEngineExposesSocketOffsetAndUtc() {
        let engine = CueEngine(mirroring: nil)
        XCTAssertNil(engine.producerClockOffsetMs)
        engine.setRemoteClockOffset(256)
        engine.setRemoteUTCOffset(-18000)
        XCTAssertEqual(engine.producerClock, ProducerClockInfo(offsetMs: 256, utcOffsetSeconds: -18000))
        engine.setRemoteClockOffset(nil)
        XCTAssertNil(engine.producerClockOffsetMs)
    }

    func testProducerEngineOffsetIsZero() {
        let engine = CueEngine(isMasterServer: true, startsNetworking: false)
        engine.refreshProducerClockOffset()
        XCTAssertEqual(engine.producerClockOffsetMs, 0)
        XCTAssertNil(engine.producerUTCOffsetSeconds)
    }
}
