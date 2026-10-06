// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct PlanItemEditorView: View {
    public enum Mode: Identifiable {
        case add
        case edit(PCOTimerItem)

        public var id: String {
            switch self {
            case .add: return "add"
            case .edit(let item): return item.id
            }
        }
    }

    private static let commonTypes = ["Item", "Song", "Header", "Media"]

    let mode: Mode
    let knownCategories: [String]
    let onSave: (_ id: String?, _ title: String, _ itemType: String, _ lengthInSeconds: Int, _ notes: [String: String], _ isDurationActual: Bool) -> Void

    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var itemType: String
    @State private var lengthInSeconds: Int
    @State private var isDurationActual: Bool
    @State private var isEditingDuration = false
    @State private var notes: [String: String]
    @State private var newCategoryName: String = ""
    @State private var newWaypointName: String = ""

    public init(
        mode: Mode,
        knownCategories: [String] = [],
        onSave: @escaping (_ id: String?, _ title: String, _ itemType: String, _ lengthInSeconds: Int, _ notes: [String: String], _ isDurationActual: Bool) -> Void
    ) {
        self.mode = mode
        self.knownCategories = knownCategories
        self.onSave = onSave

        switch mode {
        case .add:
            _title = State(initialValue: "")
            _itemType = State(initialValue: "Item")
            _lengthInSeconds = State(initialValue: 5 * 60)
            _isDurationActual = State(initialValue: false)
            _notes = State(initialValue: [:])
        case .edit(let item):
            _title = State(initialValue: item.title)
            _itemType = State(initialValue: item.itemType)
            _lengthInSeconds = State(initialValue: item.lengthInSeconds)
            _isDurationActual = State(initialValue: item.isDurationActual)
            _notes = State(initialValue: item.notes)
        }
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Title", text: $title)

                    Picker("Type", selection: $itemType) {
                        ForEach(Self.commonTypes, id: \.self) { Text($0) }
                        if !Self.commonTypes.contains(itemType) {
                            Text(itemType).tag(itemType)
                        }
                    }
                }

                if itemType.caseInsensitiveCompare("header") != .orderedSame {
                    Section {
                        durationRow
                        Toggle("Actual duration (not projected)", isOn: $isDurationActual)
                    } header: {
                        Text("Duration")
                    } footer: {
                        Text("Most items are projected. Mark a duration as actual for a fixed, known length — a song's recorded runtime, a video clip.")
                    }
                }

                notesSection

                if case .edit(let item) = mode {
                    waypointsSection(itemId: item.id)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isAdding ? "Add Item" : "Edit Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let id: String? = {
                            if case .edit(let item) = mode { return item.id }
                            return nil
                        }()
                        onSave(id, title, itemType, lengthInSeconds, notes, isDurationActual)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var durationRow: some View {
        HStack {
            Text("Length")
            Spacer()
            Text(formattedLength)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(isEditingDuration ? Color.accentColor.opacity(0.35) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isEditingDuration else { return }
                    isEditingDuration = true
                }
                .timeEntryPopover(
                    isPresented: $isEditingDuration,
                    previewBaseSeconds: lengthInSeconds,
                    hourFormatThreshold: engine.hourFormatThreshold
                ) { action in
                    switch action {
                    case .setAbsolute(let seconds):
                        lengthInSeconds = max(0, seconds)
                    case .adjustRelative(let delta):
                        lengthInSeconds = max(0, lengthInSeconds + delta)
                    }
                }
        }
    }

    private var formattedLength: String {
        TimeFormatting.string(forSeconds: lengthInSeconds, threshold: engine.hourFormatThreshold)
    }

    private var notesSection: some View {
        Section {
            ForEach(notes.keys.sorted(), id: \.self) { category in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(category)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) { notes.removeValue(forKey: category) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    TextField("Note content", text: Binding(
                        get: { notes[category] ?? "" },
                        set: { notes[category] = $0 }
                    ), axis: .vertical)
                }
                .padding(.vertical, 2)
            }

            addCategoryRow
        } header: {
            Text("Notes")
        } footer: {
            Text("Shown to any role assigned this category as its Current/Next note on the pager.")
        }
    }

    private var addCategoryRow: some View {
        HStack {
            if !unusedKnownCategories.isEmpty {
                Menu {
                    ForEach(unusedKnownCategories, id: \.self) { category in
                        Button(category) { notes[category] = "" }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
            }

            TextField("New category name", text: $newCategoryName)
            Button("Add") {
                let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                notes[trimmed] = ""
                newCategoryName = ""
            }
            .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var unusedKnownCategories: [String] {
        knownCategories.filter { !notes.keys.contains($0) }
    }

    private func waypointsSection(itemId: String) -> some View {
        Section {
            ForEach(engine.waypoints) { waypoint in
                let currentItemId = engine.itemId(forWaypointId: waypoint.id)
                Toggle(isOn: Binding(
                    get: { currentItemId == itemId },
                    set: { isOn in
                        engine.assignWaypoint(waypoint.id, toItemId: isOn ? itemId : nil)
                    }
                )) {
                    if let currentItemId, currentItemId != itemId,
                       let currentTitle = engine.planItems.first(where: { $0.id == currentItemId })?.title {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(waypoint.name)
                            Text("Currently on \u{201C}\(currentTitle)\u{201D}")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(waypoint.name)
                    }
                }
            }

            HStack {
                TextField("New Waypoint Name", text: $newWaypointName)
                Button("Add") {
                    let trimmed = newWaypointName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    if let waypoint = engine.addWaypoint(name: trimmed) {
                        engine.assignWaypoint(waypoint.id, toItemId: itemId)
                    }
                    newWaypointName = ""
                }
                .disabled(newWaypointName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Waypoints")
        } footer: {
            Text("A checked waypoint (e.g. \u{201C}Song 1\u{201D}) is how a Stream Deck or Companion button finds this item without knowing its title. Create, rename, and delete waypoints in Settings › Waypoints.")
        }
    }

    private var isAdding: Bool {
        if case .add = mode { return true }
        return false
    }
}
