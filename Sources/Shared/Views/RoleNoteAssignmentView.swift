// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct RoleNoteAssignmentView: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss
    let categories: [String]

    @State private var renamingRoleId: String?
    @State private var renameText: String = ""
    @State private var pendingDeleteRole: RoleCue?

    public init(categories: [String]) {
        self.categories = categories
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Roles & Pager Fields")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .alert("Rename Role", isPresented: Binding(
                    get: { renamingRoleId != nil },
                    set: { if !$0 { renamingRoleId = nil } }
                )) {
                    TextField("Role Name", text: $renameText)
                    Button("Cancel", role: .cancel) { renamingRoleId = nil }
                    Button("Save") {
                        if let id = renamingRoleId, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                            engine.renameRole(id: id, name: renameText.trimmingCharacters(in: .whitespaces))
                        }
                        renamingRoleId = nil
                    }
                }
                .confirmationDialog(
                    "Delete this role?",
                    isPresented: Binding(
                        get: { pendingDeleteRole != nil },
                        set: { if !$0 { pendingDeleteRole = nil } }
                    ),
                    titleVisibility: .visible,
                    presenting: pendingDeleteRole
                ) { role in
                    Button("Delete", role: .destructive) {
                        engine.removeRole(id: role.id)
                        pendingDeleteRole = nil
                    }
                    Button("Cancel", role: .cancel) { pendingDeleteRole = nil }
                } message: { role in
                    Text("\u{201C}\(role.name)\u{201D} and its pager fields and notes will be removed. You can add it back at any time.")
                }
        }
        #if os(macOS)
        .frame(minWidth: 860, idealWidth: 960, minHeight: 560, idealHeight: 680)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS) || os(iOS)
        RolePagerEditorContent(
            categories: categories,
            onRename: { role in
                renameText = role.name
                renamingRoleId = role.id
            },
            onDelete: { pendingDeleteRole = $0 }
        )
        #else
        Text("Edit roles on the Producer.")
            .foregroundStyle(.secondary)
        #endif
    }
}
