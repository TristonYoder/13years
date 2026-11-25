// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

/// Edits the quick phrases offered above the message composer: one shared list plus
/// an optional list per role. Stored in the producer document, so they travel with it.
struct CannedPhrasesView: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss

    /// nil selects the shared list.
    @State private var selectedRoleId: String?
    @State private var newPhrase = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                List(selection: $selectedRoleId) {
                    Label("Shared (all roles)", systemImage: "star")
                        .tag(String?.none)
                    Section("Roles") {
                        ForEach(engine.roles) { role in
                            HStack {
                                Text(role.name)
                                Spacer()
                                Text("\(role.cannedPhrases?.count ?? 0)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(String?.some(role.id))
                        }
                    }
                }
                #if os(macOS)
                .listStyle(.sidebar)
                #endif
                .frame(width: 200)
                Divider()
                editor
            }
            Divider()
            HStack {
                Text("Saved with the producer document.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 420)
        #endif
    }

    private var role: RoleCue? {
        selectedRoleId.flatMap { id in engine.roles.first(where: { $0.id == id }) }
    }

    private var phrases: [String] {
        role?.cannedPhrases ?? (selectedRoleId == nil ? engine.sharedPhrases : [])
    }

    private func commit(_ list: [String]) {
        if let role {
            engine.setPhrases(forRoleId: role.id, phrases: list, usesShared: role.usesSharedPhrases ?? true)
        } else {
            engine.setSharedPhrases(list)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(role?.name ?? "Shared phrases")
                    .font(.headline)
                Spacer()
                if let role {
                    Toggle("Also show shared phrases", isOn: Binding(
                        get: { role.usesSharedPhrases ?? true },
                        set: { engine.setPhrases(forRoleId: role.id, phrases: role.cannedPhrases ?? [], usesShared: $0) }
                    ))
                    .toggleStyle(.switch)
                    .help("Shared phrases appear after this role's own phrases")
                }
            }
            Text(role == nil
                 ? "Offered to every role that has shared phrases turned on, and to the Everyone thread."
                 : "Shown above the composer when you message \(role?.name ?? "this role"). There is no limit on how many.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(Array(phrases.enumerated()), id: \.offset) { index, phrase in
                    HStack {
                        TextField("Phrase", text: Binding(
                            get: { phrase },
                            set: { value in
                                var list = phrases
                                guard list.indices.contains(index) else { return }
                                list[index] = value
                                commitKeepingEmpty(list)
                            }
                        ))
                        .textFieldStyle(.plain)
                        Button {
                            var list = phrases
                            list.remove(at: index)
                            commit(list)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove this phrase")
                        .accessibilityLabel("Remove \(phrase)")
                    }
                }
                .onMove { source, destination in
                    var list = phrases
                    list.move(fromOffsets: source, toOffset: destination)
                    commit(list)
                }
            }
            .overlay {
                if phrases.isEmpty {
                    Text(role == nil ? "No shared phrases." : "No phrases for this role yet.")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                TextField("Add a phrase", text: $newPhrase)
                    .onSubmit(addPhrase)
                Button("Add", action: addPhrase)
                    .disabled(newPhrase.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }

    /// Editing a field live must not drop an entry that is momentarily empty.
    private func commitKeepingEmpty(_ list: [String]) {
        if let role {
            engine.roleCannedPhrasesRaw(forRoleId: role.id, list)
        } else {
            engine.sharedPhrases = list
        }
    }

    private func addPhrase() {
        let value = newPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        commit(phrases + [value])
        newPhrase = ""
    }
}
