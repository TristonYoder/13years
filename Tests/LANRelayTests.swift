// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
import Network
@testable import ThirteenYearsClockKit

final class LANRelayTests: XCTestCase {
    func testModeDefaultsToControlOnlyAndPersists() {
        let suite = UserDefaults(suiteName: "LANRelayTests-\(UUID().uuidString)")!
        XCTAssertEqual(RemoteLANMode.stored(in: suite), .controlOnly)
        for mode in RemoteLANMode.allCases {
            RemoteLANMode.store(mode, in: suite)
            XCTAssertEqual(RemoteLANMode.stored(in: suite), mode)
        }
        suite.set("bogus", forKey: RemoteLANMode.defaultsKey)
        XCTAssertEqual(RemoteLANMode.stored(in: suite), .controlOnly)
        XCTAssertEqual(RemoteLANMode.allCases.map(\.displayName), ["Control Only", "Introducer", "Local Relay"])
    }

    func testDiscoveryUsesHintForIntroducer() {
        let service = NWEndpoint.service(name: "Booth", type: "_13years._tcp", domain: "local.", interface: nil)
        let hinted = LANDiscoveryRouting.target(serviceEndpoint: service, txt: ["mode": "introducer", "host": "10.0.0.5", "port": "13380", "hostip": "10.0.0.5", "ip": "192.168.1.9"])
        XCTAssertTrue(hinted.isIntroduced)
        XCTAssertEqual(hinted.endpoint, .hostPort(host: "10.0.0.5", port: 13380))
        XCTAssertEqual(hinted.advertisedIPv4, "10.0.0.5")
    }

    func testDiscoveryPrefersResolvedHostIPOverHostname() {
        let service = NWEndpoint.service(name: "Booth", type: "_13years._tcp", domain: "local.", interface: nil)
        let byIP = LANDiscoveryRouting.target(serviceEndpoint: service, txt: ["mode": "introducer", "host": "david", "port": "13380", "hostip": "100.75.81.4"])
        XCTAssertEqual(byIP.endpoint, .hostPort(host: "100.75.81.4", port: 13380))
        let byName = LANDiscoveryRouting.target(serviceEndpoint: service, txt: ["mode": "introducer", "host": "david", "port": "13380", "hostip": "not-an-ip"])
        XCTAssertEqual(byName.endpoint, .hostPort(host: "david", port: 13380))
        XCTAssertNil(byName.advertisedIPv4)
    }

    func testOnlyActiveModesRetargetAnExistingConnection() {
        XCTAssertTrue(LANDiscoveryRouting.advertisesMode(txt: ["mode": "introducer", "host": "david", "port": "13380"]))
        XCTAssertTrue(LANDiscoveryRouting.advertisesMode(txt: ["mode": "relay"]))
        XCTAssertFalse(LANDiscoveryRouting.advertisesMode(txt: [:]))
        XCTAssertFalse(LANDiscoveryRouting.advertisesMode(txt: ["ip": "10.0.0.2", "did": "x"]))
    }

    func testDiscoveryFallsBackToServiceEndpoint() {
        let service = NWEndpoint.service(name: "Booth", type: "_13years._tcp", domain: "local.", interface: nil)
        for txt in [["ip": "192.168.1.9"], ["mode": "relay", "host": "10.0.0.5", "port": "13380", "ip": "192.168.1.9"], ["host": "10.0.0.5"], ["host": "10.0.0.5", "port": "0"], ["host": "", "port": "13380"], ["host": "x", "port": "abc"]] as [[String: String]] {
            let target = LANDiscoveryRouting.target(serviceEndpoint: service, txt: txt)
            XCTAssertFalse(target.isIntroduced, "\(txt)")
            XCTAssertEqual(target.endpoint, service)
            XCTAssertEqual(target.advertisedIPv4, txt["ip"])
        }
    }

