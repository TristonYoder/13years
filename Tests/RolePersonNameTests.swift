// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class RolePersonNameTests: XCTestCase {
    private func patch(_ engine: CueEngine, _ json: String) -> HTTPResponse {
        let router = ControlAPIRouter(engine: engine)
        return router.handle(HTTPRequest(method: "PATCH", path: "/v1/roles/host", body: Data(json.utf8)))
    }

    func testPatchingAnEmptyPersonNameClearsItToNull() throws {
        let engine = CueEngine(startsNetworking: false)
        engine.roles = [RoleCue(id: "host", name: "Host", personName: "Sam")]
        let cleared = patch(engine, #"{"personName":""}"#)
        XCTAssertEqual(cleared.status, 200)
        XCTAssertNil(engine.roles.first?.personName)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: cleared.body) as? [String: Any])
        XCTAssertTrue(object["personName"] == nil || object["personName"] is NSNull)
    }

    func testOmittingPersonNameLeavesItAlone() {
        let engine = CueEngine(startsNetworking: false)
        engine.roles = [RoleCue(id: "host", name: "Host", personName: "Sam")]
        XCTAssertEqual(patch(engine, #"{"name":"Host"}"#).status, 200)
        XCTAssertEqual(engine.roles.first?.personName, "Sam")
        XCTAssertEqual(patch(engine, #"{"personName":"Alex"}"#).status, 200)
        XCTAssertEqual(engine.roles.first?.personName, "Alex")
    }
}
