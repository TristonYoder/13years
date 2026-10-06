// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct RoleNoteAssignmentView: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss
    let categories: [String]

    @State private var newRoleName: String = ""
    @State private var renamingRoleId: String?
    @State private var renameText: String = ""
    @State private var pendingDeleteRole: RoleCue?

    public init(categories: [String]) {
        self.categories = categories
    }

    public var body: some View {
        NavigationStack {
            Form {
                rolesSection

                ForEach(engine.roles) { role in
                    noteCategorySection(for: role)
                }

                if categories.isEmpty {
                    Section {
                        Text("No note categories yet — sync from Planning Center or add a note to any item in Service Flow.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !engine.plotipharRoles.isEmpty {
                    Section {
                        ForEach(engine.roles) { role in
                            Picker(role.name, selection: Binding(
                                get: { role.plotipharRoleId ?? "" },
                                set: { engine.setPlotipharRoleId(forRoleId: role.id, plotipharRoleId: $0.isEmpty ? nil : $0) }
                            )) {
                                Text("Not linked").tag("")
                                ForEach(engine.plotipharRoles, id: \.id) { plotipharRole in
                                    Text(plotipharRole.name).tag(plotipharRole.id)
                                }
                            }
                        }
                    } header: {
                        Text("Plotiphar Role")
                    } footer: {
                        Text("Links this role to Plotiphar's own role library — once linked, that role's assigned person syncs in automatically whenever a matching plan is loaded.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Roles & Notes")
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
                Text("\u{201C}\(role.name)\u{201D} and its note-category assignments will be removed. You can add it back at any time.")
            }
        }
    }

    private var rolesSection: some View {
        Section {
            ForEach(engine.roles) { role in
                HStack {
                    Text(role.name)
                    Spacer()
                    #if os(macOS)
                    RowActionButton(systemImage: "pencil", label: "Rename role\u{2026}") {
                        renameText = role.name
                        renamingRoleId = role.id
                    }
                    RowActionButton(systemImage: "trash", label: "Delete role\u{2026}") {
                        pendingDeleteRole = role
                    }
                    #endif
                }
                .rowActions {
                    Button {
                        renameText = role.name
                        renamingRoleId = role.id
                    } label: {
                        Label("Rename\u{2026}", systemImage: "pencil")
                    }
                    .tint(.blue)

                    Button(role: .destructive) {
                        pendingDeleteRole = role
                    } label: {
                        Label("Delete\u{2026}", systemImage: "trash")
                    }
                }
            }

            HStack {
                TextField("New Role Name", text: $newRoleName)
                Button("Add") {
                    let trimmed = newRoleName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    engine.addRole(name: trimmed)
                    newRoleName = ""
                }
                .disabled(newRoleName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Roles")
        } footer: {
            #if os(macOS)
            Text("Use the pencil and trash buttons on a role — or right-click it — to rename or delete. Roles can be deleted down to none; add a new one any time.")
            #else
            Text("Swipe a role left to delete it, or right to rename it — or long-press it for the same menu. Roles can be deleted down to none; add a new one any time.")
            #endif
        }
    }

    @ViewBuilder
    private func noteCategorySection(for role: RoleCue) -> some View {
        if !categories.isEmpty {
            Section {
                ForEach(categories, id: \.self) { category in
                    Toggle(category, isOn: Binding(
                        get: { role.assignedNoteCategories.contains(category) },
                        set: { engine.setNoteCategory(forRoleId: role.id, category: category, isOn: $0) }
                    ))
                }
            } header: {
                Text("\(role.name) — Notes Exposed")
            } footer: {
                Text("Checked categories show on this role's pager as its Current/Next note panel.")
            }
        }
    }
}
