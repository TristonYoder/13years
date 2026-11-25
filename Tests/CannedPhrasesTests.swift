// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class CannedPhrasesTests: XCTestCase {
    private func makeEngine() -> (CueEngine, String) {
        let engine = CueEngine()
        let role = engine.addRole(name: "Audio")
        return (engine, role.id)
    }

    func testRoleWithoutOwnPhrasesGetsSharedList() {
        let (engine, id) = makeEngine()
        XCTAssertEqual(engine.phrases(forRoleId: id), CueEngine.defaultSharedPhrases)
        XCTAssertEqual(engine.phrases(forRoleId: nil), CueEngine.defaultSharedPhrases)
    }

    func testOwnPhrasesComeFirstAndSharedFollowWithoutDuplicates() {
        let (engine, id) = makeEngine()
        engine.setSharedPhrases(["Copy", "Standby"])
        engine.setPhrases(forRoleId: id, phrases: ["Mic check", "Copy", "  "], usesShared: true)
        XCTAssertEqual(engine.phrases(forRoleId: id), ["Mic check", "Copy", "Standby"])
    }

    func testRoleCanOptOutOfSharedPhrases() {
        let (engine, id) = makeEngine()
        engine.setPhrases(forRoleId: id, phrases: ["Mic check"], usesShared: false)
        XCTAssertEqual(engine.phrases(forRoleId: id), ["Mic check"])
    }

    func testPhrasesSurviveEncodeDecode() throws {
        var role = RoleCue(name: "CG")
        role.cannedPhrases = ["Next slide"]
        role.usesSharedPhrases = false
        let decoded = try JSONDecoder().decode(RoleCue.self, from: JSONEncoder().encode(role))
        XCTAssertEqual(decoded.cannedPhrases, ["Next slide"])
        XCTAssertEqual(decoded.usesSharedPhrases, false)
    }

    func testOlderRoleDataDecodesWithoutPhrases() throws {
        let json = #"{"id":"r","name":"Old","state":"off","lastUpdated":0,"assignedNoteCategories":[]}"#
        let role = try JSONDecoder().decode(RoleCue.self, from: Data(json.utf8))
        XCTAssertNil(role.cannedPhrases)
        XCTAssertNil(role.usesSharedPhrases)
    }
}
