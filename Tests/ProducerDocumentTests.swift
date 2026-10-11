// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

@MainActor
final class ProducerDocumentTests: XCTestCase {
    private func sample() -> ProducerDocument {
        ProducerDocument(
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            roles: [RoleCue(id: "r1", name: "Lyrics", personName: "Sam", plotipharRoleId: "p9", lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))],
            selectedRoleIds: ["r1"],
            waypoints: [Waypoint(id: "w1", name: "Offering")],
            serviceSchedules: [ServiceSchedule(id: "s1", title: "Sunday", startsAt: Date(timeIntervalSince1970: 1_700_100_000))],
            planItems: [PCOTimerItem(id: "i1", title: "Welcome", waypointIds: ["w1"])],
            activeItemIndex: 0,
            settings: .init(hourFormatThreshold: .never, pcoDefaultServiceTypeId: "st1", plotipharRelayHost: "relay.example")
        )
    }

    func testRoundTripPreservesIdsAndSettings() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ProducerDocument.fileExtension)")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = sample()
        try original.write(to: url)
        XCTAssertEqual(try ProducerDocument.read(from: url), original)
    }

    func testApplyRestoresSelectedRoles() {
        let engine = CueEngine()
        var doc = sample()
        doc.roles.append(RoleCue(id: "r2", name: "Camera"))
        doc.selectedRoleIds = ["r2", "gone"]
        engine.apply(doc)
        XCTAssertEqual(engine.selectedRoleIds, ["r2"])
        XCTAssertEqual(engine.makeDocument().selectedRoleIds, ["r2"])
    }

    func testRejectsNewerFormat() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ProducerDocument.fileExtension)")
        defer { try? FileManager.default.removeItem(at: url) }
        var doc = sample()
        doc.version = ProducerDocument.currentVersion + 1
        try doc.write(to: url)
        XCTAssertThrowsError(try ProducerDocument.read(from: url))
    }
}
