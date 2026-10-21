// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

struct ActualRun: Equatable {
    var itemId: String
    var eventTimeId: String?
    var elapsedBase: Int
    var startedAt: Date?
}

public struct ActualLengthChange: Equatable, Sendable, Identifiable {
    public let itemId: String
    public let title: String
    public let plannedSeconds: Int
    public let actualSeconds: Int

    public var id: String { itemId }
}

extension CueEngine {
    var isLoggingActuals: Bool {
        !isRemoteMirror && isMasterServer && !isRehearsalMode && hasStartedPlan
    }

    func markPlanStarted() {
        guard !hasStartedPlan else { return }
        hasStartedPlan = true
        guard !isRemoteMirror, isMasterServer else { return }
        let active = activeTimerItem
        openActualRun(for: active)
        startActualRunIfRunning(active)
    }

    public var actualsEventTimeId: String? {
        liveEventTime?.id
    }

    public var activePlanTimeId: String? {
        if isRehearsalMode { return rehearsalPlanTimeId ?? liveEventTime?.pcoPlanTimeId }
        return liveEventTime?.pcoPlanTimeId
    }

    public var skipsKey: String {
        isRehearsalMode ? ItemActual.rehearsalKey : ItemActuals.skipsKey(eventTimeId: liveEventTime?.id)
    }

    func trackActuals(from old: PCOTimerItem?) {
        guard !isRemoteMirror, isMasterServer else { return }
        let new = activeTimerItem
        if old?.id != new?.id {
            closeActualRun(with: old)
            openActualRun(for: new)
        }
        startActualRunIfRunning(new)
    }

    func actualsContextDidChange() {
        guard !isRemoteMirror, isMasterServer else { return }
        let active = activeTimerItem
        if let run = actualRun {
            if isLoggingActuals, run.eventTimeId == actualsEventTimeId { return }
            closeActualRun(with: active)
        }
        if isLoggingActuals {
            openActualRun(for: active)
            startActualRunIfRunning(active)
        }
    }

    private func openActualRun(for item: PCOTimerItem?) {
        guard isLoggingActuals, let item, !item.isHeader else {
            actualRun = nil
            return
        }
        actualRun = ActualRun(itemId: item.id, eventTimeId: actualsEventTimeId, elapsedBase: item.elapsedSeconds, startedAt: nil)
    }

    private func startActualRunIfRunning(_ item: PCOTimerItem?) {
        guard var run = actualRun, run.startedAt == nil, let item, item.id == run.itemId, item.isRunning else { return }
        let now = timerClock()
        run.startedAt = now
        actualRun = run
        if !itemActuals.contains(where: { $0.itemId == run.itemId && $0.eventTimeId == run.eventTimeId }) {
            itemActuals.append(ItemActual(itemId: run.itemId, eventTimeId: run.eventTimeId, startedAt: now))
        }
    }

    private func closeActualRun(with old: PCOTimerItem?) {
        guard let run = actualRun else { return }
        actualRun = nil
        guard let old, old.id == run.itemId, run.startedAt != nil else { return }
        let runLength = max(0, old.elapsedSeconds - run.elapsedBase)
        guard let index = itemActuals.firstIndex(where: { $0.itemId == run.itemId && $0.eventTimeId == run.eventTimeId }) else { return }
        let total = (itemActuals[index].lengthSeconds ?? 0) + runLength
        if total == 0 {
            itemActuals.remove(at: index)
            return
        }
        var entry = itemActuals[index]
        entry.lengthSeconds = total
        if runLength > 0 || entry.endedAt == nil { entry.endedAt = timerClock() }
        itemActuals[index] = entry
    }

    func resetLiveOperations() {
        hasStartedPlan = false
        isRehearsalMode = false
        rehearsalPlanTimeId = nil
        actualRun = nil
        itemActuals = []
        skippedItemIds = [:]
    }

    func forgetLiveOperations(forItemId id: String) {
        if actualRun?.itemId == id { actualRun = nil }
        if itemActuals.contains(where: { $0.itemId == id }) {
            itemActuals.removeAll { $0.itemId == id }
        }
        if skippedItemIds.values.contains(where: { $0.contains(id) }) {
            skippedItemIds = skippedItemIds.compactMapValues { ids in
                let rest = ids.subtracting([id])
                return rest.isEmpty ? nil : rest
            }
        }
    }

    public func clearActuals() {
        if isRemoteMirror {
            remoteCommands?.send(.actualsClear)
            return
        }
        itemActuals = []
        if var run = actualRun {
            run.startedAt = nil
            run.elapsedBase = activeTimerItem?.elapsedSeconds ?? 0
            actualRun = run
            startActualRunIfRunning(activeTimerItem)
        }
    }

    public var itemActualsIncludingLive: [ItemActual] {
        var result = itemActuals
        guard !isRemoteMirror, let run = actualRun, run.startedAt != nil,
              let active = activeTimerItem, active.id == run.itemId,
              let index = result.firstIndex(where: { $0.itemId == run.itemId && $0.eventTimeId == run.eventTimeId }) else {
            return result
        }
        let runLength = max(0, active.elapsedSeconds - run.elapsedBase)
        result[index].lengthSeconds = (result[index].lengthSeconds ?? 0) + runLength
        result[index].endedAt = nil
        return result
    }

    public var currentItemActuals: [ItemActual] {
        guard !isRehearsalMode else { return [] }
        let key = actualsEventTimeId
        return itemActualsIncludingLive.filter { $0.eventTimeId == key }
    }

