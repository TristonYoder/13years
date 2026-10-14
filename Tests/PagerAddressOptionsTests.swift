// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

final class PagerAddressOptionsTests: XCTestCase {
    private func addr(_ host: String, _ iface: String) -> PagerAddress {
        PagerAddress(host: host, kind: PagerAddressOptions.kind(host: host, interface: iface), interface: iface)
    }

    func testKinds() {
        XCTAssertEqual(PagerAddressOptions.kind(host: "192.168.1.20", interface: "en0"), .wifi)
        XCTAssertEqual(PagerAddressOptions.kind(host: "10.0.0.5", interface: "en1"), .ethernet)
        XCTAssertEqual(PagerAddressOptions.kind(host: "100.101.2.3", interface: "utun3"), .vpn)
        XCTAssertEqual(PagerAddressOptions.kind(host: "100.101.2.3", interface: "en0"), .vpn)
        XCTAssertEqual(PagerAddressOptions.kind(host: "10.8.0.2", interface: "utun1"), .vpn)
        XCTAssertEqual(PagerAddressOptions.kind(host: "100.128.0.1", interface: "en0"), .wifi)
        XCTAssertEqual(PagerAddressOptions.kind(host: "169.254.4.4", interface: "en1"), .linkLocal)
        XCTAssertEqual(PagerAddressOptions.kind(host: "fe80::1", interface: "en0"), .linkLocal)
        XCTAssertEqual(PagerAddressOptions.kind(host: "127.0.0.1", interface: "lo0"), .loopback)
        XCTAssertEqual(PagerAddressOptions.kind(host: "10.1.1.1", interface: "pdp_ip0"), .cellular)
        XCTAssertEqual(PagerAddressOptions.kind(host: "192.168.64.1", interface: "bridge100"), .bridge)
    }

    func testLabels() {
        XCTAssertEqual(addr("192.168.1.20", "en0").label, "192.168.1.20 — Wi-Fi (en0)")
        XCTAssertEqual(addr("10.0.0.5", "en1").label, "10.0.0.5 — Ethernet (en1)")
        XCTAssertEqual(addr("100.101.2.3", "utun3").label, "100.101.2.3 — VPN/Tailscale (utun3)")
        XCTAssertEqual(addr("127.0.0.1", "lo0").label, "127.0.0.1 — This device only")
        XCTAssertTrue(addr("169.254.1.1", "en2").label.contains("not routable"))
    }

    func testHostnameNormalisation() {
        XCTAssertEqual(PagerAddressOptions.hostname(from: "studio-mac.local"), "studio-mac.local")
        XCTAssertEqual(PagerAddressOptions.hostname(from: "studio-mac.lan"), "studio-mac.local")
        XCTAssertEqual(PagerAddressOptions.hostname(from: "studio-mac"), "studio-mac.local")
        XCTAssertNil(PagerAddressOptions.hostname(from: "localhost"))
        XCTAssertNil(PagerAddressOptions.hostname(from: " "))
    }

    func testArrangeOrdersHostnameThenV4ThenV6ThenLoopback() {
        let list = PagerAddressOptions.arrange([
            addr("127.0.0.1", "lo0"), addr("fd00::5", "en0"), addr("fe80::1", "en0"),
            addr("192.168.1.20", "en0"), addr("100.101.2.3", "utun3")
        ], hostname: "studio-mac.local")
        XCTAssertEqual(list.map(\.host), ["studio-mac.local", "192.168.1.20", "100.101.2.3", "fd00::5", "127.0.0.1"])
    }

    func testLinkLocalV6KeptOnlyWhenNothingElse() {
        let only = PagerAddressOptions.arrange([addr("127.0.0.1", "lo0"), addr("fe80::1", "en0")], hostname: nil)
        XCTAssertEqual(only.map(\.host), ["fe80::1", "127.0.0.1"])
    }

    func testDuplicatesCollapse() {
        let list = PagerAddressOptions.arrange([addr("10.0.0.5", "en0"), addr("10.0.0.5", "en1")], hostname: nil)
        XCTAssertEqual(list.count, 1)
    }

    func testDefaultPrefersWifiOrEthernetV4OverHostnameAndVPN() {
        let list = PagerAddressOptions.arrange([addr("100.101.2.3", "utun3"), addr("10.0.0.5", "en1"), addr("127.0.0.1", "lo0")], hostname: "a.local")
        XCTAssertEqual(PagerAddressOptions.defaultChoice(list)?.host, "10.0.0.5")
    }

    func testDefaultFallsBackToHostname() {
        let list = PagerAddressOptions.arrange([addr("100.101.2.3", "utun3"), addr("127.0.0.1", "lo0")], hostname: "a.local")
        XCTAssertEqual(PagerAddressOptions.defaultChoice(list)?.host, "a.local")
    }

    func testLocalAddressesHaveLoopback() {
        XCTAssertTrue(PagerAddressOptions.localAddresses(hostName: "x").contains { $0.host == "127.0.0.1" })
    }

    func testCustomParsing() {
        func parse(_ s: String) -> String? {
            PagerAddressOptions.parseCustom(s, defaultPort: 13390).map { "\($0.host)|\($0.port)" }
        }
        XCTAssertEqual(parse("studio.local"), "studio.local|13390")
        XCTAssertEqual(parse(" 192.168.1.9:8080 "), "192.168.1.9|8080")
        XCTAssertEqual(parse("[fe80::1]:9000"), "fe80::1|9000")
        XCTAssertEqual(parse("[fd00::2]"), "fd00::2|13390")
        XCTAssertEqual(parse("fd00::2"), "fd00::2|13390")
        XCTAssertEqual(parse("http://host:81/pager"), "host|81")
        XCTAssertNil(parse(""))
        XCTAssertNil(parse("a b"))
        XCTAssertNil(parse("host:0"))
        XCTAssertNil(parse("host:99999"))
        XCTAssertNil(parse("host:abc"))
        XCTAssertNil(parse(":80"))
        XCTAssertNil(parse("[host]:80"))
        XCTAssertNil(parse("[::1"))
    }

    func testBuilderWithEachAddressForm() {
        let h = PagerAddressOptions.parseCustom("studio.local:8080", defaultPort: 1)!
        XCTAssertEqual(PagerURLBuilder(host: h.host, port: h.port).urlString, "http://studio.local:8080/pager")
        let v6 = PagerAddressOptions.parseCustom("[fd00::2]:9", defaultPort: 1)!
        XCTAssertEqual(PagerURLBuilder(host: v6.host, port: v6.port).urlString, "http://[fd00::2]:9/pager")
        let bare = PagerAddressOptions.parseCustom("fd00::2", defaultPort: 13390)!
        XCTAssertEqual(PagerURLBuilder(host: bare.host, port: bare.port).urlString, "http://[fd00::2]:13390/pager")
        XCTAssertEqual(PagerURLBuilder(host: "studio-mac.local").urlString, "http://studio-mac.local:13390/pager")
    }
}
