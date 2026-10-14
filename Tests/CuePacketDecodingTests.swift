// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

final class CuePacketDecodingTests: XCTestCase {
    func testSyncWithoutTimestampDecodes() throws {
        let json = #"{"type":"SYNC","senderId":"esp32","t0":12345}"#
        let before = Date().timeIntervalSince1970
        let packet = try XCTUnwrap(CuePacket.decode(from: Data(json.utf8)))
        XCTAssertEqual(packet.type, .sync)
        XCTAssertEqual(packet.t0, 12345)
        XCTAssertGreaterThanOrEqual(packet.timestamp, before)
    }

    func testTimestampStillDecodedWhenPresent() throws {
        let json = #"{"type":"PING","senderId":"x","timestamp":1700000000.5}"#
        let packet = try XCTUnwrap(CuePacket.decode(from: Data(json.utf8)))
        XCTAssertEqual(packet.timestamp, 1700000000.5)
    }
}
