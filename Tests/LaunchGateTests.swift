// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class LaunchGateTests: XCTestCase {
    func testDeferredEngineDoesNotServeUntilReleased() {
        let engine = CueEngine(isMasterServer: true, startsNetworking: true, defersLANServing: true)
        XCTAssertTrue(engine.isLANServingHeld)
        XCTAssertFalse(engine.isLANServing)
        engine.setLANServingHeld(false)
        XCTAssertTrue(engine.isLANServing)
        engine.setLANServingHeld(true)
        XCTAssertFalse(engine.isLANServing)
        engine.setLANServingHeld(false)
        engine.setLANServingSuspended(true)
        XCTAssertFalse(engine.isLANServing)
        engine.setLANServingSuspended(false)
        XCTAssertTrue(engine.isLANServing)
        engine.setLANServingSuspended(true)
        engine.setLANServingSuspended(false)
        engine.setLANServingHeld(true)
        engine.setLANServingSuspended(true)
        engine.setLANServingSuspended(false)
        XCTAssertFalse(engine.isLANServing)
    }

    func testRemoteSessionKeepsLocalServingOffEvenAfterDocumentOpens() {
        let engine = CueEngine(isMasterServer: true, startsNetworking: true, defersLANServing: true)
        engine.setLANServingSuspended(true)
        engine.setLANServingHeld(false)
        XCTAssertFalse(engine.isLANServing)
        engine.setLANServingSuspended(false)
        XCTAssertTrue(engine.isLANServing)
    }

    func testHubDrivesRootSelection() {
        let hub = RemoteProducerHub()
        XCTAssertFalse(hub.isRemoteActive)
        hub.activate(RemoteProducerSession(endpoint: RemoteEndpoint(host: "127.0.0.1", port: 13390)))
        XCTAssertTrue(hub.isRemoteActive)
        hub.disconnect()
        XCTAssertFalse(hub.isRemoteActive)
    }
}
