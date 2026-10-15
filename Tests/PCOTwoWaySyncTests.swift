// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

final class PCOPlanDiffTests: XCTestCase {
    private func item(_ id: String, _ title: String? = nil, length: Int = 300, notes: [String: String] = [:]) -> PCOTimerItem {
        PCOTimerItem(id: id, title: title ?? "Item \(id)", lengthInSeconds: length, notes: notes, pcoServiceTypeId: "st", pcoPlanId: "p")
    }

    func testIdenticalPlansHaveNoChanges() {
        let plan = [item("a", notes: ["Lights": ""]), item("b")]
        XCTAssertTrue(PCOPlanDiff.changes(from: plan, to: [item("a"), item("b")]).isEmpty)
    }

    func testDetectsEveryKindOfChange() {
        let baseline = [item("a"), item("b", "Sermon"), item("c", length: 180), item("d", notes: ["Lights": "dim"]), item("e")]
        let remote = [item("c", length: 240), item("b", "Message"), item("a"), item("d", notes: ["Lights": "full"]), item("f", "Baptism")]
        let changes = PCOPlanDiff.changes(from: baseline, to: remote)
        let kinds = changes.map(\.kind)

        XCTAssertTrue(kinds.contains(.added))
        XCTAssertTrue(kinds.contains(.removed))
        XCTAssertTrue(kinds.contains(.retitled))
        XCTAssertTrue(kinds.contains(.length))
        XCTAssertTrue(kinds.contains(.notes))
        XCTAssertTrue(kinds.contains(.reordered))
        XCTAssertEqual(changes.first { $0.kind == .length }?.detail, "3:00 to 4:00")
        XCTAssertEqual(changes.first { $0.kind == .notes }?.detail, "Lights")
        XCTAssertEqual(changes.first { $0.kind == .added }?.title, "Baptism")
        XCTAssertEqual(changes.first { $0.kind == .removed }?.itemId, "e")
    }

    func testAddingAndRemovingAloneIsNotAReorder() {
        let baseline = [item("a"), item("b"), item("c")]
        let remote = [item("a"), item("x"), item("c")]
        XCTAssertFalse(PCOPlanDiff.isReordered(from: baseline, to: remote))
    }

    func testRevisionTracksContent() {
        let plan = [item("a"), item("b")]
        XCTAssertEqual(PCOPlanDiff.revision(of: plan), PCOPlanDiff.revision(of: plan))
        XCTAssertNotEqual(PCOPlanDiff.revision(of: plan), PCOPlanDiff.revision(of: [item("b"), item("a")]))
        XCTAssertNotEqual(PCOPlanDiff.revision(of: plan), PCOPlanDiff.revision(of: [item("a", notes: ["Lights": "on"]), item("b")]))
    }

    func testMergeOnlyOverwritesFieldsChangedRemotely() {
        let baseline = [item("a", "Welcome", length: 120), item("b", "Song")]
        var localA = item("a", "Welcome Everyone", length: 120)
        localA.elapsedSeconds = 45
        localA.waypointIds = ["w1"]
        let local = [localA, item("b", "Song")]
        let remote = [item("a", "Welcome", length: 180), item("b", "Worship Song")]

        let merged = PCOPlanDiff.merge(remote: remote, baseline: baseline, into: local, keeping: nil)

        XCTAssertEqual(merged.map(\.title), ["Welcome Everyone", "Worship Song"])
        XCTAssertEqual(merged[0].lengthInSeconds, 180)
        XCTAssertEqual(merged[0].elapsedSeconds, 45)
        XCTAssertEqual(merged[0].waypointIds, ["w1"])
    }

