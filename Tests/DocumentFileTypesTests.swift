// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import UniformTypeIdentifiers
import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class DocumentFileTypesTests: XCTestCase {
    private func sample() -> ProducerDocument {
        ProducerDocument(
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            roles: [RoleCue(id: "r1", name: "Lyrics", personName: "Sam", state: .go, plotipharRoleId: nil, lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))],
            waypoints: [Waypoint(id: "w1", name: "Offering")],
            serviceSchedules: [],
            planItems: [PCOTimerItem(id: "i1", title: "Welcome", waypointIds: ["w1"])],
            activeItemIndex: 0,
            settings: .init(hourFormatThreshold: .never, pcoDefaultServiceTypeId: nil, plotipharRelayHost: "relay.example")
        )
    }

    func testEncodedRoundTrip() throws {
        let original = sample()
        XCTAssertEqual(try ProducerDocument.decoded(from: original.encoded()), original)
    }

    func testFileWrapperRoundTrip() throws {
        let file = ProducerDocumentFile(sample())
        let data = try file.document.encoded()
        XCTAssertEqual(try ProducerDocument.decoded(from: data), file.document)
        XCTAssertFalse(file.isTemplate)
    }

    func testTemplateFileClearsLiveState() {
        let file = ProducerDocumentFile(sample(), isTemplate: true)
        XCTAssertTrue(file.isTemplate)
        XCTAssertTrue(file.document.roles.allSatisfy { $0.state == .off })
    }

    func testTypeIdentifiers() {
        XCTAssertEqual(UTType.thirteenYearsDocument.identifier, "app.13years.document")
        XCTAssertEqual(UTType.thirteenYearsTemplate.identifier, "app.13years.template")
    }

    func testInfoPlistsDeclareBothTypes() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for name in ["ProducerMac", "ProducerIOS"] {
            let url = root.appendingPathComponent("Sources/\(name)/Info.plist")
            let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
            let exported = try XCTUnwrap(plist["UTExportedTypeDeclarations"] as? [[String: Any]])
            XCTAssertEqual(Set(exported.compactMap { $0["UTTypeIdentifier"] as? String }), ["app.13years.document", "app.13years.template"], name)
            let extensions = exported.flatMap { ($0["UTTypeTagSpecification"] as? [String: Any])?["public.filename-extension"] as? [String] ?? [] }
            XCTAssertEqual(Set(extensions), [ProducerDocument.fileExtension, ProducerDocument.templateExtension], name)
            let docs = try XCTUnwrap(plist["CFBundleDocumentTypes"] as? [[String: Any]])
            XCTAssertEqual(Set(docs.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }), ["app.13years.document", "app.13years.template"], name)
        }
    }
}
