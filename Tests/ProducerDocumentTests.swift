// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

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

    func testRunSheetLayoutTravelsWithTheDocument() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ProducerDocument.fileExtension)")
        defer { try? FileManager.default.removeItem(at: url) }
        let layout = RunSheetLayoutSettings(
            columnOrder: ["title", "start", "note-Audio"],
            hiddenColumns: ["drift"],
            columnWidths: ["title": 320, "note-Audio": 180],
            nowNextPaneWidth: 410,
            nowNextSplit: 0.4,
            highlightedColumns: ["note-Backstage", "note-Media"],
            sidePaneTab: RunSheetLayoutSettings.detailsTabId,
            detailsTextScale: 1.4,
            detailsUnpinned: true
        )
        let source = CueEngine()
        source.apply(sample())
        source.runSheetLayout = layout
        try source.makeDocument().write(to: url)

        let loaded = try ProducerDocument.read(from: url)
        XCTAssertEqual(loaded.settings.runSheetLayout, layout)
        let target = CueEngine()
        target.runSheetLayout = RunSheetLayoutSettings(columnWidths: ["drift": 99])
        target.apply(loaded)
        XCTAssertEqual(target.runSheetLayout, layout)
        XCTAssertEqual(target.runSheetColumnWidths, ["title": 320, "note-Audio": 180])

        target.apply(sample())
        XCTAssertEqual(target.runSheetLayout, RunSheetLayoutSettings())
        XCTAssertNil(target.makeDocument().settings.runSheetLayout)
    }

    func testHighlightedColumnsRoundTrip() throws {
        let layout = RunSheetLayoutSettings(highlightedColumns: ["note-Backstage", "key"])
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(RunSheetLayoutSettings.self, from: data)
        XCTAssertEqual(decoded.highlightedColumns, ["note-Backstage", "key"])
        XCTAssertEqual(decoded.highlightedSet, ["note-Backstage", "key"])
        XCTAssertTrue(RunSheetLayoutSettings().highlightedSet.isEmpty)
    }

    func testLegacyColumnWidthsDecodeIntoLayout() throws {
        var document = sample()
        document.settings.runSheetLayout = nil
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: document.encoded()) as? [String: Any])
        var settings = try XCTUnwrap(json["settings"] as? [String: Any])
        settings["runSheetColumnWidths"] = ["title": 300.0, "drift": 70.0]
        json["settings"] = settings
        let data = try JSONSerialization.data(withJSONObject: json)
        let loaded = try ProducerDocument.decoded(from: data)
        XCTAssertEqual(loaded.settings.runSheetLayout?.columnWidths, ["title": 300, "drift": 70])
        XCTAssertNil(loaded.settings.runSheetLayout?.columnOrder)
        XCTAssertEqual(loaded.settings.runSheetColumnWidths, ["title": 300, "drift": 70])
    }

    func testColumnOrderNormalization() {
        let defaults = ["status", "start", "title", "note-A", "key"]
        XCTAssertEqual(RunSheetLayoutSettings.normalizedOrder(nil, defaultOrder: defaults), defaults)
        XCTAssertEqual(
            RunSheetLayoutSettings.normalizedOrder(["key", "gone", "title", "key", "status"], defaultOrder: defaults),
            ["key", "title", "status", "start", "note-A"]
        )
        XCTAssertEqual(
            RunSheetLayoutSettings(columnOrder: ["note-A", "start"]).orderedIds(defaultOrder: defaults),
            ["note-A", "start", "status", "title", "key"]
        )
    }

    func testHiddenColumnDefaults() {
        XCTAssertEqual(RunSheetLayoutSettings().hiddenSet, Set(RunSheetLayoutSettings.defaultHiddenColumns))
        XCTAssertTrue(RunSheetLayoutSettings().hiddenSet.contains("bpm"))
        XCTAssertFalse(RunSheetLayoutSettings().hiddenSet.contains("title"))
        XCTAssertTrue(RunSheetLayoutSettings(hiddenColumns: []).hiddenSet.isEmpty)
        XCTAssertEqual(RunSheetLayoutSettings(hiddenColumns: ["key"]).hiddenSet, ["key"])
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

    func testResetToNewDocumentClearsContentButKeepsSettings() {
        let engine = CueEngine()
        engine.apply(sample())
        engine.currentDocumentURL = URL(fileURLWithPath: "/tmp/x.13years")

        engine.resetToNewDocument()

        XCTAssertTrue(engine.planItems.isEmpty)
        XCTAssertTrue(engine.waypoints.isEmpty)
        XCTAssertTrue(engine.serviceSchedules.isEmpty)
        XCTAssertEqual(engine.roles.map(\.id), RoleCue.defaultRoles.map(\.id))
        XCTAssertNil(engine.currentDocumentURL)
        XCTAssertEqual(engine.hourFormatThreshold, .never)
    }

    func testTemplateStripsLiveState() {
        var doc = sample()
        doc.roles[0].state = .go
        doc.planItems[0].elapsedSeconds = 120
        doc.planItems[0].isRunning = true

        let template = doc.asTemplate()

        XCTAssertEqual(template.roles[0].state, .off)
        XCTAssertEqual(template.planItems[0].elapsedSeconds, 0)
        XCTAssertFalse(template.planItems[0].isRunning)
        XCTAssertEqual(template.planItems[0].id, doc.planItems[0].id)
    }

    func testLaunchPreferencesPersist() {
        let suite = "LaunchPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = LaunchPreferences(defaults: defaults)
        XCTAssertEqual(prefs.behavior, .showLauncher)
        prefs.behavior = .reopenLast

        XCTAssertEqual(LaunchPreferences(defaults: defaults).behavior, .reopenLast)
    }

    func testRecentDocumentsMoveToFrontAndCap() {
        XCTAssertEqual(RecentDocuments.updated([1, 2, 3], adding: 3), [3, 1, 2])
        XCTAssertEqual(RecentDocuments.updated([1, 2, 3], adding: 4, limit: 3), [4, 1, 2])
        XCTAssertEqual(RecentDocuments.updated(Array(1...10), adding: 11), [11] + Array(1...9))
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
