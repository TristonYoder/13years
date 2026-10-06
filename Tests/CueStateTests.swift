// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

@MainActor
final class CueStateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "persistedRoles")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "persistedRoles")
        super.tearDown()
    }

    func testOnlyThreeStatesRemain() {
        XCTAssertEqual(CueState.allCases, [.off, .standby, .go])
    }

    func testUnknownStateErrorListsExactlyTheThreeRealValues() {
        let engine = CueEngine()
        let router = ControlAPIRouter(engine: engine)
        let response = router.handle(HTTPRequest(
            method: "POST",
            path: "/v1/cues/selected",
            body: Data(#"{"state":"NOPE"}"#.utf8)
        ))

        XCTAssertEqual(response.status, 400)
        let json = try! JSONSerialization.jsonObject(with: response.body) as! [String: Any]
        XCTAssertEqual(json["detail"] as? String, "OFF, STANDBY, GO")
    }

    func testRawValueInitRejectsRetiredStates() {
        XCTAssertNil(CueState(rawValue: "FLASH_GO"))
        XCTAssertNil(CueState(rawValue: "FLASH_STANDBY"))
    }

    func testDecodingRetiredRawValuesMapsToTheSolidState() {
        XCTAssertEqual(try decode("\"FLASH_GO\""), CueState.go)
        XCTAssertEqual(try decode("\"FLASH_STANDBY\""), CueState.standby)
    }

    func testDecodingIsCaseInsensitiveForRetiredAndCurrentValues() {
        XCTAssertEqual(try decode("\"flash_go\""), CueState.go)
        XCTAssertEqual(try decode("\"standby\""), CueState.standby)
    }

    func testDecodingAGenuinelyUnknownValueStillThrows() {
        XCTAssertThrowsError(try decode("\"TEAL\""))
    }

    func testEncodingRoundTrips() {
        for state in CueState.allCases {
            let data = try! JSONEncoder().encode(state)
            XCTAssertEqual(try! JSONDecoder().decode(CueState.self, from: data), state)
        }
    }

    func testAPersistedRosterCarryingARetiredStateSurvivesRestore() {
        let legacy = """
        [
          {"id":"host","name":"Host","state":"FLASH_GO","assignedNoteCategories":["Host Notes"],"lastUpdated":812141383.09},
          {"id":"keys","name":"Keys Player","state":"OFF","assignedNoteCategories":[],"lastUpdated":812141383.09}
        ]
        """
        UserDefaults.standard.set(Data(legacy.utf8), forKey: "persistedRoles")

        let engine = CueEngine()

        XCTAssertEqual(engine.roles.map(\.name), ["Host", "Keys Player"])
        XCTAssertEqual(engine.roles.first?.state, .go, "FLASH_GO read as the GO it always behaved as")
        XCTAssertEqual(engine.roles.first?.assignedNoteCategories, ["Host Notes"])
    }

    func testAPIRejectsRetiredStateForOneRole() {
        let engine = CueEngine()
        let roleId = engine.roles[0].id
        let router = ControlAPIRouter(engine: engine)

        let response = router.handle(HTTPRequest(
            method: "POST",
            path: "/v1/roles/\(roleId)/cue",
            body: Data(#"{"state":"FLASH_GO"}"#.utf8)
        ))

        XCTAssertEqual(response.status, 400, "accepting this was the whole defect: 200, then no blink")
        XCTAssertEqual(engine.roles[0].state, .off, "and it must not have changed the cue on the way out")
    }

    func testAPIStillAcceptsTheThreeRealStates() {
        let engine = CueEngine()
        let roleId = engine.roles[0].id
        let router = ControlAPIRouter(engine: engine)

        for state in ["GO", "STANDBY", "OFF"] {
            let response = router.handle(HTTPRequest(
                method: "POST",
                path: "/v1/roles/\(roleId)/cue",
                body: Data("{\"state\":\"\(state)\"}".utf8)
            ))
            XCTAssertEqual(response.status, 200, "\(state) should still be settable")
            XCTAssertEqual(engine.roles[0].state.rawValue, state)
        }
    }

    private func decode(_ json: String) throws -> CueState {
        try JSONDecoder().decode(CueState.self, from: Data(json.utf8))
    }
}