    public func actualLength(forItemId id: String) -> Int? {
        currentItemActuals.first { $0.itemId == id }?.lengthSeconds
    }

    func scheduleActuals() -> [String: RunSheetSchedule.Actual] {
        var result: [String: RunSheetSchedule.Actual] = [:]
        for actual in currentItemActuals {
            result[actual.itemId] = RunSheetSchedule.Actual(
                start: actual.startedAt,
                length: actual.lengthSeconds ?? 0,
                isComplete: actual.endedAt != nil
            )
        }
        return result
    }

    public func actualLengthChanges() -> [ActualLengthChange] {
        guard !isRehearsalMode, isPCOConnected else { return [] }
        let key = actualsEventTimeId
        let closed = Dictionary(
            itemActuals.filter { $0.eventTimeId == key && $0.endedAt != nil }.map { ($0.itemId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return planItems.compactMap { item in
            guard !item.isHeader, item.pcoServiceTypeId != nil, item.pcoPlanId != nil,
                  let actual = closed[item.id]?.lengthSeconds, actual > 0,
                  actual != item.lengthInSeconds,
                  TimerLimits.isValidLength(actual) else { return nil }
            return ActualLengthChange(itemId: item.id, title: item.title, plannedSeconds: item.lengthInSeconds, actualSeconds: actual)
        }
    }

    @discardableResult
    public func saveActualLengthsToPCO() -> Int {
        if isRemoteMirror {
            let count = actualLengthChanges().count
            if count > 0 { remoteCommands?.send(.actualsSaveToPCO) }
            return count
        }
        let changes = actualLengthChanges()
        guard !changes.isEmpty else { return 0 }
        ensurePCOBaseline()
        for change in changes {
            applyPlannedLength(change.actualSeconds, toItemId: change.itemId)
        }
        let ids = changes.map(\.itemId)
        schedulePCOPush(key: "actual-lengths") { engine in
            for id in ids { await engine.writeItemLengthToPCO(id: id) }
        }
        return changes.count
    }

    @discardableResult
    public func useActualAsPlannedLength(itemId: String) -> Bool {
        if isRemoteMirror {
            remoteCommands?.send(.itemUseActual(itemId: itemId))
            return true
        }
        guard let item = planItems.first(where: { $0.id == itemId }), !item.isHeader,
              let actual = actualLength(forItemId: itemId), actual > 0,
              TimerLimits.isValidLength(actual) else { return false }
        ensurePCOBaseline()
        applyPlannedLength(actual, toItemId: itemId)
        pushItemLengthToPCO(id: itemId)
        return true
    }

    private func applyPlannedLength(_ seconds: Int, toItemId id: String) {
        guard let index = planItems.firstIndex(where: { $0.id == id }) else { return }
        planItems[index].lengthInSeconds = seconds
        if activeTimerItem?.id == id {
            activeTimerItem?.lengthInSeconds = seconds
            broadcastTimerUpdate()
        }
    }

    public func isPCOExcluded(_ item: PCOTimerItem) -> Bool {
        !item.isHeader && (item.details?.isExcluded(fromPlanTimeId: activePlanTimeId) ?? false)
    }

    public func isItemSkipped(_ id: String) -> Bool {
        skippedItemIds[skipsKey]?.contains(id) ?? false
    }

    public func isOmittedFromNavigation(_ item: PCOTimerItem) -> Bool {
        !item.isHeader && (isItemSkipped(item.id) || isPCOExcluded(item))
    }

    public func setItemSkipped(id: String, skipped: Bool) {
        if isRemoteMirror {
            remoteCommands?.send(.itemSkip(itemId: id, skipped: skipped))
            return
        }
        guard let item = planItems.first(where: { $0.id == id }), !item.isHeader else { return }
        var ids = skippedItemIds[skipsKey] ?? []
        if skipped { ids.insert(id) } else { ids.remove(id) }
        var updated = skippedItemIds
        updated[skipsKey] = ids.isEmpty ? nil : ids
        skippedItemIds = updated
    }

    public var rehearsalPlanTimes: [PCOPlanTimeInfo] {
        pcoPlanContext?.times.filter { $0.timeType == "rehearsal" } ?? []
    }

    public var rehearsalLabel: String {
        if let id = rehearsalPlanTimeId, let time = rehearsalPlanTimes.first(where: { $0.id == id }) {
            if let name = time.name, !name.isEmpty { return "Rehearsal \u{00B7} \(name)" }
            if let start = time.startsAt { return "Rehearsal \u{00B7} \(clockFormat.string(from: start))" }
        }
        return "Rehearsal"
    }

    @discardableResult
    public func setRehearsalMode(_ enabled: Bool, planTimeId: String? = nil) -> Bool {
        if isRemoteMirror {
            remoteCommands?.send(.rehearsal(enabled: enabled, planTimeId: planTimeId))
            return true
        }
        if enabled {
            let times = rehearsalPlanTimes
            if let planTimeId, !times.contains(where: { $0.id == planTimeId }) { return false }
            rehearsalPlanTimeId = planTimeId ?? (isRehearsalMode ? rehearsalPlanTimeId : nil) ?? times.first?.id
            isRehearsalMode = true
        } else {
            guard isRehearsalMode else { return true }
            isRehearsalMode = false
            rehearsalPlanTimeId = nil
            if isPCOLiveSyncEnabled, let live = liveEventTime, let item = activeTimerItem {
                jumpPCOLive(toEventTime: live.id, itemId: item.id)
            }
        }
        return true
    }
}
