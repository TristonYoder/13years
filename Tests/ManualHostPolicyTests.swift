// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

final class ManualHostPolicyTests: XCTestCase {
    func testIPv4() {
        XCTAssertEqual(ManualHostPolicy.validate("192.168.1.20"), .valid("192.168.1.20"))
        XCTAssertEqual(ManualHostPolicy.validate("10.0.0.5").host, "10.0.0.5")
    }

    func testHostnames() {
        XCTAssertEqual(ManualHostPolicy.validate("studio-mac.local"), .valid("studio-mac.local"))
        XCTAssertEqual(ManualHostPolicy.validate("producer"), .valid("producer"))
        XCTAssertEqual(ManualHostPolicy.validate("Studio.Example.com").host, "Studio.Example.com")
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(ManualHostPolicy.validate("  192.168.1.20 \n"), .valid("192.168.1.20"))
        XCTAssertEqual(ManualHostPolicy.validate("\tstudio-mac.local "), .valid("studio-mac.local"))
    }

    func testEmpty() {
        XCTAssertEqual(ManualHostPolicy.validate(""), .empty)
        XCTAssertEqual(ManualHostPolicy.validate("   \n"), .empty)
    }

    func testInvalid() {
        for value in ["999.1.1.1", "1.2.3", "1.2.3.4.5", "bad host", "-bad.local", "a..b", "host_name", "http://x", "192.168.1.20:9000", ".local", String(repeating: "a", count: 300)] {
            XCTAssertNotNil(ManualHostPolicy.validate(value).message, value)
            XCTAssertNil(ManualHostPolicy.validate(value).host, value)
        }
    }

    func testLinkStatusMessages() {
        XCTAssertEqual(ProducerLinkStatus.connecting(host: "x.local").message, "Connecting to x.local…")
        XCTAssertEqual(ProducerLinkStatus.unreachable(host: "x.local").message, "Can't reach x.local")
        XCTAssertTrue(ProducerLinkStatus.localNetworkDenied.message?.contains("Local Network") == true)
        XCTAssertNil(ProducerLinkStatus.connected.message)
    }
}
