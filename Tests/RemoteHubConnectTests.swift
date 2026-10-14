// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class RemoteHubConnectTests: XCTestCase {
    func testRecentConnectDoesNotShowSheetUntilItFails() async throws {
        let hub = RemoteProducerHub()
        let endpoint = try XCTUnwrap(RemoteEndpoint.parse("127.0.0.1:1"))
        hub.connect(to: endpoint)
        XCTAssertFalse(hub.isConnectPresented)
        XCTAssertNotNil(hub.connectingTo)
        let deadline = Date().addingTimeInterval(15)
        while hub.connectingTo != nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNil(hub.connectingTo)
        XCTAssertNil(hub.session)
        XCTAssertTrue(hub.isConnectPresented)
        XCTAssertEqual(hub.failedEndpoint?.address, endpoint.address)
        XCTAssertNotNil(hub.failureMessage)
        hub.clearFailure()
        XCTAssertNil(hub.failedEndpoint)
    }

    func testCancelStopsConnecting() throws {
        let hub = RemoteProducerHub()
        hub.connect(to: try XCTUnwrap(RemoteEndpoint.parse("127.0.0.1:1")))
        hub.cancelConnect()
        XCTAssertNil(hub.connectingTo)
        XCTAssertFalse(hub.isConnectPresented)
    }
}
