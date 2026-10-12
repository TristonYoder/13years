// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

@MainActor
final class DocumentAutosaverTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/autosave-test.13years")

    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var _count = 0
        private var _failures = 0
        var count: Int { lock.withLock { _count } }
        var failures: Int { lock.withLock { _failures } }
        func bump() { lock.withLock { _count += 1 } }
        func fail() { lock.withLock { _failures += 1 } }
    }

    private func makeSaver(_ engine: CueEngine, writes: Box, failing: Bool = false, indexThrottle: TimeInterval = 10) -> DocumentAutosaver {
        DocumentAutosaver(
            engine: engine,
            debounce: 0.05,
            indexThrottle: indexThrottle,
            write: { _, _ in
                writes.bump()
                if failing { throw CocoaError(.fileWriteUnknown) }
            },
            onFailure: { _, _ in writes.fail() }
        )
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
        XCTAssertEqual(saver.status, .saved)
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

    func testFailureSuspendsAutosaveUntilManualSave() async {
        let engine = CueEngine()
        engine.currentDocumentURL = url
        let writes = Box()
        let saver = makeSaver(engine, writes: writes, failing: true)
        engine.waypoints = [Waypoint(id: "w", name: "One-\(UUID().uuidString)")]
        await settle()
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.failures, 1)
        XCTAssertEqual(saver.status, .failed)
        engine.waypoints = [Waypoint(id: "w", name: "Two-\(UUID().uuidString)")]
        await settle()
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(saver.status, .failed)
        saver.markManualSave()
        XCTAssertFalse(saver.isAutosaveSuspended)
    }

    func testForcedFlushWritesOnlyWhenDirty() {
        let engine = CueEngine()
        engine.currentDocumentURL = url
        let writes = Box()
        let saver = makeSaver(engine, writes: writes)
        XCTAssertNil(saver.flush(force: true))
        XCTAssertEqual(writes.count, 0)
        engine.waypoints = [Waypoint(id: "w", name: "One-\(UUID().uuidString)")]
        XCTAssertNil(saver.flush(force: true))
        XCTAssertEqual(writes.count, 1)
        XCTAssertNil(saver.flush(force: true))
        XCTAssertEqual(writes.count, 1)
    }

    func testForcedFlushRetriesAfterFailureAndReportsError() {
        let engine = CueEngine()
        engine.currentDocumentURL = url
        let writes = Box()
        let saver = makeSaver(engine, writes: writes, failing: true)
        engine.waypoints = [Waypoint(id: "w", name: "One-\(UUID().uuidString)")]
        XCTAssertNotNil(saver.flush(force: true))
        XCTAssertNotNil(saver.flush(force: true))
        XCTAssertEqual(writes.count, 2)
    }

    func testStatusTracksUntitledAndSaved() {
        let engine = CueEngine()
        let saver = makeSaver(engine, writes: Box())
        saver.refreshStatus()
        XCTAssertEqual(saver.status, .untitled)
        engine.currentDocumentURL = url
        saver.reseed()
        XCTAssertEqual(saver.status, .saved)
    }

    func testUntitledChangesAreDetected() {
        let engine = CueEngine()
        let saver = makeSaver(engine, writes: Box())
        XCTAssertFalse(saver.hasUnsavedUntitledChanges)
        engine.waypoints = [Waypoint(id: "w", name: "One-\(UUID().uuidString)")]
        XCTAssertTrue(saver.hasUnsavedUntitledChanges)
    }

    func testIndexOnlyChangesAreThrottledWhileTimerRuns() async {
        let engine = CueEngine()
        engine.currentDocumentURL = url
        engine.planItems = [PCOTimerItem(id: "a", title: "A"), PCOTimerItem(id: "b", title: "B")]
        let writes = Box()
        let saver = makeSaver(engine, writes: writes, indexThrottle: 1.5)
        saver.reseed()
        engine.waypoints = [Waypoint(id: "w", name: "One-\(UUID().uuidString)")]
        await settle()
        XCTAssertEqual(writes.count, 1)
        engine.planItems[0].isRunning = true
        engine.activeItemIndex = 1
        await settle()
        XCTAssertEqual(writes.count, 1)
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertEqual(writes.count, 2)
    }

    private func revertSaver(_ engine: CueEngine) -> DocumentAutosaver {
        DocumentAutosaver(engine: engine, debounce: 0.05, write: { _, _ in }, onFailure: { _, _ in })
    }

    func testBaselineMovesOnManualSaveNotAutosave() async {
        let engine = CueEngine()
        engine.waypoints = []
        engine.currentDocumentURL = url
        let writes = Box()
        let saver = makeSaver(engine, writes: writes)
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
        let saver = revertSaver(engine)
        engine.waypoints = [Waypoint(id: "w", name: "One-\(UUID().uuidString)")]
        saver.refreshRevert()
        XCTAssertFalse(saver.canRevert)
    }

    func testRevertBaselineIsSessionScoped() {
        let engine = CueEngine()
        engine.waypoints = []
        engine.currentDocumentURL = url
        let first = revertSaver(engine)
        first.markOpened()
        engine.waypoints = [Waypoint(id: "w", name: "Autosaved-\(UUID().uuidString)")]
        let second = revertSaver(engine)
        second.markOpened()
        XCTAssertFalse(second.canRevert)
        XCTAssertNil(second.revertDocument())
    }
}