    func testRelayProxiesBytesBothWays() throws {
        let upstream = try NWListener(using: .tcp)
        let queue = DispatchQueue(label: "test.upstream")
        let upstreamReady = expectation(description: "upstream ready")
        var held: [NWConnection] = []
        upstream.newConnectionHandler = { connection in
            held.append(connection)
            connection.start(queue: queue)
            func echo() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, done, error in
                    if let data, !data.isEmpty { connection.send(content: data, completion: .contentProcessed { _ in }) }
                    if !done && error == nil { echo() }
                }
            }
            echo()
        }
        upstream.stateUpdateHandler = { if case .ready = $0 { upstreamReady.fulfill() } }
        upstream.start(queue: queue)
        wait(for: [upstreamReady], timeout: 5)
        let upstreamPort = try XCTUnwrap(upstream.port?.rawValue)
        defer { upstream.cancel() }

        let relay = LANRelayService(listenPort: 0, advertise: false)
        let relayReady = expectation(description: "relay ready")
        relayReady.assertForOverFulfill = false
        relay.onStatusChanged = { if relay.state == .relaying { relayReady.fulfill() } }
        relay.start(mode: .localRelay, upstreamHost: "127.0.0.1", upstreamPort: upstreamPort, advertisedName: "Test", deviceId: "did")
        wait(for: [relayReady], timeout: 5)
        defer { relay.stop() }
        let relayPort = try XCTUnwrap(relay.boundPort)

        let client = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: relayPort)!, using: .tcp)
        let echoed = expectation(description: "echo")
        let counted = expectation(description: "count 1")
        counted.assertForOverFulfill = false
        relay.onStatusChanged = { if relay.relayedConnectionCount == 1 { counted.fulfill() } }
        client.stateUpdateHandler = { state in
            if case .ready = state {
                client.send(content: Data("hello-relay".utf8), completion: .contentProcessed { _ in })
                client.receive(minimumIncompleteLength: 11, maximumLength: 64) { data, _, _, _ in
                    XCTAssertEqual(data.flatMap { String(data: $0, encoding: .utf8) }, "hello-relay")
                    echoed.fulfill()
                }
            }
        }
        client.start(queue: queue)
        wait(for: [echoed, counted], timeout: 10)

        let dropped = expectation(description: "count 0")
        dropped.assertForOverFulfill = false
        relay.onStatusChanged = { if relay.relayedConnectionCount == 0 { dropped.fulfill() } }
        client.cancel()
        wait(for: [dropped], timeout: 10)
    }
    func testIntroducerNeverCarriesTraffic() throws {
        let upstream = try NWListener(using: .tcp)
        let queue = DispatchQueue(label: "test.introducer.upstream")
        let upstreamReady = expectation(description: "upstream ready")
        var upstreamConnections = 0
        upstream.newConnectionHandler = { connection in
            upstreamConnections += 1
            connection.cancel()
        }
        upstream.stateUpdateHandler = { if case .ready = $0 { upstreamReady.fulfill() } }
        upstream.start(queue: queue)
        wait(for: [upstreamReady], timeout: 5)
        let upstreamPort = try XCTUnwrap(upstream.port?.rawValue)
        defer { upstream.cancel() }

        let relay = LANRelayService(listenPort: 0, advertise: false)
        let ready = expectation(description: "introducer ready")
        ready.assertForOverFulfill = false
        relay.onStatusChanged = { if case .advertising = relay.state { ready.fulfill() } }
        relay.start(mode: .introducer, upstreamHost: "127.0.0.1", upstreamPort: upstreamPort, advertisedName: "Test", deviceId: "did")
        wait(for: [ready], timeout: 5)
        defer { relay.stop() }
        let relayPort = try XCTUnwrap(relay.boundPort)

        let client = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: relayPort)!, using: .tcp)
        let refused = expectation(description: "refused")
        refused.assertForOverFulfill = false
        client.stateUpdateHandler = { state in
            if case .ready = state {
                client.send(content: Data("ping".utf8), completion: .contentProcessed { _ in })
                client.receive(minimumIncompleteLength: 1, maximumLength: 64) { data, _, done, error in
                    if (data ?? Data()).isEmpty && (done || error != nil) { refused.fulfill() }
                }
            }
            if case .failed = state { refused.fulfill() }
            if case .cancelled = state { refused.fulfill() }
        }
        client.start(queue: queue)
        wait(for: [refused], timeout: 10)
        client.cancel()
        XCTAssertEqual(relay.relayedConnectionCount, 0)
        XCTAssertEqual(upstreamConnections, 0)
    }

}
