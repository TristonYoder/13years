// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit
import Foundation

@MainActor
final class ControlAPIServerIntegrationTests: XCTestCase {
    private var server: ControlAPIServer?

    override func tearDown() {
        server?.stop()
        server = nil
        UserDefaults.standard.removeObject(forKey: "persistedFlow")
        UserDefaults.standard.removeObject(forKey: "persistedRoles")
        UserDefaults.standard.removeObject(forKey: "recentMessages")
        super.tearDown()
    }

    func testServesStateOverRealSocket() async throws {
        let engine = CueEngine()
        let router = ControlAPIRouter(engine: engine)
        let server = ControlAPIServer(router: router)
        self.server = server

        let port: UInt16 = 13399
        let listening = expectation(description: "listener ready")
        server.onStatusChanged = { isUp in
            if isUp { listening.fulfill() }
        }
        server.start(port: port)
        await fulfillment(of: [listening], timeout: 5)

        let url = URL(string: "http://127.0.0.1:\(port)/v1/health")!
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["service"] as? String, "13 Years Control API")
    }

    func testFiresACueOverRealSocket() async throws {
        let engine = CueEngine()
        engine.roles = [RoleCue(id: "host", name: "Host")]
        engine.selectedRoleIds = ["host"]
        let router = ControlAPIRouter(engine: engine)
        let server = ControlAPIServer(router: router)
        self.server = server

        let port: UInt16 = 13398
        let listening = expectation(description: "listener ready")
        server.onStatusChanged = { isUp in
            if isUp { listening.fulfill() }
        }
        server.start(port: port)
        await fulfillment(of: [listening], timeout: 5)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/cues/selected")!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"state":"GO"}"#.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.data(for: request)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(engine.roles.first?.state, .go)
    }

    private func startServer(port: UInt16, engine: CueEngine) async {
        let server = ControlAPIServer(router: ControlAPIRouter(engine: engine))
        self.server = server
        let listening = expectation(description: "listener ready")
        server.onStatusChanged = { isUp in
            if isUp { listening.fulfill() }
        }
        server.start(port: port)
        await fulfillment(of: [listening], timeout: 5)
    }

    func testRejectsBodiesWithoutJSONContentType() async throws {
        let engine = CueEngine()
        engine.roles = [RoleCue(id: "host", name: "Host")]
        engine.selectedRoleIds = ["host"]
        await startServer(port: 13397, engine: engine)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:13397/v1/cues/selected")!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"state":"GO"}"#.utf8)
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 415)
        XCTAssertEqual(engine.roles.first?.state, .off)
    }

    func testForeignOriginIsRefusedAndResponsesHaveNoCORS() async throws {
        let engine = CueEngine()
        await startServer(port: 13396, engine: engine)

        var foreign = URLRequest(url: URL(string: "http://127.0.0.1:13396/v1/state")!)
        foreign.setValue("https://evil.example", forHTTPHeaderField: "Origin")
        let (_, refused) = try await URLSession.shared.data(for: foreign)
        XCTAssertEqual((refused as? HTTPURLResponse)?.statusCode, 403)

        var same = URLRequest(url: URL(string: "http://127.0.0.1:13396/v1/state")!)
        same.setValue("http://127.0.0.1:13396", forHTTPHeaderField: "Origin")
        let (_, allowed) = try await URLSession.shared.data(for: same)
        let http = try XCTUnwrap(allowed as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertNil(http.value(forHTTPHeaderField: "Access-Control-Allow-Origin"))
        XCTAssertEqual(http.value(forHTTPHeaderField: "X-Content-Type-Options"), "nosniff")
        XCTAssertEqual(http.value(forHTTPHeaderField: "X-Frame-Options"), "DENY")
    }
}
