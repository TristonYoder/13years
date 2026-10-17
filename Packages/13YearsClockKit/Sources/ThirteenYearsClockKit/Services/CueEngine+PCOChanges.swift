// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

struct PCOChangeTracking {
    var baseline: [PCOTimerItem] = []
    var baselinePlanId: String?
    var pendingRemote: [PCOTimerItem] = []
    var writeGeneration = 0
    var writesInFlight = 0
    var debounces: [String: Task<Void, Never>] = [:]
    var writes: [String: Task<Void, Never>] = [:]
    var pollTask: Task<Void, Never>?
    var pollInterval: TimeInterval = 30
    var pushDelay: TimeInterval = 0.8
    var fetchRemote: (@MainActor (_ serviceTypeId: String, _ planId: String) async throws -> [PCOTimerItem])?
    var reorderRemote: (@MainActor (_ serviceTypeId: String, _ planId: String, _ itemIds: [String]) async throws -> Void)?
    var fetchContext: (@MainActor (_ serviceTypeId: String, _ planId: String) async throws -> PCOPlanContext)?
    var contextRefreshInterval: TimeInterval = 120
}

extension CueEngine {
    public var pendingPCOChangesForCurrentPlan: PCOPendingChanges? {
        guard let pending = pcoPendingChanges, pending.planId == currentPCOPlanId else { return nil }
        return pending
    }

    public func checkPCOForChanges() async {
        if isRemoteMirror {
            remoteCommands?.send(.pcoChangesCheck)
            return
        }
        guard isPCOConnected, let serviceTypeId = currentPCOServiceTypeId, let planId = currentPCOPlanId else {
            clearPCOChangeTracking()
            return
        }
        ensurePCOBaseline()
        guard !isPCOWriteActive else { return }
        let generation = pcoChangeTracking.writeGeneration
        let remote: [PCOTimerItem]
        do {
            if let fetchRemote = pcoChangeTracking.fetchRemote {
                remote = try await fetchRemote(serviceTypeId, planId)
            } else {
                remote = try await pcoClient.fetchPlanItems(serviceTypeId: serviceTypeId, planId: planId).items
            }
        } catch {
            AppLog.cue.error("CueEngine: PCO change check failed: \(error.localizedDescription, privacy: .private)")
            return
        }
        guard generation == pcoChangeTracking.writeGeneration, !isPCOWriteActive,
              currentPCOPlanId == planId, pcoChangeTracking.baselinePlanId == planId else { return }
        receivePCOSnapshot(remote, serviceTypeId: serviceTypeId, planId: planId)
        if let fetchedAt = pcoPlanContext?.fetchedAt, pcoPlanContext?.planId == planId,
           Date().timeIntervalSince(fetchedAt) < pcoChangeTracking.contextRefreshInterval { return }
        await refreshPCOPlanContext(serviceTypeId: serviceTypeId, planId: planId)
    }

    func refreshPCOPlanContext(serviceTypeId: String, planId: String) async {
        guard !isRemoteMirror else { return }
        let context: PCOPlanContext
        do {
            if let fetchContext = pcoChangeTracking.fetchContext {
                context = try await fetchContext(serviceTypeId, planId)
            } else {
                context = try await pcoClient.fetchPlanContext(serviceTypeId: serviceTypeId, planId: planId)
            }
        } catch {
            AppLog.cue.error("CueEngine: PCO plan context refresh failed: \(error.localizedDescription, privacy: .private)")
            return
        }
        guard currentPCOPlanId == planId else { return }
        pcoPlanContext = context
    }

    @discardableResult
    public func acceptPCOChanges(revision: String? = nil) -> Bool {
        if isRemoteMirror {
            guard let pending = pendingPCOChangesForCurrentPlan else { return false }
            remoteCommands?.send(.pcoChangesAccept(revision: revision ?? pending.revision))
            return true
        }
        guard let pending = pendingPCOChangesForCurrentPlan, revision == nil || revision == pending.revision else { return false }
        let remote = pcoChangeTracking.pendingRemote
        let baseline = pcoChangeTracking.baseline
        let activeId = activeTimerItem?.id
        let planTitle = planItems.first?.servicePlanTitle

        var merged = PCOPlanDiff.merge(remote: remote, baseline: baseline, into: planItems, keeping: activeId)
        for index in merged.indices {
            merged[index].sequence = index + 1
            if merged[index].servicePlanTitle == nil { merged[index].servicePlanTitle = planTitle }
            if merged[index].id != activeId { merged[index].isRunning = false }
        }
        planItems = merged

        if let activeId, let newIndex = merged.firstIndex(where: { $0.id == activeId }) {
            activeItemIndex = newIndex
            if var active = activeTimerItem {
                if let theirs = remote.first(where: { $0.id == activeId }) {
                    active = PCOPlanDiff.applying(theirs, over: baseline.first { $0.id == activeId }, to: active)
                }
                active.sequence = newIndex + 1
                activeTimerItem = active
            }
        } else if merged.isEmpty {
            activeItemIndex = 0
            activeTimerItem = nil
        }

        pcoChangeTracking.baseline = remote
        pcoChangeTracking.pendingRemote = []
        pcoPendingChanges = nil
        AppLog.cue.info("CueEngine: merged \(pending.changes.count) Planning Center change(s)")
        broadcastTimerUpdate()
        return true
    }

