// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

final class ManualHostPolicyTests: XCTestCase {
    func testIPv4() {
        XCTAssertEqual(ManualHostPolicy.validate("192.168.1.20"), .valid(host: "192.168.1.20", port: nil))
        XCTAssertEqual(ManualHostPolicy.validate("10.0.0.5").host, "10.0.0.5")
    }

    func testHostnames() {
        XCTAssertEqual(ManualHostPolicy.validate("studio-mac.local"), .valid(host: "studio-mac.local", port: nil))
        XCTAssertEqual(ManualHostPolicy.validate("producer"), .valid(host: "producer", port: nil))
        XCTAssertEqual(ManualHostPolicy.validate("Studio.Example.com").host, "Studio.Example.com")
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(ManualHostPolicy.validate("  192.168.1.20 \n"), .valid(host: "192.168.1.20", port: nil))
        XCTAssertEqual(ManualHostPolicy.validate("\tstudio-mac.local "), .valid(host: "studio-mac.local", port: nil))
    }

    func testEmpty() {
        XCTAssertEqual(ManualHostPolicy.validate(""), .empty)
        XCTAssertEqual(ManualHostPolicy.validate("   \n"), .empty)
    }

    func testInvalid() {
        for value in ["999.1.1.1", "1.2.3", "1.2.3.4.5", "bad host", "-bad.local", "a..b", "host_name", "http://x", ".local", String(repeating: "a", count: 300)] {
            XCTAssertNotNil(ManualHostPolicy.validate(value).message, value)
            XCTAssertNil(ManualHostPolicy.validate(value).host, value)
        }
    }

    func testPorts() {
        XCTAssertEqual(ManualHostPolicy.validate("192.168.1.20:9000"), .valid(host: "192.168.1.20", port: 9000))
        XCTAssertEqual(ManualHostPolicy.validate("clock.example.com:443"), .valid(host: "clock.example.com", port: 443))
        XCTAssertEqual(ManualHostPolicy.validate("[::1]:13380"), .valid(host: "::1", port: 13380))
        XCTAssertEqual(ManualHostPolicy.validate("[fe80::1]"), .valid(host: "fe80::1", port: nil))
        XCTAssertEqual(ManualHostPolicy.validate("10.0.0.5:65535").port, 65535)
        XCTAssertEqual(ManualHostPolicy.validate("192.168.1.20:9000").endpoint, "192.168.1.20:9000")
        XCTAssertEqual(ManualHostPolicy.validate("[::1]:9000").endpoint, "[::1]:9000")
        XCTAssertNil(ManualHostPolicy.validate("10.0.0.5").port)
    }

    func testPublicHosts() {
        XCTAssertEqual(ManualHostPolicy.validate("100.75.81.4:13380").host, "100.75.81.4")
        XCTAssertEqual(ManualHostPolicy.validate("8.8.8.8").host, "8.8.8.8")
        XCTAssertEqual(ManualHostPolicy.validate("clock.example.com").host, "clock.example.com")
    }

    func testInvalidPorts() {
        for value in ["10.0.0.5:0", "10.0.0.5:70000", "10.0.0.5:abc", "10.0.0.5:", "studio.local:-1", ":9000", "[::1]:0", "[::1", "::1", "[::1]x"] {
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