    func testMergeKeepsLocalOnlyItemsAndTheActiveItem() {
        let baseline = [item("a"), item("b"), item("c")]
        let localOnly = PCOTimerItem(id: "mine", title: "Walk-in loop")
        let local = [item("a"), localOnly, item("b"), item("c")]
        let remote = [item("a"), item("c")]

        let merged = PCOPlanDiff.merge(remote: remote, baseline: baseline, into: local, keeping: "b")

        XCTAssertEqual(merged.map(\.id), ["a", "mine", "b", "c"])
        XCTAssertEqual(PCOPlanDiff.merge(remote: remote, baseline: baseline, into: local, keeping: nil).map(\.id), ["a", "mine", "c"])
    }

    func testMergeAppliesRemoteOrderAroundLocalItems() {
        let baseline = [item("a"), item("b"), item("c")]
        let local = [item("a"), PCOTimerItem(id: "mine", title: "Local"), item("b"), item("c")]
        let remote = [item("c"), item("a"), item("b")]

        let merged = PCOPlanDiff.merge(remote: remote, baseline: baseline, into: local, keeping: nil)

        XCTAssertEqual(merged.map(\.id), ["c", "mine", "a", "b"])
    }

    func testMergeInsertsAddedItemsAfterTheirRemotePredecessor() {
        let baseline = [item("a"), item("b")]
        let remote = [item("new0"), item("a"), item("new1"), item("b"), item("new2")]

        let merged = PCOPlanDiff.merge(remote: remote, baseline: baseline, into: baseline, keeping: nil)

        XCTAssertEqual(merged.map(\.id), ["new0", "a", "new1", "b", "new2"])
    }

    func testMergeAppliesRemoteNoteRemovalAndIds() {
        let baseline = [item("a", notes: ["Lights": "dim", "Audio": "mic 1"])]
        var remoteA = item("a", notes: ["Audio": "mic 2"])
        remoteA.noteIds = ["Audio": "n2"]

        let merged = PCOPlanDiff.merge(remote: [remoteA], baseline: baseline, into: baseline, keeping: nil)

        XCTAssertEqual(merged[0].notes, ["Audio": "mic 2"])
        XCTAssertEqual(merged[0].noteIds["Audio"], "n2")
    }

    func testReorderSequenceKeepsItemsMissingLocally() {
        let sequence = PCOPlanDiff.reorderSequence(local: ["c", "a", "local"], baseline: ["a", "b", "c", "d"])
        XCTAssertEqual(sequence, ["c", "d", "a", "b"])
        XCTAssertEqual(PCOPlanDiff.reorderSequence(local: ["b", "a"], baseline: ["x", "a", "b"]), ["x", "b", "a"])
    }

    func testChangeSummariesReadAsEvents() {
        XCTAssertEqual(PCOPlanChange(kind: .added, title: "Baptism").summary, "Added “Baptism”")
        XCTAssertEqual(PCOPlanChange(kind: .length, title: "Sermon", detail: "30:00 to 35:00").summary, "“Sermon” length 30:00 to 35:00")
        XCTAssertEqual(PCOPendingChanges(revision: "r", serviceTypeId: "st", planId: "p", detectedAt: Date(), changes: [PCOPlanChange(kind: .reordered, title: "Run sheet")]).headline, "Planning Center has 1 change")
    }
}

@MainActor
final class PCOTwoWaySyncEngineTests: XCTestCase {
    private var remote: [PCOTimerItem] = []
    private var fetchCount = 0
    private var reorders: [[String]] = []

    override func setUp() {
        super.setUp()
        clearPersistedState()
        remote = []
        fetchCount = 0
        reorders = []
    }

    override func tearDown() {
        clearPersistedState()
        super.tearDown()
    }

