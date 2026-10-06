// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
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
        let (_, response) = try await URLSession.shared.data(for: request)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(engine.roles.first?.state, .go)
    }
}
