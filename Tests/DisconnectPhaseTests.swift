// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

final class DisconnectPhaseTests: XCTestCase {
    func testLiveWhenNoElapsedTime() {
        XCTAssertEqual(DisconnectPhase(elapsedSinceLive: nil), .live)
        XCTAssertEqual(DisconnectPhase(elapsedSinceLive: 0), .live)
    }

    func testDimmedBeforeTwentySeconds() {
        XCTAssertEqual(DisconnectPhase(elapsedSinceLive: 0.5), .dimmed)
        XCTAssertEqual(DisconnectPhase(elapsedSinceLive: 19.99), .dimmed)
    }

    func testExtendedFromTwentySeconds() {
        XCTAssertEqual(DisconnectPhase(elapsedSinceLive: 20), .extended)
        XCTAssertEqual(DisconnectPhase(elapsedSinceLive: 300), .extended)
    }

    func testConnectionStateTitles() {
        XCTAssertEqual(PagerConnectionState(isProducerLive: true, isLANConnected: true).title, "Live")
        XCTAssertEqual(PagerConnectionState(isProducerLive: false, isLANConnected: true).title, "Disconnected — retrying…")
        XCTAssertEqual(PagerConnectionState(isProducerLive: false, isLANConnected: false).title, "Not connected")
    }
}
