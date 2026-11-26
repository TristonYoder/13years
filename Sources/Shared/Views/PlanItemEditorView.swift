// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct NewItemPlacement: Equatable {
    public var position: Int?
    public var count: Int

    public static let atEnd = NewItemPlacement(position: nil, count: 1)
}

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

    enum EditorTab: String, CaseIterable, Identifiable {
        case form = "Form"
        case quick = "Quick add"
        case importText = "Import text"
        var id: String { rawValue }
    }

    private static let commonTypes = ["Item", "Song", "Header", "Media"]

    let mode: Mode
    let knownCategories: [String]
    let onImport: ((_ title: String, _ items: [PCOTimerItem]) -> Void)?
    let onSave: (_ id: String?, _ title: String, _ itemType: String, _ lengthInSeconds: Int, _ notes: [String: String], _ isDurationActual: Bool, _ description: String?, _ servicePosition: PCOServicePosition?, _ trigger: ItemTrigger?, _ cueRoleIds: [String], _ placement: NewItemPlacement) -> Void

    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var itemType: String
    @State private var lengthInSeconds: Int
    @State private var isDurationActual: Bool
    @State private var isEditingDuration = false
    @State private var trigger: ItemTrigger?
    @State private var cueRoleIds: [String]
    @State private var commandText = ""
    @State private var commandResult = ItemCommandParser.parse("")
    @State private var placement = NewItemPlacement.atEnd
    @FocusState private var commandFocused: Bool
    @AppStorage("itemEditorTab") private var lastTabRaw = EditorTab.form.rawValue
    @State private var tab: EditorTab = .form
    @State private var importTitle = ""
    @State private var importText = ""
    @State private var confirmingImport = false
    @State private var notes: [String: String]
    @State private var itemDescription: String
    @State private var servicePosition: PCOServicePosition
    private let isManual: Bool
    @State private var newCategoryName: String = ""
    @State private var newWaypointName: String = ""

    public init(
        mode: Mode,
        knownCategories: [String] = [],
        onImport: ((_ title: String, _ items: [PCOTimerItem]) -> Void)? = nil,
        onSave: @escaping (_ id: String?, _ title: String, _ itemType: String, _ lengthInSeconds: Int, _ notes: [String: String], _ isDurationActual: Bool, _ description: String?, _ servicePosition: PCOServicePosition?, _ trigger: ItemTrigger?, _ cueRoleIds: [String], _ placement: NewItemPlacement) -> Void
    ) {
        self.mode = mode
        self.knownCategories = knownCategories
        self.onImport = onImport
        if case .add = mode {
            let stored = UserDefaults.standard.string(forKey: "itemEditorTab").flatMap(EditorTab.init(rawValue:))
            _tab = State(initialValue: stored.flatMap { ($0 != .importText || onImport != nil) ? $0 : nil } ?? .form)
        }
        self.onSave = onSave

        switch mode {
        case .add:
            _title = State(initialValue: "")
            _itemType = State(initialValue: "Item")
            _lengthInSeconds = State(initialValue: 5 * 60)
            _isDurationActual = State(initialValue: false)
            _trigger = State(initialValue: nil)
            _cueRoleIds = State(initialValue: [])
            _notes = State(initialValue: [:])
            _itemDescription = State(initialValue: "")
            _servicePosition = State(initialValue: .during)
            isManual = true
        case .edit(let item):
            _title = State(initialValue: item.title)
            _itemType = State(initialValue: item.itemType)
            _lengthInSeconds = State(initialValue: item.lengthInSeconds)
            _isDurationActual = State(initialValue: item.isDurationActual)
            _trigger = State(initialValue: item.trigger)
            _cueRoleIds = State(initialValue: item.cueRoleIds)
            _notes = State(initialValue: item.notes)
            _itemDescription = State(initialValue: item.details?.description ?? "")
            _servicePosition = State(initialValue: item.details?.servicePosition ?? .during)
            isManual = item.pcoPlanId == nil
        }
    }

    public var body: some View {
        #if os(macOS)
        editorForm
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    saveButton
                }
                .padding()
                .background(.bar)
            }
            .frame(minWidth: 460, minHeight: 480)
        #else
        NavigationStack {
            editorForm
                .navigationTitle(isAdding ? "Add Item" : "Edit Item")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        saveButton
                    }
                }
        }
        #endif
    }

    @ViewBuilder
    private var saveButton: some View {
        if isImporting {
            Button("Import") {
                if engine.planItems.isEmpty { performImport() } else { confirmingImport = true }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(importItems.isEmpty)
            .confirmationDialog("Replace the current run sheet?", isPresented: $confirmingImport, titleVisibility: .visible) {
                Button("Replace with \(importItems.count) Item\(importItems.count == 1 ? "" : "s")", role: .destructive) { performImport() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Importing replaces every item in the current flow.")
            }
        } else {
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let id: String? = {
            if case .edit(let item) = mode { return item.id }
            return nil
        }()
        let isHeader = itemType.caseInsensitiveCompare("header") == .orderedSame
        onSave(
            id, title, itemType, lengthInSeconds, notes, isDurationActual,
            isManual && !isHeader ? itemDescription : nil,
            isManual ? servicePosition : nil,
            isHeader ? nil : trigger,
            isHeader ? [] : cueRoleIds,
            isAdding ? placement : .atEnd
        )
        dismiss()
    }

    @ViewBuilder
    private var editorForm: some View {
        if isAdding {
            #if os(macOS)
            TabView(selection: $tab) {
                ForEach(availableTabs) { entry in
                    Form { tabContent(entry) }
                        .formStyle(.grouped)
                        .tabItem { Text(entry.rawValue) }
                        .tag(entry)
                }
            }
            .onChange(of: tab) { _, newTab in lastTabRaw = newTab.rawValue }
            #else
            Form {
                Picker("Editor", selection: $tab) {
                    ForEach(availableTabs) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: tab) { _, newTab in lastTabRaw = newTab.rawValue }
                tabContent(tab)
            }
            .formStyle(.grouped)
            #endif
        } else {
            Form { formSections }
                .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private func tabContent(_ entry: EditorTab) -> some View {
        switch entry {
        case .form:
            formSections
        case .quick:
            commandSection
            resultSection
        case .importText:
            ImportFlowSections(planTitle: $importTitle, text: $importText)
        }
    }

    private var availableTabs: [EditorTab] {
        onImport == nil ? [.form, .quick] : EditorTab.allCases
    }

    private var isImporting: Bool { isAdding && tab == .importText }

    private var importItems: [PCOTimerItem] { ImportFlowSections.parsedItems(importText) }

    private func performImport() {
        onImport?(importTitle, importItems)
        dismiss()
    }

    @ViewBuilder
    private var resultSection: some View {
        Section("Result") {
            Text(commandText.trimmingCharacters(in: .whitespaces).isEmpty ? "Type a command above to see the item it makes." : commandSummary)
                .font(.callout)
                .foregroundStyle(commandResult.isValid ? Color.primary : AppPalette.warning)
        }
    }

    @ViewBuilder
    private var formSections: some View {
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
                        VStack(alignment: .leading, spacing: 8) {
                            Text("How this starts")
                            Picker("How this starts", selection: $trigger) {
                                Text("Plan default").tag(ItemTrigger?.none)
                                Text("Follow").tag(ItemTrigger?.some(.follow))
                                Text("Go").tag(ItemTrigger?.some(.go))
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .disabled(startsPlan)
                        }
                        .padding(.vertical, 2)
                    } header: {
                        Text("Duration")
                    } footer: {
                        Text("Most items are projected. Mark a duration as actual for a fixed, known length — a song's recorded runtime, a video clip. Follow starts this item when the one before it reaches zero. Go waits for the producer.")
                    }
                }

                if itemType.caseInsensitiveCompare("header") != .orderedSame {
                    cueRolesSection
                }

                if isManual {
                    placementSection
                }

                notesSection

                if case .edit(let item) = mode {
                    waypointsSection(itemId: item.id)
                }
    }

    private var commandSection: some View {
        Section {
            TextField("Command", text: $commandText, prompt: Text("\u{201C}Amazing Grace\u{201D} Time 4:30 Type Song"))
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .focused($commandFocused)
                .onSubmit { if canSave { save() } }
                .onChange(of: commandText) { _, text in applyCommand(text) }
                .onAppear { commandFocused = true }
        } header: {
            Text("Quick add")
        } footer: {
            Text("Store Item 4 Thru 6 \u{201C}Song\u{201D} Time 4:30 Type Song Trigger Follow /Actual. Everything but the name is optional, and times work like the timer.")
        }
    }

    private func applyCommand(_ text: String) {
        let result = ItemCommandParser.parse(text)
        commandResult = result
        let command = result.command
        if let value = command.title { title = value }
        if let value = command.type { itemType = value }
        if command.length != nil { lengthInSeconds = command.resolvedLength(base: 5 * 60) }
        if command.trigger != nil { trigger = command.trigger }
        if let value = command.isActual { isDurationActual = value }
        if let value = command.servicePosition { servicePosition = value }
        placement = NewItemPlacement(position: command.position, count: max(1, min(command.count, ItemCommandParser.maxCount)))
    }

    private var commandSummary: String {
        guard commandResult.isValid else { return commandResult.errors.joined(separator: " \u{00B7} ") }
        let command = commandResult.command
        var parts: [String] = []
        if let type = command.type { parts.append(type) }
        parts.append(command.title.map { "\u{201C}\($0)\u{201D}" } ?? "Untitled")
        if command.length != nil { parts.append(formattedLength) }
        if let value = command.trigger { parts.append(value == .follow ? "Follow" : "Go") }
        if command.isActual == true { parts.append("Actual") }
        if let position = command.servicePosition { parts.append(position == .pre ? "Before event" : "After event") }
        if let position = command.position { parts.append(command.count > 1 ? "Items \(position)\u{2013}\(position + command.count - 1)" : "Item \(position)") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var placementSection: some View {
        Section {
            Picker("Position", selection: $servicePosition) {
                Text("Before the event").tag(PCOServicePosition.pre)
                Text("During the event").tag(PCOServicePosition.during)
                Text("After the event").tag(PCOServicePosition.post)
            }
            if itemType.caseInsensitiveCompare("header") != .orderedSame {
                TextField("Description", text: $itemDescription, axis: .vertical)
                    .lineLimit(1...4)
            }
        } header: {
            Text("Run Sheet")
        } footer: {
            Text("Items before or after the event are scheduled around its start time instead of counting toward the event's length.")
        }
    }

    private var durationRow: some View {
        HStack {
            Text("Length")
            Spacer()
            Text(formattedLength)
                .font(.clock(.body, weight: .regular))
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
                    hourFormatThreshold: engine.hourFormatThreshold,
                    clockFormat: engine.clockFormat,
                    allowsEndAt: false
                ) { action in
                    switch action {
                    case .setAbsolute(let seconds):
                        lengthInSeconds = max(0, seconds)
                    case .adjustRelative(let delta):
                        lengthInSeconds = max(0, lengthInSeconds + delta)
                    case .endAt:
                        break
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
                    engine.createWaypointAndAssign(name: trimmed, toItemId: itemId)
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

    private var cueRolesSection: some View {
        Section {
            ForEach(engine.roles) { role in
                Toggle(isOn: Binding(
                    get: { cueRoleIds.contains(role.id) },
                    set: { isOn in
                        if isOn {
                            if !cueRoleIds.contains(role.id) { cueRoleIds.append(role.id) }
                        } else {
                            cueRoleIds.removeAll { $0 == role.id }
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(role.name)
                        if let person = role.personName, !person.isEmpty {
                            Text(person)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Cue")
        } footer: {
            Text("Standby and GO on this item's row call these roles. With none chosen, the row shows only play, which starts the clock without a light.")
        }
    }

    private var startsPlan: Bool {
        if case .edit(let item) = mode { return engine.isFirstPlanItem(id: item.id) }
        return false
    }

    private var isAdding: Bool {
        if case .add = mode { return true }
        return false
    }
}
