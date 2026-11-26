// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

#if os(macOS) || os(iOS)

/// Edits the quick phrases offered above the message composer: one shared list plus an optional list per
/// role, as chips, with a live preview of the composer that role's operator would use. Saved with the producer document.
struct CannedPhrasesView: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss

    /// nil selects the shared list.
    @State private var selectedRoleId: String?
    @State private var newPhrase = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    rolePicker
                    editor
                    Divider()
                    preview
                }
                .padding()
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
        .frame(minWidth: 560, minHeight: 480)
        #endif
    }

    private var role: RoleCue? {
        selectedRoleId.flatMap { id in engine.roles.first(where: { $0.id == id }) }
    }

    private var phrases: [String] {
        role?.cannedPhrases ?? (selectedRoleId == nil ? engine.sharedPhrases : [])
    }

    private var rolePicker: some View {
        ChipFlowLayout {
            roleChip("Shared", id: nil)
            ForEach(engine.roles) { entry in
                roleChip(entry.name, id: entry.id)
            }
        }
    }

    private func roleChip(_ title: String, id: String?) -> some View {
        let selected = selectedRoleId == id
        return Button { selectedRoleId = id } label: {
            Text(title)
                .font(.callout.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.accentColor : Color.primary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
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
                Text(role.map { "\($0.name) phrases" } ?? "Shared phrases")
                    .font(.headline)
                Spacer()
                if let role {
                    Toggle("Also show shared phrases", isOn: Binding(
                        get: { role.usesSharedPhrases ?? true },
                        set: { engine.setPhrases(forRoleId: role.id, phrases: role.cannedPhrases ?? [], usesShared: $0) }
                    ))
                    .toggleStyle(.switch)
                }
            }
            Text(role == nil
                 ? "Offered to every role that has shared phrases turned on, and to the Everyone thread."
                 : "Shown above the composer when you message \(role?.name ?? "this role"). There is no limit on how many.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ChipFlowLayout {
                ForEach(Array(phrases.enumerated()), id: \.offset) { index, phrase in
                    HStack(spacing: 4) {
                        Text(phrase)
                        Button {
                            var list = phrases
                            list.remove(at: index)
                            commit(list)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                        }
                        .buttonStyle(.plain)
                        .help("Remove this phrase")
                        .accessibilityLabel("Remove \(phrase)")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
            }
            if phrases.isEmpty {
                Text(role == nil ? "No shared phrases." : "No phrases for this role yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField("Add a phrase", text: $newPhrase)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addPhrase)
                Button("Add", action: addPhrase)
                    .disabled(newPhrase.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// The composer as that role's operator sees it.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview in Messages")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                let shown = engine.phrases(forRoleId: selectedRoleId)
                ChipFlowLayout {
                    ForEach(shown, id: \.self) { phrase in
                        Text(phrase)
                            .font(.caption)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.1), in: Capsule())
                    }
                }
                HStack {
                    Text("To: \(role?.name ?? "Everyone")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Message…")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    Text("Send")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.white)
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func addPhrase() {
        let value = newPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        commit(phrases + [value])
        newPhrase = ""
    }
}
#endif