    @discardableResult
    public func dismissPCOChanges(revision: String? = nil) -> Bool {
        if isRemoteMirror {
            guard let pending = pendingPCOChangesForCurrentPlan else { return false }
            remoteCommands?.send(.pcoChangesDismiss(revision: revision ?? pending.revision))
            return true
        }
        guard let pending = pendingPCOChangesForCurrentPlan, revision == nil || revision == pending.revision else { return false }
        pcoChangeTracking.baseline = pcoChangeTracking.pendingRemote
        pcoChangeTracking.pendingRemote = []
        pcoPendingChanges = nil
        return true
    }

    public func pushItemLengthToPCO(id: String) {
        guard !isRemoteMirror,
              let item = planItems.first(where: { $0.id == id }),
              item.pcoServiceTypeId != nil, item.pcoPlanId != nil else { return }
        schedulePCOPush(key: "length\(SyncHash.unitSeparator)\(id)") { engine in
            await engine.writeItemLengthToPCO(id: id)
        }
    }

    public func pushItemNoteToPCO(id: String, category: String) {
        guard !isRemoteMirror,
              let item = planItems.first(where: { $0.id == id }),
              item.pcoServiceTypeId != nil, item.pcoPlanId != nil else { return }
        schedulePCOPush(key: "note\(SyncHash.unitSeparator)\(id)\(SyncHash.unitSeparator)\(category)") { engine in
            await engine.writeItemNoteToPCO(id: id, category: category)
        }
    }

    public func pushPlanOrderToPCO() {
        guard !isRemoteMirror, let serviceTypeId = currentPCOServiceTypeId, let planId = currentPCOPlanId else { return }
        schedulePCOPush(key: "order") { engine in
            await engine.writePlanOrderToPCO(serviceTypeId: serviceTypeId, planId: planId)
        }
    }

    func beginPCOChangeTracking(planId: String, items: [PCOTimerItem]) {
        pcoChangeTracking.baseline = items
        pcoChangeTracking.baselinePlanId = planId
        pcoChangeTracking.pendingRemote = []
        if pcoPendingChanges != nil { pcoPendingChanges = nil }
        startPCOChangePolling()
    }

    func ensurePCOBaseline() {
        guard !isRemoteMirror, let planId = currentPCOPlanId, pcoChangeTracking.baselinePlanId != planId else { return }
        pcoChangeTracking.baseline = planItems.filter { $0.pcoPlanId == planId }
        pcoChangeTracking.baselinePlanId = planId
        pcoChangeTracking.pendingRemote = []
        if pcoPendingChanges != nil { pcoPendingChanges = nil }
    }

