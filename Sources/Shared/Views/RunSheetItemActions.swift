// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

struct RunSheetItemActions: View {
    @EnvironmentObject var engine: CueEngine
    let item: PCOTimerItem
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onNewWaypoint: () -> Void

    var body: some View {
        Button(action: onEdit) {
            Label("Edit\u{2026}", systemImage: "pencil")
        }
        .tint(.blue)

        if !item.isHeader {
            Button {
                engine.setActivePlanItem(id: item.id)
            } label: {
                Label("Go to This Item", systemImage: "play.fill")
            }
            .tint(.green)

            Button {
                engine.setDurationIsActual(id: item.id, isActual: !item.isDurationActual)
            } label: {
                Label(item.isDurationActual ? "Mark Duration Projected" : "Mark Duration Actual",
                      systemImage: "clock.arrow.circlepath")
            }

            Menu {
                RunSheetWaypointMenuItems(item: item, onNewWaypoint: onNewWaypoint)
            } label: {
                Label("Assign Waypoints\u{2026}", systemImage: Waypoint.symbolName)
            }

            if !engine.isPCOExcluded(item) {
                let skipped = engine.isItemSkipped(item.id)
                Button {
                    engine.setItemSkipped(id: item.id, skipped: !skipped)
                } label: {
                    Label(skipped ? "Unskip" : "Skip in \(engine.liveEventTimeLabel ?? "This Event")",
                          systemImage: skipped ? "arrow.uturn.backward" : "forward.end")
                }
            }

            if let actual = engine.actualLength(forItemId: item.id), actual > 0 {
                Button {
                    engine.useActualAsPlannedLength(itemId: item.id)
                } label: {
                    Label("Use Actual as Planned Length", systemImage: "stopwatch")
                }
                .help(item.pcoPlanId != nil
                    ? "Sets this item's length to the recorded actual and updates it in Planning Center for every event time"
                    : "Sets this item's length to the recorded actual")
            }
        }

        Button(role: .destructive, action: onDelete) {
            Label("Delete\u{2026}", systemImage: "trash")
        }
    }
}

struct RunSheetWaypointMenuItems: View {
    @EnvironmentObject var engine: CueEngine
    let item: PCOTimerItem
    let onNewWaypoint: () -> Void

    var body: some View {
        ForEach(engine.waypoints) { waypoint in
            let currentItemId = engine.itemId(forWaypointId: waypoint.id)
            let isOnThisItem = currentItemId == item.id
            Button {
                engine.assignWaypoint(waypoint.id, toItemId: isOnThisItem ? nil : item.id)
            } label: {
                if isOnThisItem {
                    Label(waypoint.name, systemImage: "checkmark")
                } else if let currentItemId,
                          let currentTitle = engine.planItems.first(where: { $0.id == currentItemId })?.title {
                    Text("\(waypoint.name) \u{2014} on \u{201C}\(currentTitle)\u{201D}")
                } else {
                    Text(waypoint.name)
                }
            }
        }

        if !engine.waypoints.isEmpty {
            Divider()
        }

        Button(action: onNewWaypoint) {
            Label("New Waypoint\u{2026}", systemImage: "plus")
        }
    }
}
