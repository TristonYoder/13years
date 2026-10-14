// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

final class PagerLinkIndicatorTests: XCTestCase {
    func testDropIsReportedImmediatelyEvenWhileClockIsStillLive() {
        let state = PagerLinkIndicator(isMasterServer: false, isLANConnected: false, isProducerLive: true, link: .connected)
        XCTAssertEqual(state, .notConnected)
        XCTAssertFalse(state.isLinked)
    }

    func testReconnectingShowsHost() {
        XCTAssertEqual(PagerLinkIndicator(isMasterServer: false, isLANConnected: false, isProducerLive: true, link: .connecting(host: "david")), .connecting(host: "david"))
    }

    func testProblemsWin() {
        XCTAssertEqual(PagerLinkIndicator(isMasterServer: false, isLANConnected: true, isProducerLive: true, link: .unreachable(host: "david")), .problem("Can't reach david"))
    }

    func testConnectedStates() {
        XCTAssertEqual(PagerLinkIndicator(isMasterServer: false, isLANConnected: true, isProducerLive: false, link: .connected), .waitingForProducer)
        XCTAssertEqual(PagerLinkIndicator(isMasterServer: false, isLANConnected: true, isProducerLive: true, link: .connected), .live)
        XCTAssertEqual(PagerLinkIndicator(isMasterServer: true, isLANConnected: false, isProducerLive: false, link: .idle), .live)
    }
}
