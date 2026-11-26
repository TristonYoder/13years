// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

extension CueEngine {
    /// Whether the loaded plan is synced from a Planning Center plan.
    public var isLinkedToPCOPlan: Bool { currentPCOPlanId != nil }

    /// Cuts the link to Planning Center so the plan runs entirely in 13 Years. Items, notes, waypoints, the event
    /// times and the rehearsal times stay, now as ones you edit here; what stops is syncing, change polling, Live
    /// control, saving actual lengths back, and Planning Center owning the event and rehearsal times. Sync a plan
    /// again to link a new one.
    public func unlinkPCOPlan() {
        if isRemoteMirror {
            remoteCommands?.send(.pcoUnlink)
            return
        }
        guard currentPCOPlanId != nil else { return }
        disablePCOLiveSync()

        // The times Planning Center owned become ours, keeping their ids so the live event and any rehearsal in progress carry on.
        let rehearsals = rehearsalPlanTimes.map { time in
            EventTime(
                id: time.id,
                name: time.name,
                day: time.startsAt.map { EventDay(date: $0) },
                startTime: time.startsAt.map { TimeOfDay(date: $0) }
            )
        }
        eventTimes = eventTimes.map { time in
            var local = time
            local.pcoPlanTimeId = nil
            return local
        }
        manualRehearsalTimes = EventTime.sorted(rehearsals)

        for index in planItems.indices {
            planItems[index].pcoPlanId = nil
            planItems[index].pcoServiceTypeId = nil
            planItems[index].noteIds = [:]
        }
        activeTimerItem?.pcoPlanId = nil
        activeTimerItem?.pcoServiceTypeId = nil
        activeTimerItem?.noteIds = [:]

        pcoChangeTracking.pollTask?.cancel()
        pcoChangeTracking.pollTask = nil
        pcoChangeTracking.baseline = []
        pcoChangeTracking.baselinePlanId = nil
        pcoChangeTracking.pendingRemote = []
        if pcoPendingChanges != nil { pcoPendingChanges = nil }
        pcoPlanContext = nil
        pcoReferenceCache.removeAll()
        broadcastTimerUpdate()
    }
}