@MainActor
final class DocumentSafetyTests: XCTestCase {
    func testDecodeErrorsAreFriendly() {
        XCTAssertThrowsError(try ProducerDocument.decoded(from: Data("not json".utf8))) { error in
            XCTAssertEqual(error.localizedDescription, ProducerDocument.LoadError.unreadable.errorDescription)
        }
        XCTAssertThrowsError(try ProducerDocument.decoded(from: Data("{\"version\":\"x\"}".utf8))) { error in
            XCTAssertTrue(error is ProducerDocument.LoadError)
        }
    }

    func testMissingOptionalFieldsDecodeWithDefaults() throws {
        let document = try ProducerDocument.decoded(from: Data("{\"version\":1}".utf8))
        XCTAssertEqual(document.planItems, [])
        XCTAssertEqual(document.activeItemIndex, 0)
        XCTAssertEqual(document.settings.plotipharRelayHost, "")
    }

    func testNewerVersionIsRejected() {
        XCTAssertThrowsError(try ProducerDocument.decoded(from: Data("{\"version\":99}".utf8))) { error in
            guard case ProducerDocument.LoadError.newerVersion(99) = error else { return XCTFail() }
        }
    }

    func testFileNotFoundClassification() {
        XCTAssertTrue(RecentDocuments.isFileNotFound(CocoaError(.fileReadNoSuchFile)))
        XCTAssertTrue(RecentDocuments.isFileNotFound(CocoaError(.fileNoSuchFile)))
        XCTAssertFalse(RecentDocuments.isFileNotFound(CocoaError(.fileReadNoPermission)))
        XCTAssertFalse(RecentDocuments.isFileNotFound(ProducerDocument.LoadError.newerVersion(2)))
    }

    func testAvailabilityDistinguishesMissingFromOffline() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let present = directory.appendingPathComponent("a.13years")
        try Data().write(to: present)
        XCTAssertEqual(RecentDocuments.availability(of: present), .present)
        XCTAssertEqual(RecentDocuments.availability(of: directory.appendingPathComponent("gone.13years")), .missing)
        XCTAssertEqual(RecentDocuments.availability(of: URL(fileURLWithPath: "/Volumes/NoSuchVolume-\(UUID().uuidString)/x.13years")), .unavailable)
        try Data().write(to: directory.appendingPathComponent(".cloud.13years.icloud"))
        XCTAssertEqual(RecentDocuments.availability(of: directory.appendingPathComponent("cloud.13years")), .unavailable)
    }

    func testSplashDuration() {
        XCTAssertEqual(SplashCoordinator.displayDuration(isFirstLaunch: true, reduceMotion: false), 2.0)
        XCTAssertEqual(SplashCoordinator.displayDuration(isFirstLaunch: false, reduceMotion: false), 0.6)
        XCTAssertEqual(SplashCoordinator.displayDuration(isFirstLaunch: true, reduceMotion: true), 0.6)
    }

    func testSaveStatusText() {
        XCTAssertEqual(DocumentSaveStatus.untitled.text, "Untitled — not saved")
        XCTAssertEqual(DocumentSaveStatus.failed.text, "Not saved — click to Save As…")
    }
}