    private func clearPersistedState() {
        for key in ["persistedFlow", "persistedRoles", "isPCOLiveSyncEnabled", "recentMessages", "waypoints", "serviceTags", "serviceSchedules"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func item(_ id: String, _ title: String? = nil, length: Int = 300, notes: [String: String] = [:]) -> PCOTimerItem {
        PCOTimerItem(id: id, title: title ?? "Item \(id)", lengthInSeconds: length, notes: notes, pcoServiceTypeId: "st", pcoPlanId: "p")
    }

    private func makeEngine(_ items: [PCOTimerItem]) -> CueEngine {
        let engine = CueEngine(startsNetworking: false)
        engine.isPCOConnected = true
        engine.importFlow(title: "Sunday", items: items)
        engine.beginPCOChangeTracking(planId: "p", items: items)
        engine.pcoChangeTracking.pollTask?.cancel()
        engine.pcoChangeTracking.pushDelay = 0
        engine.pcoChangeTracking.fetchRemote = { [unowned self] _, _ in
            self.fetchCount += 1
            return self.remote
        }
        engine.pcoChangeTracking.reorderRemote = { [unowned self] _, _, ids in
            self.reorders.append(ids)
        }
        remote = items
        return engine
    }

    private func settle(_ engine: CueEngine) async {
        for _ in 0..<200 where engine.isPCOWriteActive || !engine.pcoChangeTracking.writes.isEmpty {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testRemoteChangeRaisesAPromptOncePerRevision() async {
        let engine = makeEngine([item("a"), item("b")])
        await engine.checkPCOForChanges()
        XCTAssertNil(engine.pcoPendingChanges)

        remote = [item("a"), item("b", length: 600)]
        await engine.checkPCOForChanges()
        let first = engine.pcoPendingChanges
        XCTAssertEqual(first?.changes.map(\.kind), [.length])
        XCTAssertEqual(first?.planId, "p")

        await engine.checkPCOForChanges()
        XCTAssertEqual(engine.pcoPendingChanges?.detectedAt, first?.detectedAt)
    }

    func testDismissedRevisionIsNotOfferedAgain() async {
        let engine = makeEngine([item("a"), item("b")])
        remote = [item("a", "Welcome"), item("b")]
        await engine.checkPCOForChanges()
        let revision = engine.pcoPendingChanges?.revision

        XCTAssertFalse(engine.dismissPCOChanges(revision: "stale"))
        XCTAssertTrue(engine.dismissPCOChanges(revision: revision))
        XCTAssertNil(engine.pcoPendingChanges)
        XCTAssertEqual(engine.planItems.first?.title, "Item a")

        await engine.checkPCOForChanges()
        XCTAssertNil(engine.pcoPendingChanges)

        remote = [item("a", "Welcome"), item("b", length: 90)]
        await engine.checkPCOForChanges()
        XCTAssertEqual(engine.pcoPendingChanges?.changes.map(\.kind), [.length])
    }

    func testAcceptMergesWithoutLosingTheRunningActiveItem() async {
        let engine = makeEngine([item("a"), item("b"), item("c")])
        engine.setActivePlanItem(id: "b")
        XCTAssertEqual(engine.activeTimerItem?.isRunning, true)

        remote = [item("c"), item("new", "Baptism"), item("b", notes: ["Lights": "warm"]), item("a", "Welcome")]
        await engine.checkPCOForChanges()
        XCTAssertTrue(engine.acceptPCOChanges())

        XCTAssertNil(engine.pcoPendingChanges)
        XCTAssertEqual(engine.planItems.map(\.id), ["c", "new", "b", "a"])
        XCTAssertEqual(engine.planItems.map(\.sequence), [1, 2, 3, 4])
        XCTAssertEqual(engine.planItems.last?.title, "Welcome")
        XCTAssertEqual(engine.activeItemIndex, 2)
        XCTAssertEqual(engine.activeTimerItem?.id, "b")
        XCTAssertEqual(engine.activeTimerItem?.isRunning, true)
        XCTAssertEqual(engine.activeTimerItem?.lengthInSeconds, 300)
        XCTAssertEqual(engine.activeTimerItem?.notes["Lights"], "warm")
        XCTAssertEqual(engine.planItems[1].servicePlanTitle, "Sunday")

        await engine.checkPCOForChanges()
        XCTAssertNil(engine.pcoPendingChanges)
    }

    func testAcceptKeepsTheActiveItemWhenPCORemovedIt() async {
        let engine = makeEngine([item("a"), item("b"), item("c")])
        engine.setActivePlanItem(id: "b")
        remote = [item("a"), item("c")]
        await engine.checkPCOForChanges()
        XCTAssertEqual(engine.pcoPendingChanges?.changes.map(\.kind), [.removed])
        XCTAssertTrue(engine.acceptPCOChanges())
        XCTAssertEqual(engine.planItems.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(engine.activeTimerItem?.id, "b")
    }

    func testOwnReorderIsWrittenAndNotTreatedAsARemoteChange() async {
        let engine = makeEngine([item("a"), item("b"), item("c")])
        engine.movePlanItems(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        await settle(engine)

        XCTAssertEqual(reorders, [["c", "a", "b"]])
        remote = [item("c"), item("a"), item("b")]
        await engine.checkPCOForChanges()
        XCTAssertNil(engine.pcoPendingChanges)
    }

    func testReorderSkipsLocalOnlyItemsAndBatchesMoves() async {
        let engine = makeEngine([item("a"), item("b"), item("c")])
        engine.pcoChangeTracking.pushDelay = 0.05
        engine.addPlanItem(title: "Walk-in", itemType: "Item", lengthInSeconds: 60)
        engine.movePlanItems(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        engine.movePlanItems(fromOffsets: IndexSet(integer: 1), toOffset: 4)
        await settle(engine)

        XCTAssertEqual(reorders, [["b", "c", "a"]])
    }

    func testChecksWaitWhileWritesArePending() async {
        let engine = makeEngine([item("a"), item("b")])
        engine.pcoChangeTracking.pushDelay = 60
        engine.updatePlanItem(id: "a", title: "Item a", itemType: "Item", lengthInSeconds: 300, notes: ["Lights": "dim"])
        remote = [item("a", notes: ["Lights": "dim"]), item("b")]

        await engine.checkPCOForChanges()

        XCTAssertEqual(fetchCount, 0)
        XCTAssertNil(engine.pcoPendingChanges)
        engine.pcoChangeTracking.debounces.values.forEach { $0.cancel() }
    }

    func testOnlyChangedNoteCategoriesArePushed() {
        let engine = makeEngine([item("a", notes: ["Lights": "dim", "Audio": "mic 1", "Video": "wide"])])
        engine.pcoChangeTracking.pushDelay = 60
        engine.updatePlanItem(id: "a", title: "Item a", itemType: "Item", lengthInSeconds: 300, notes: ["Lights": "dim", "Audio": "mic 2"])

        let keys = Set(engine.pcoChangeTracking.debounces.keys)
        let separator = SyncHash.unitSeparator
        XCTAssertEqual(keys, ["note\(separator)a\(separator)Audio", "note\(separator)a\(separator)Video"])
        engine.pcoChangeTracking.debounces.values.forEach { $0.cancel() }
    }

    func testLoadingANonPCORunSheetClearsThePrompt() async {
        let engine = makeEngine([item("a")])
        remote = [item("a", "Renamed")]
        await engine.checkPCOForChanges()
        XCTAssertNotNil(engine.pendingPCOChangesForCurrentPlan)

        engine.importFlow(title: "Local", items: [PCOTimerItem(title: "Walk-in")])
        XCTAssertNil(engine.pendingPCOChangesForCurrentPlan)
        XCTAssertFalse(engine.acceptPCOChanges())
        await engine.checkPCOForChanges()
        XCTAssertNil(engine.pcoPendingChanges)
    }

    func testControlAPIExposesAcceptsAndDismisses() async {
        let engine = makeEngine([item("a"), item("b")])
        let router = ControlAPIRouter(engine: engine)
        remote = [item("a"), item("b", "Message")]
        await engine.checkPCOForChanges()
        let revision = try! XCTUnwrap(engine.pcoPendingChanges?.revision)

        let status = router.handle(HTTPRequest(method: "GET", path: "/v1/pco/changes", body: Data()))
        XCTAssertEqual(status.status, 200)
        let body = String(decoding: status.body, as: UTF8.self)
        XCTAssertTrue(body.contains(revision))
        XCTAssertTrue(body.contains("retitled"))

        let state = router.handle(HTTPRequest(method: "GET", path: "/v1/pco", body: Data()))
        XCTAssertTrue(String(decoding: state.body, as: UTF8.self).contains("pendingChanges"))

        let stale = router.handle(HTTPRequest(method: "POST", path: "/v1/pco/changes/accept", body: Data(#"{"revision":"nope"}"#.utf8)))
        XCTAssertEqual(stale.status, 409)
        XCTAssertNotNil(engine.pcoPendingChanges)

        let accepted = router.handle(HTTPRequest(method: "POST", path: "/v1/pco/changes/accept", body: Data(#"{"revision":"\#(revision)"}"#.utf8)))
        XCTAssertEqual(accepted.status, 200)
        XCTAssertEqual(engine.planItems.last?.title, "Message")

        let empty = router.handle(HTTPRequest(method: "GET", path: "/v1/pco/changes", body: Data()))
        XCTAssertEqual(String(decoding: empty.body, as: UTF8.self), #"{"pending":null}"#)
        XCTAssertEqual(router.handle(HTTPRequest(method: "POST", path: "/v1/pco/changes/dismiss", body: Data())).status, 409)
        XCTAssertEqual(router.handle(HTTPRequest(method: "POST", path: "/v1/pco/changes/check", body: Data())).status, 202)
        XCTAssertEqual(router.handle(HTTPRequest(method: "GET", path: "/v1/pco/changes/accept", body: Data())).status, 405)
    }
}

@MainActor
final class PCOTwoWaySyncMirrorTests: XCTestCase {
    private func state(pending: String) -> ControlAPIState {
        let json = RemoteFixtures.stateJSON(rev: 1)
            .replacingOccurrences(of: #""noteCategories":[]}"#, with: #""noteCategories":[],"pendingChanges":\#(pending)}"#)
        return try! ControlAPIJSON.decoder.decode(ControlAPIState.self, from: Data(json.utf8))
    }

    func testMirrorShowsThePromptAndForwardsTheAnswer() {
        let sink = RecordingCommands()
        let engine = CueEngine(mirroring: sink)
        engine.apply(remoteState: state(pending: #"{"revision":"r1","serviceTypeId":"st","planId":"p","detectedAt":"2026-10-18T13:55:02Z","changes":[{"kind":"added","title":"Baptism"}]}"#))

        XCTAssertEqual(engine.pcoPendingChanges?.revision, "r1")
        XCTAssertEqual(engine.pcoPendingChanges?.changes.first?.summary, "Added “Baptism”")

        engine.apply(remoteState: state(pending: "null"))
        XCTAssertNil(engine.pcoPendingChanges)
    }

    func testMirrorAcceptAndDismissSendCommands() {
        let sink = RecordingCommands()
        let engine = CueEngine(mirroring: sink)
        engine.pcoPendingChanges = PCOPendingChanges(revision: "r1", serviceTypeId: "st", planId: "p", detectedAt: Date(), changes: [])
        engine.planItems = [PCOTimerItem(id: "a", title: "A", pcoServiceTypeId: "st", pcoPlanId: "p")]

        XCTAssertTrue(engine.acceptPCOChanges())
        XCTAssertTrue(engine.dismissPCOChanges())
        XCTAssertEqual(sink.sent, [.pcoChangesAccept(revision: "r1"), .pcoChangesDismiss(revision: "r1")])
        XCTAssertEqual(RemoteCommand.pcoChangesAccept(revision: "r1").request.path, "/v1/pco/changes/accept")
        XCTAssertEqual(RemoteCommand.pcoChangesCheck.request.path, "/v1/pco/changes/check")
    }
}
