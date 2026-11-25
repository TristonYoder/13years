// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

extension CueEngine {
    public func cueRoles(for item: PCOTimerItem) -> [RoleCue] {
        item.cueRoleIds.compactMap { id in roles.first { $0.id == id } }
    }

    public func hasCueRoles(_ item: PCOTimerItem) -> Bool {
        !item.isHeader && !cueRoles(for: item).isEmpty
    }

    public func setItemCueRoles(id: String, _ roleIds: [String]) {
        guard !isRemoteMirror, let index = planItems.firstIndex(where: { $0.id == id }) else { return }
        let known = Set(roles.map(\.id))
        var seen = Set<String>()
        let cleaned = roleIds.filter { known.contains($0) && seen.insert($0).inserted }
        guard planItems[index].cueRoleIds != cleaned else { return }
        planItems[index].cueRoleIds = cleaned
        if activeTimerItem?.id == id { activeTimerItem?.cueRoleIds = cleaned }
    }

    public func standbyItem(id: String) {
        guard let item = planItems.first(where: { $0.id == id }) else { return }
        setCue(.standby, forRoleIds: cueRoles(for: item).map(\.id))
    }

    public func goItem(id: String) {
        guard let item = planItems.first(where: { $0.id == id }) else { return }
        let targets = cueRoles(for: item).map(\.id)
        if activeTimerItem?.id == id {
            if activeTimerItem?.isRunning == false {
                activeTimerItem?.isRunning = true
                if !isRemoteMirror { broadcastTimerUpdate() }
            }
        } else {
            setActivePlanItem(id: id)
        }
        setCue(.go, forRoleIds: targets)
    }

    func setCue(_ state: CueState, forRoleIds ids: [String]) {
        guard !ids.isEmpty else { return }
        if isRemoteMirror {
            for id in ids { remoteCommands?.send(.cueRole(id: id, state: state)) }
            return
        }
        let now = Date()
        for index in roles.indices where ids.contains(roles[index].id) {
            roles[index].state = state
            roles[index].lastUpdated = now
        }
        broadcastState()
    }
}
