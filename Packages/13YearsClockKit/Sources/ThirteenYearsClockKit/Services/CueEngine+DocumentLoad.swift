// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

extension CueEngine {
    func loadDocument(_ body: ControlAPIRequests.DocumentLoadBody) {
        guard !isRemoteMirror else { return }

        var document = makeDocument()
        var keptRoles: [RoleCue]? = roles
        if let incoming = body.roles {
            if body.replaceRoles == true {
                document.roles = incoming
                keptRoles = nil
            } else {
                var merged = roles
                for role in incoming {
                    if let index = merged.firstIndex(where: { $0.id == role.id }) {
                        merged[index].name = role.name
                        merged[index].personName = role.personName
                        merged[index].assignedNoteCategories = role.assignedNoteCategories
                    } else if merged.count < ContentLimits.maxRoles {
                        var added = role
                        added.state = .off
                        merged.append(added)
                    }
                }
                document.roles = merged
                keptRoles = merged
            }
        }
        if let selected = body.selectedRoleIds { document.selectedRoleIds = selected }
        if let incoming = body.waypoints { document.waypoints = incoming }
        if let incoming = body.schedules { document.serviceSchedules = incoming }
        if let incoming = body.eventTimes {
            document.eventTimes = incoming
            document.liveEventTimeId = body.liveEventTimeId
        }
        if let raw = body.settings?.hourFormatThreshold, let threshold = HourFormatThreshold(rawValue: raw) {
            document.settings.hourFormatThreshold = threshold
        }

        let items = body.items

        applyConfiguration(of: document)
        if let keptRoles { roles = keptRoles }

        if let index = body.activeItemIndex {
            document.planItems = items
            document.activeItemIndex = index
            applyPlan(of: document)
            broadcastTimerUpdate()
        } else {
            importFlow(title: body.title, items: items)
            if body.eventTimes != nil {
                restoreEventTimes(document.eventTimes, liveId: document.liveEventTimeId)
            }
        }
    }
}
