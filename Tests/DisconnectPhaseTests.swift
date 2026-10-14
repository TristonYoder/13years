// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

final class DisconnectPhaseTests: XCTestCase {
    func testPhaseFollowsSignal() {
        XCTAssertEqual(DisconnectPhase(signal: .live), .live)
        XCTAssertEqual(DisconnectPhase(signal: .stale), .dimmed)
        XCTAssertEqual(DisconnectPhase(signal: .lost), .extended)
    }

    func testProducerSignalThresholds() {
        XCTAssertEqual(ProducerSignal(silence: nil), .lost)
        XCTAssertEqual(ProducerSignal(silence: 0), .live)
        XCTAssertEqual(ProducerSignal(silence: 4.9), .live)
        XCTAssertEqual(ProducerSignal(silence: 5), .stale)
        XCTAssertEqual(ProducerSignal(silence: 19.9), .stale)
        XCTAssertEqual(ProducerSignal(silence: 20), .lost)
    }

    func testConnectionStateTitles() {
        XCTAssertEqual(PagerConnectionState(isProducerLive: true, isLANConnected: true).title, "Live")
        XCTAssertEqual(PagerConnectionState(isProducerLive: false, isLANConnected: true).title, "Disconnected — retrying…")
        XCTAssertEqual(PagerConnectionState(isProducerLive: false, isLANConnected: false).title, "Not connected")
    }
}
