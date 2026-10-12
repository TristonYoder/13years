// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

@MainActor
final class DocumentAutosaverTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/autosave-test.13years")

    private func makeSaver(_ engine: CueEngine, writes: Box, failing: Bool = false) -> DocumentAutosaver {
        DocumentAutosaver(
            engine: engine,
            debounce: 0.05,
            write: { _, _ in
                writes.count += 1
                if failing { throw CocoaError(.fileWriteUnknown) }
            },
            onFailure: { _, _ in writes.failures += 1 }
        )
    }

    final class Box {
        var count = 0
        var failures = 0
    }

    private func settle() async {
        try? await Task.sleep(nanoseconds: 600_000_000)
    }

    func testNormalizationIgnoresLiveStateElapsedAndSavedAt() {
        var a = ProducerDocument(
            savedAt: Date(timeIntervalSince1970: 1),
            roles: [RoleCue(id: "r", name: "A")],
            waypoints: [],
            serviceSchedules: [],
            planItems: [PCOTimerItem(id: "i", title: "T")],
            activeItemIndex: 0,
            settings: .init(hourFormatThreshold: .never, pcoDefaultServiceTypeId: nil, plotipharRelayHost: "")
        )
        var b = a
        b.savedAt = Date(timeIntervalSince1970: 999)
        b.roles[0].state = .go
        b.roles[0].lastUpdated = Date(timeIntervalSince1970: 50)
        b.planItems[0].elapsedSeconds = 42
        b.planItems[0].isRunning = true
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.normalizedForComparison(), b.normalizedForComparison())
        a.roles[0].name = "B"
        XCTAssertNotEqual(a.normalizedForComparison(), b.normalizedForComparison())
    }

    func testWritesOnceAfterDebouncedChange() async {
        let engine = CueEngine()
        engine.currentDocumentURL = url
        let writes = Box()
        let saver = makeSaver(engine, writes: writes)
        engine.waypoints = [Waypoint(id: "w", name: "One-\(UUID().uuidString)")]
        engine.waypoints = [Waypoint(id: "w", name: "Two-\(UUID().uuidString)")]
        await settle()
        XCTAssertEqual(writes.count, 1)
        XCTAssertFalse(saver.hasUnsavedChanges)
    }

    func testNoWriteWithoutURL() async {
        let engine = CueEngine()
        let writes = Box()
        let saver = makeSaver(engine, writes: writes)
        engine.waypoints = [Waypoint(id: "w", name: "One-\(UUID().uuidString)")]
        await settle()
        XCTAssertEqual(writes.count, 0)
        _ = saver
    }

    func testLiveCueAndTimerChangesDoNotWrite() async {
        let engine = CueEngine()
        engine.currentDocumentURL = url
        engine.planItems = [PCOTimerItem(id: "i", title: "T")]
        let writes = Box()
        let saver = makeSaver(engine, writes: writes)
        saver.reseed()
        engine.planItems[0].elapsedSeconds = 5
        engine.planItems[0].isRunning = true
        engine.roles[0].state = .go
        await settle()
        XCTAssertEqual(writes.count, 0)
    }

    func testReseedAfterApplyPreventsWrite() async {
        let engine = CueEngine()
        engine.currentDocumentURL = url
        let writes = Box()
        let saver = makeSaver(engine, writes: writes)
        var doc = engine.makeDocument()
        doc.waypoints = [Waypoint(id: "w", name: "Opened-\(UUID().uuidString)")]
        engine.apply(doc)
        saver.reseed()
        await settle()
        XCTAssertEqual(writes.count, 0)
        engine.waypoints = []
        await settle()
        XCTAssertEqual(writes.count, 1)
    }

    func testFailureReportedOnceUntilNextChange() async {
        let engine = CueEngine()
        engine.currentDocumentURL = url
        let writes = Box()
        let saver = makeSaver(engine, writes: writes, failing: true)
        engine.waypoints = [Waypoint(id: "w", name: "One-\(UUID().uuidString)")]
        await settle()
        saver.flush()
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.failures, 1)
        engine.waypoints = [Waypoint(id: "w", name: "Two-\(UUID().uuidString)")]
        await settle()
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes.failures, 2)
    }

    private func revertSaver(_ engine: CueEngine, store: DocumentBaselineStore) -> DocumentAutosaver {
        DocumentAutosaver(engine: engine, debounce: 0.05, store: store, write: { _, _ in }, onFailure: { _, _ in })
    }

    private func tempStore() -> DocumentBaselineStore {
        DocumentBaselineStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func testBaselineMovesOnManualSaveNotAutosave() async {
        let engine = CueEngine()
        engine.waypoints = []
        engine.currentDocumentURL = url
        let writes = Box()
        let store = tempStore()
        let saver = DocumentAutosaver(
            engine: engine, debounce: 0.05, store: store,
            write: { _, _ in writes.count += 1 }, onFailure: { _, _ in }
        )
        saver.markOpened()
        XCTAssertFalse(saver.canRevert)
        engine.waypoints = [Waypoint(id: "w", name: "One-\(UUID().uuidString)")]
        await settle()
        XCTAssertEqual(writes.count, 1)
        XCTAssertTrue(saver.canRevert)
        XCTAssertEqual(saver.revertDocument()?.waypoints, [])
        saver.markManualSave()
        XCTAssertFalse(saver.canRevert)
        XCTAssertNil(saver.revertDocument())
        engine.waypoints = []
        await settle()
        XCTAssertEqual(saver.revertDocument()?.waypoints.count, 1)
    }

    func testCanRevertRequiresURL() {
        let engine = CueEngine()
        let saver = revertSaver(engine, store: tempStore())
        engine.waypoints = [Waypoint(id: "w", name: "One-\(UUID().uuidString)")]
        saver.refreshRevert()
        XCTAssertFalse(saver.canRevert)
    }

    func testSidecarSurvivesRelaunchAndRevertRestoresContent() {
        let store = tempStore()
        let engine = CueEngine()
        engine.waypoints = []
        engine.currentDocumentURL = url
        let first = revertSaver(engine, store: store)
        first.markOpened()
        engine.waypoints = [Waypoint(id: "w", name: "Autosaved-\(UUID().uuidString)")]
        let second = revertSaver(engine, store: store)
        second.markOpened()
        XCTAssertTrue(second.canRevert)
        guard let baseline = second.revertDocument() else { return XCTFail() }
        engine.apply(baseline)
        XCTAssertEqual(engine.waypoints, [])
        second.refreshRevert()
        XCTAssertFalse(second.canRevert)
    }
}
