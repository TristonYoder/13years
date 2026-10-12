// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

extension CueEngine {
    public func apply(remoteState state: ControlAPIState) {
        guard isRemoteMirror else { return }

        assign(\.roles, state.roles)
        assign(\.selectedRoleIds, Set(state.selectedRoleIds))
        assign(\.waypoints, state.waypoints.map { Waypoint(id: $0.id, name: $0.name) })
        assign(\.serviceSchedules, state.schedules.entries.map { entry in
            ServiceSchedule(
                id: entry.id,
                title: entry.title,
                startsAt: entry.startsAt,
                goLiveOffsetSeconds: entry.goLiveOffsetSeconds,
                pcoServiceTypeId: entry.pcoServiceTypeId,
                pcoPlanId: entry.pcoPlanId,
                recurrence: ServiceSchedule.Recurrence(rawValue: entry.recurrence) ?? .once,
                isEnabled: entry.isEnabled,
                lastFiredAt: entry.lastFiredAt
            )
        })
        assign(\.planItems, state.plan.items)
        assign(\.activeItemIndex, state.plan.activeItemIndex)
        apply(remoteTimer: state.timer)
        assign(\.recentMessages, state.messages)
        assign(\.notificationsClearedAt, state.notificationsClearedAt)
        assign(\.hourFormatThreshold, HourFormatThreshold(rawValue: state.settings.hourFormatThreshold) ?? hourFormatThreshold)
        assign(\.isPCOConnected, state.pco.isConnected)
        assign(\.pcoUserName, state.pco.userName)
        assign(\.pcoLastError, state.pco.lastError)
        assign(\.isPCOLiveSyncEnabled, state.pco.isLiveSyncEnabled)
        assign(\.pcoSelectedServiceTypeId, state.pco.selectedServiceTypeId)
        assign(\.pcoDefaultServiceTypeId, state.pco.defaultServiceTypeId)
        assign(\.pcoPlanFilter, PCOClient.PCOPlanFilter(rawValue: state.pco.planFilter) ?? pcoPlanFilter)
        assign(\.pcoServiceTypes, state.pco.serviceTypes.map { PCOClient.PCOServiceType(id: $0.id, name: $0.name) })
        assign(\.pcoPlans, state.pco.plans.map { PCOClient.PCOPlanInfo(id: $0.id, title: $0.title, dates: $0.dates) })
        assign(\.pcoNoteCategories, state.pco.noteCategories.map { PCOClient.PCONoteCategory(id: $0.id, name: $0.name) })
        assign(\.remoteControllerCount, state.settings.connectedAPIClients)
    }

    public func apply(remoteTimer timer: ControlAPIState.ActiveTimer?) {
        guard isRemoteMirror else { return }
        if let timer {
            var item = timer.item
            if nextItem != timer.nextItem { nextItem = timer.nextItem }
            item.isRunning = timer.isRunning
            assign(\.isActiveTimerActualOverride, timer.isDurationActualForDisplay)
            if actualOverrideItemId != item.id { actualOverrideItemId = item.id }
            if let anchor = timer.anchor, anchor.itemId == item.id {
                syncV2.held = HeldAnchor(anchor: anchor, item: item)
                if syncedProducerNowMs != nil {
                    refreshHeldTimer()
                } else {
                    assign(\.activeTimerItem, item)
                }
                armDisplayTick()
            } else {
                syncV2.held = nil
                cancelDisplayTick()
                assign(\.activeTimerItem, item)
            }
        } else {
            syncV2.held = nil
            cancelDisplayTick()
            assign(\.activeTimerItem, nil)
            if nextItem != nil { nextItem = nil }
            actualOverrideItemId = nil
        }
    }

    public func mirrorHashes() -> SyncHash.Hashes {
        SyncHash.Hashes(
            roles: SyncHash.roles(roles),
            timer: SyncHash.timer(syncV2.held?.anchor),
            plan: SyncHash.plan(items: planItems, activeItemIndex: activeItemIndex),
            messages: SyncHash.messages(recentMessages)
        )
    }

    private func assign<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<CueEngine, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}
