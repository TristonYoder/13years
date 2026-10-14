// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

final class AssignAndLaunchTests: XCTestCase {
    private func plan(_ remote: RemoteAssignContext?) -> AssignProducerPlan? {
        AssignProducerPolicy.plan(selfAddress: "192.168.1.5", remote: remote, resolveServer: { $0 == "clock.example.com" ? "203.0.113.9" : AssignProducerPolicy.resolveIPv4($0) })
    }

    func testStandalonePlanIsOwnAddress() {
        let result = plan(nil)
        XCTAssertEqual(result, AssignProducerPlan(host: "192.168.1.5"))
        XCTAssertNil(result?.jsonObject["port"])
        XCTAssertNil(result?.jsonObject["mode"])
    }

    func testLocalRelayPlanIsOwnAddress() {
        XCTAssertEqual(plan(RemoteAssignContext(endpointHost: "10.0.0.2", lanPort: 13380, lanMode: .localRelay)), AssignProducerPlan(host: "192.168.1.5"))
    }

    func testIntroducerAndControlOnlyUseServer() {
        for mode in [RemoteLANMode.introducer, .controlOnly] {
            let result = plan(RemoteAssignContext(endpointHost: "clock.example.com", lanPort: 14000, lanMode: mode))
            XCTAssertEqual(result, AssignProducerPlan(host: "203.0.113.9", port: 14000, introducer: true))
            XCTAssertEqual(result?.jsonObject["mode"] as? String, "introducer")
            XCTAssertEqual(result?.jsonObject["port"] as? Int, 14000)
        }
        XCTAssertEqual(plan(RemoteAssignContext(endpointHost: "10.0.0.2", lanPort: nil, lanMode: .introducer))?.port, 13380)
        XCTAssertNil(plan(RemoteAssignContext(endpointHost: "no-such-host.invalid", lanPort: 13380, lanMode: .introducer)))
    }

    private func accept(_ object: [String: Any], sender: String? = "192.168.1.5") -> AssignProducerPolicy.Accepted? {
        AssignProducerPolicy.accept(object, senderIP: sender)
    }

    func testAcceptanceRules() {
        XCTAssertEqual(accept(["type": "ASSIGN_PRODUCER", "host": "192.168.1.5"]), .init(host: "192.168.1.5", port: 13380))
        XCTAssertNil(accept(["type": "ASSIGN_PRODUCER", "host": "192.168.1.9"]))
        XCTAssertEqual(accept(["type": "ASSIGN_PRODUCER", "host": "192.168.1.9", "mode": "introducer"])?.host, "192.168.1.9")
        XCTAssertEqual(accept(["type": "ASSIGN_PRODUCER", "host": "203.0.113.9", "mode": "introducer", "port": 14000]), .init(host: "203.0.113.9", port: 14000))
        XCTAssertEqual(accept(["type": "ASSIGN_PRODUCER", "host": "8.8.8.8"], sender: "8.8.8.8")?.host, "8.8.8.8")
        XCTAssertNil(accept(["type": "ASSIGN_PRODUCER", "host": "256.1.1.1", "mode": "introducer"]))
        XCTAssertNil(accept(["type": "ASSIGN_PRODUCER", "host": "a b", "mode": "introducer"]))
        XCTAssertNil(accept(["type": "OTHER", "host": "192.168.1.5"]))
        for bad in [0, 65536, -1] {
            XCTAssertNil(accept(["type": "ASSIGN_PRODUCER", "host": "10.0.0.1", "mode": "introducer", "port": bad]))
        }
        XCTAssertNil(accept(["type": "ASSIGN_PRODUCER", "host": "10.0.0.1", "mode": "introducer", "port": "80"]))
        XCTAssertEqual(accept(["type": "ASSIGN_PRODUCER", "host": "10.0.0.1", "mode": "introducer", "port": 65535])?.port, 65535)
        XCTAssertEqual(accept(["type": "ASSIGN_PRODUCER", "host": "10.0.0.1", "mode": "introducer", "port": 14000])?.endpoint, "10.0.0.1:14000")
        XCTAssertEqual(AssignProducerPolicy.parseStored("10.0.0.1:14000"), .init(host: "10.0.0.1", port: 14000))
    }

    func testSettingsGating() {
        XCTAssertTrue(SettingsGating.isLocalControlAPIConfigurable(isRemoteSession: false))
        XCTAssertFalse(SettingsGating.isLocalControlAPIConfigurable(isRemoteSession: true))
    }

    func testLaunchPolicy() {
        XCTAssertEqual(LaunchPolicy.decide(behavior: .connectRemote, remoteAddress: "studio.local:13391"), .connectRemote(RemoteEndpoint(host: "studio.local", port: 13391)))
        XCTAssertEqual(LaunchPolicy.decide(behavior: .connectRemote, remoteAddress: "10.0.0.4"), .connectRemote(RemoteEndpoint(host: "10.0.0.4")))
        XCTAssertEqual(LaunchPolicy.decide(behavior: .connectRemote, remoteAddress: ""), .showLauncher)
        XCTAssertEqual(LaunchPolicy.decide(behavior: .connectRemote, remoteAddress: "bad host"), .showLauncher)
        XCTAssertEqual(LaunchPolicy.decide(behavior: .reopenLast, remoteAddress: "10.0.0.4"), .reopenLast)
    }
}