    func startPCOChangePolling() {
        guard !isRemoteMirror, pcoChangeTracking.pollTask == nil else { return }
        pcoChangeTracking.pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.pcoChangeTracking.pollInterval ?? 30
                try? await Task.sleep(nanoseconds: UInt64(max(interval, 1) * 1_000_000_000))
                guard !Task.isCancelled, let engine = self else { return }
                await engine.checkPCOForChanges()
            }
        }
    }

    func applyRemotePCODetails(_ remote: [PCOTimerItem]) {
        var activeChanged = false
        for item in remote {
            guard let baselineIndex = pcoChangeTracking.baseline.firstIndex(where: { $0.id == item.id }),
                  pcoChangeTracking.baseline[baselineIndex].details != item.details else { continue }
            pcoChangeTracking.baseline[baselineIndex].details = item.details
            if let index = planItems.firstIndex(where: { $0.id == item.id }) {
                planItems[index].details = item.details
            }
            if activeTimerItem?.id == item.id {
                activeChanged = activeChanged || activeTimerItem?.details?.broadcastTrimmed != item.details?.broadcastTrimmed
                activeTimerItem?.details = item.details
            }
        }
        if activeChanged { broadcastTimerUpdate() }
    }

    func receivePCOSnapshot(_ remote: [PCOTimerItem], serviceTypeId: String, planId: String) {
        applyRemotePCODetails(remote)
        let changes = PCOPlanDiff.changes(from: pcoChangeTracking.baseline, to: remote)
        guard !changes.isEmpty else {
            pcoChangeTracking.pendingRemote = []
            if pcoPendingChanges != nil { pcoPendingChanges = nil }
            return
        }
        let revision = PCOPlanDiff.revision(of: remote)
        guard pcoPendingChanges?.revision != revision else { return }
        pcoChangeTracking.pendingRemote = remote
        pcoPendingChanges = PCOPendingChanges(
            revision: revision,
            serviceTypeId: serviceTypeId,
            planId: planId,
            detectedAt: Date(),
            changes: changes
        )
    }

    var isPCOWriteActive: Bool {
        pcoChangeTracking.writesInFlight > 0 || !pcoChangeTracking.debounces.isEmpty
    }

    private func clearPCOChangeTracking() {
        guard pcoChangeTracking.baselinePlanId != nil || pcoPendingChanges != nil else { return }
        pcoChangeTracking.baseline = []
        pcoChangeTracking.baselinePlanId = nil
        pcoChangeTracking.pendingRemote = []
        pcoPendingChanges = nil
    }

    private func schedulePCOPush(key: String, _ work: @escaping @MainActor (CueEngine) async -> Void) {
        ensurePCOBaseline()
        pcoChangeTracking.debounces[key]?.cancel()
        pcoChangeTracking.writeGeneration += 1
        let delay = pcoChangeTracking.pushDelay
        pcoChangeTracking.debounces[key] = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled, let engine = self else { return }
            engine.pcoChangeTracking.debounces[key] = nil
            let previous = engine.pcoChangeTracking.writes[key]
            engine.pcoChangeTracking.writesInFlight += 1
            engine.pcoChangeTracking.writeGeneration += 1
            let write = Task { @MainActor in
                await previous?.value
                await work(engine)
                engine.pcoChangeTracking.writesInFlight -= 1
                engine.pcoChangeTracking.writeGeneration += 1
            }
            engine.pcoChangeTracking.writes[key] = write
            await write.value
            if engine.pcoChangeTracking.writes[key] == write {
                engine.pcoChangeTracking.writes[key] = nil
            }
        }
    }

    private func recordPCOWrite(itemId: String, _ update: (inout PCOTimerItem) -> Void) {
        guard let index = pcoChangeTracking.baseline.firstIndex(where: { $0.id == itemId }) else { return }
        update(&pcoChangeTracking.baseline[index])
    }

    private func writeItemLengthToPCO(id: String) async {
        guard let item = planItems.first(where: { $0.id == id }),
              let serviceTypeId = item.pcoServiceTypeId,
              let planId = item.pcoPlanId else { return }
        let length = item.lengthInSeconds
        do {
            try await pcoClient.updateItemLength(serviceTypeId: serviceTypeId, planId: planId, itemId: id, lengthInSeconds: length)
            recordPCOWrite(itemId: id) { $0.lengthInSeconds = length }
            pcoLastError = nil
        } catch {
            pcoLastError = error.localizedDescription
        }
    }

    private func writeItemNoteToPCO(id: String, category: String) async {
        guard let item = planItems.first(where: { $0.id == id }),
              let serviceTypeId = item.pcoServiceTypeId,
              let planId = item.pcoPlanId else { return }
        let content = item.notes[category] ?? ""
        do {
            if let noteId = item.noteIds[category] {
                try await pcoClient.updateItemNoteContent(serviceTypeId: serviceTypeId, planId: planId, itemId: id, noteId: noteId, content: content)
                recordPCOWrite(itemId: id) { $0.notes[category] = content }
            } else {
                guard !content.isEmpty, let categoryId = pcoNoteCategories.first(where: { $0.name == category })?.id else { return }
                let noteId = try await pcoClient.createItemNote(serviceTypeId: serviceTypeId, planId: planId, itemId: id, categoryId: categoryId, content: content)
                if let index = planItems.firstIndex(where: { $0.id == id }) {
                    planItems[index].noteIds[category] = noteId
                }
                if activeTimerItem?.id == id {
                    activeTimerItem?.noteIds[category] = noteId
                }
                recordPCOWrite(itemId: id) {
                    $0.notes[category] = content
                    $0.noteIds[category] = noteId
                }
            }
            pcoLastError = nil
        } catch {
            pcoLastError = error.localizedDescription
        }
    }

    private func writePlanOrderToPCO(serviceTypeId: String, planId: String) async {
        guard pcoChangeTracking.baselinePlanId == planId else { return }
        let baselineIds = pcoChangeTracking.baseline.map(\.id)
        let localIds = planItems.filter { $0.pcoPlanId == planId }.map(\.id)
        let sequence = PCOPlanDiff.reorderSequence(local: localIds, baseline: baselineIds)
        guard sequence != baselineIds else { return }
        do {
            if let reorderRemote = pcoChangeTracking.reorderRemote {
                try await reorderRemote(serviceTypeId, planId, sequence)
            } else {
                try await pcoClient.reorderItems(serviceTypeId: serviceTypeId, planId: planId, itemIds: sequence)
            }
            guard pcoChangeTracking.baselinePlanId == planId else { return }
            let byId = Dictionary(pcoChangeTracking.baseline.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            pcoChangeTracking.baseline = sequence.compactMap { byId[$0] }
            pcoLastError = nil
        } catch {
            pcoLastError = error.localizedDescription
        }
    }
}
