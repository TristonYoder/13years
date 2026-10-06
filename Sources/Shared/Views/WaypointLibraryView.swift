// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct WaypointLibraryView: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss

    @State private var newWaypointName: String = ""
    @State private var renamingWaypointId: String?
    @State private var renameText: String = ""
    @State private var pendingDeleteWaypoint: Waypoint?

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                waypointsSection
            }
            .formStyle(.grouped)
            .navigationTitle("Waypoints")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename Waypoint", isPresented: Binding(
                get: { renamingWaypointId != nil },
                set: { if !$0 { renamingWaypointId = nil } }
            )) {
                TextField("Waypoint Name", text: $renameText)
                Button("Cancel", role: .cancel) { renamingWaypointId = nil }
                Button("Save") {
                    if let id = renamingWaypointId, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                        engine.renameWaypoint(id: id, name: renameText.trimmingCharacters(in: .whitespaces))
                    }
                    renamingWaypointId = nil
                }
            }
            .confirmationDialog(
                "Delete this waypoint?",
                isPresented: Binding(
                    get: { pendingDeleteWaypoint != nil },
                    set: { if !$0 { pendingDeleteWaypoint = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeleteWaypoint
            ) { waypoint in
                Button("Delete", role: .destructive) {
                    engine.removeWaypoint(id: waypoint.id)
                    pendingDeleteWaypoint = nil
                }
                Button("Cancel", role: .cancel) { pendingDeleteWaypoint = nil }
            } message: { waypoint in
                Text("\u{201C}\(waypoint.name)\u{201D} will be unassigned from this week's flow, and any Companion or Stream Deck button that fires \u{201C}\(waypoint.slug)\u{201D} will stop finding an item.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 420, idealHeight: 520)
        #endif
    }

    private var waypointsSection: some View {
        Section {
            if engine.waypoints.isEmpty {
                Text("No waypoints yet — add one below, e.g. \u{201C}Song 1\u{201D}, then assign it to this week's item from Service Flow.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(engine.waypoints) { waypoint in
                waypointRow(waypoint)
            }

            HStack {
                TextField("New Waypoint Name", text: $newWaypointName)
                Button("Add") {
                    let trimmed = newWaypointName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    engine.addWaypoint(name: trimmed)
                    newWaypointName = ""
                }
                .disabled(newWaypointName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Waypoints")
        } footer: {
            Text("A waypoint is a reusable handle like \u{201C}Song 1\u{201D} — assign it to whichever item plays that slot this week from Service Flow. The monospaced text under each name is its slug: what a Stream Deck or Companion button actually types to fire it.")
        }
    }

    private func waypointRow(_ waypoint: Waypoint) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Image(systemName: Waypoint.symbolName)
                        .foregroundStyle(.secondary)
                    Text(waypoint.name)
                    Text(waypoint.slug)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(assignmentDescription(for: waypoint))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            #if os(macOS)
            RowActionButton(systemImage: "pencil", label: "Rename waypoint\u{2026}") {
                renameText = waypoint.name
                renamingWaypointId = waypoint.id
            }
            RowActionButton(systemImage: "trash", label: "Delete waypoint\u{2026}") {
                pendingDeleteWaypoint = waypoint
            }
            #endif
        }
        .rowActions {
            Button {
                renameText = waypoint.name
                renamingWaypointId = waypoint.id
            } label: {
                Label("Rename\u{2026}", systemImage: "pencil")
            }
            .tint(.blue)

            Button(role: .destructive) {
                pendingDeleteWaypoint = waypoint
            } label: {
                Label("Delete\u{2026}", systemImage: "trash")
            }
        }
    }

    private func assignmentDescription(for waypoint: Waypoint) -> String {
        guard let itemId = engine.itemId(forWaypointId: waypoint.id),
              let item = engine.planItems.first(where: { $0.id == itemId }) else {
            return "Not assigned"
        }
        return "On \u{201C}\(item.title)\u{201D}"
    }
}
