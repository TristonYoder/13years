// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct ServiceFlowView: View {
    @EnvironmentObject var engine: CueEngine
    @State private var editorMode: PlanItemEditorView.Mode?
    @State private var showingImportText = false
    @State private var expandedItemId: String?
    @State private var showingPlanPicker = false
    @State private var newWaypointTargetItemId: String?
    @State private var newWaypointName: String = ""
    @State private var pendingDeleteItem: PCOTimerItem?
    @State private var selectedItemId: String?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            SectionHeaderBar(mode: .serviceFlow) {
                Button(action: { showingImportText = true }) {
                    Label("Import Text", systemImage: "text.badge.plus")
                }
                .help("Paste in a plain-text service flow")

                Button(action: { showingPlanPicker = true }) {
                    Label(engine.isPCOConnected ? "Change Plan" : "Sync PCO", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Pick a Planning Center plan type and plan to sync")

                Button(action: { editorMode = .add }) {
                    Label("Add Item", systemImage: "plus")
                }
                .help("Add a single item to the flow")

                #if os(iOS)
                EditButton()
                    .help("Reorder or delete items")
                #endif
            }

            Group {
                if engine.planItems.isEmpty {
                    emptyState
                } else {
                    flowList
                }
            }
        }
        .sheet(item: $editorMode) { mode in
            PlanItemEditorView(mode: mode, knownCategories: knownNoteCategories) { id, title, itemType, lengthInSeconds, notes, isDurationActual in
                if let id {
                    engine.updatePlanItem(id: id, title: title, itemType: itemType, lengthInSeconds: lengthInSeconds, notes: notes, isDurationActual: isDurationActual)
                } else {
                    engine.addPlanItem(title: title, itemType: itemType, lengthInSeconds: lengthInSeconds, isDurationActual: isDurationActual)
                }
            }
        }
        .sheet(isPresented: $showingImportText) {
            ImportFlowTextView { title, items in
                engine.importFlow(title: title.isEmpty ? nil : title, items: items)
            }
        }
        .sheet(isPresented: $showingPlanPicker) {
            PCOPlanPickerView()
        }
        .alert("New Waypoint", isPresented: Binding(
            get: { newWaypointTargetItemId != nil },
            set: { if !$0 { newWaypointTargetItemId = nil } }
        )) {
            TextField("Waypoint Name", text: $newWaypointName)
            Button("Cancel", role: .cancel) { newWaypointTargetItemId = nil; newWaypointName = "" }
            Button("Create") {
                let trimmed = newWaypointName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, let itemId = newWaypointTargetItemId, let waypoint = engine.addWaypoint(name: trimmed) {
                    engine.assignWaypoint(waypoint.id, toItemId: itemId)
                }
                newWaypointTargetItemId = nil
                newWaypointName = ""
            }
        } message: {
            Text("Creates a reusable waypoint and assigns it to this item right away.")
        }
        .confirmationDialog(
            "Delete this item?",
            isPresented: Binding(
                get: { pendingDeleteItem != nil },
                set: { if !$0 { pendingDeleteItem = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteItem
        ) { item in
            Button("Delete", role: .destructive) {
                engine.removePlanItem(id: item.id)
                if selectedItemId == item.id { selectedItemId = nil }
                pendingDeleteItem = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteItem = nil }
        } message: { item in
            Text("\u{201C}\(item.title)\u{201D} and its notes will be removed from the flow.")
        }
    }

    private var knownNoteCategories: [String] {
        var set = Set(engine.pcoNoteCategories.map(\.name))
        for item in engine.planItems {
            set.formUnion(item.notes.keys)
        }
        return set.sorted()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            if let error = engine.pcoLastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }

            ContentUnavailableView(
                "No Service Flow",
                systemImage: "list.bullet.rectangle",
                description: Text("Sync from Planning Center, paste in a flow, or add items below.")
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var flowList: some View {
        #if os(macOS)
        List(selection: $selectedItemId) {
            flowListContent
        }
        .onDeleteCommand {
            guard let selectedItemId,
                  let item = engine.planItems.first(where: { $0.id == selectedItemId })
            else { return }
            pendingDeleteItem = item
        }
        #else
        List {
            flowListContent
        }
        #endif
    }

    @ViewBuilder
    private var flowListContent: some View {
        if let error = engine.pcoLastError {
            Section {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
        }

        if engine.planItems.first?.pcoPlanId != nil {
            Section {
                Toggle(isOn: Binding(
                    get: { engine.isPCOLiveSyncEnabled },
                    set: { newValue in
                        if newValue {
                            engine.enablePCOLiveSync()
                        } else {
                            engine.disablePCOLiveSync()
                        }
                    }
                )) {
                    Label("Sync with PCO Live", systemImage: "dot.radiowaves.left.and.right")
                }
            } footer: {
                Text(engine.isPCOLiveSyncEnabled
                    ? "This app controls Planning Center's Live view — item navigation mirrors there too. Taking control can interrupt another controller."
                    : "Takes control of Planning Center Live and mirrors item navigation to it — also happens automatically the moment you move to another item, since Live can't advance without control. Only use this on the plan you're actually running.")
            }
        }

        Section {
            ForEach(engine.planItems) { item in
                planItemRow(item)
            }
            .onMove { offsets, destination in
                engine.movePlanItems(fromOffsets: offsets, toOffset: destination)
            }
            .onDelete { offsets in
                for index in offsets {
                    engine.removePlanItem(id: engine.planItems[index].id)
                }
            }
        } header: {
            Text(engine.planItems.first?.servicePlanTitle ?? "Service Flow")
        }
    }

    private func planItemRow(_ item: PCOTimerItem) -> some View {
        let isActive = engine.activeTimerItem?.id == item.id
        let isExpanded = expandedItemId == item.id
        let isSelected = selectedItemId == item.id

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
                    .accessibilityHidden(true)

                Group {
                    if item.isHeader {
                        Color.clear
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formattedDuration(item.lengthInSeconds))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            durationModeBadge(item)
                        }
                    }
                }
                .frame(width: 44, alignment: .leading)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if item.isHeader {
                            Text(item.title.uppercased())
                                .font(.caption.weight(.heavy))
                                .tracking(1.0)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(item.title)
                                .font(.body.weight(isActive ? .bold : .regular))
                        }
                        if item.pcoPlanId != nil {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                                .help("Synced with Planning Center")
                        }
                    }

                    if !item.isHeader {
                        waypointsRow(for: item)
                    }

                    ForEach(item.notes.keys.sorted(), id: \.self) { category in
                        if let text = item.notes[category], !text.isEmpty {
                            Text("\(category): \(text)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }
                }

                Spacer()

                Group {
                    if item.isHeader {
                        EmptyView()
                    } else if isActive {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.green)
                                .frame(width: 52, height: 52)

                            Button {
                                engine.resetTimer()
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.title2.weight(.bold))
                                    .frame(width: 52, height: 52)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.roundedRectangle(radius: 10))
                            .tint(.secondary)
                            .accessibilityLabel("Reset")
                            .help("Reset this item's clock back to its full length — if Planning Center Live sync is on, also steps back and immediately forward there so PCO's own clock restarts too")
                        }
                    } else {
                        Button {
                            engine.setActivePlanItem(id: item.id)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.title2.weight(.bold))
                                .frame(width: 52, height: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 10))
                        .tint(.green)
                        .accessibilityLabel("Go")
                        .help("Jump to this item and make it active")
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        expandedItemId = isExpanded ? nil : item.id
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up.circle" : "chevron.down.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit time and notes inline")

                #if os(macOS)
                RowActionButton(systemImage: "pencil", label: "Edit item\u{2026}") {
                    editorMode = .edit(item)
                }
                RowActionButton(systemImage: "trash", label: "Delete item\u{2026}") {
                    pendingDeleteItem = item
                }
                #endif
            }

            if isExpanded {
                InlineItemEditor(item: item, knownCategories: knownNoteCategories)
                    .padding(.leading, 32)
            }
        }
        .listRowBackground(rowBackground(item, isActive: isActive, isSelected: isSelected))
        .rowActions {
            Button {
                editorMode = .edit(item)
            } label: {
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
                    waypointAssignmentMenuItems(for: item)
                } label: {
                    Label("Assign Waypoints\u{2026}", systemImage: Waypoint.symbolName)
                }
            }

            Button(role: .destructive) {
                pendingDeleteItem = item
            } label: {
                Label("Delete\u{2026}", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func waypointsRow(for item: PCOTimerItem) -> some View {
        let waypoints = engine.waypoints(forItemId: item.id)
        HStack(spacing: 4) {
            ForEach(waypoints) { waypoint in
                waypointChip(waypoint)
            }
            Menu {
                waypointAssignmentMenuItems(for: item)
            } label: {
                Image(systemName: waypoints.isEmpty ? Waypoint.symbolName : "plus")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .menuIndicator(.hidden)
            .help("Assign waypoints\u{2026}")
        }
    }

    private func waypointChip(_ waypoint: Waypoint) -> some View {
        HStack(spacing: 3) {
            Image(systemName: Waypoint.symbolName)
            Text(waypoint.name)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    @ViewBuilder
    private func waypointAssignmentMenuItems(for item: PCOTimerItem) -> some View {
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

        Button {
            newWaypointName = ""
            newWaypointTargetItemId = item.id
        } label: {
            Label("New Waypoint\u{2026}", systemImage: "plus")
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        TimeFormatting.string(forSeconds: seconds, threshold: engine.hourFormatThreshold)
    }

    private func durationModeBadge(_ item: PCOTimerItem) -> some View {
        Button {
            engine.setDurationIsActual(id: item.id, isActual: !item.isDurationActual)
        } label: {
            Text(item.isDurationActual ? "ACT" : "PROJ")
                .font(.inter(size: 9, weight: .bold))
                .foregroundStyle(item.isDurationActual ? Color.white : Color.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    item.isDurationActual ? Color.blue : Color.secondary.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(item.isDurationActual
            ? "Actual duration — tap to mark as projected"
            : "Projected duration — tap to mark as an actual, known duration")
    }

    @ViewBuilder
    private func rowBackground(_ item: PCOTimerItem, isActive: Bool, isSelected: Bool) -> some View {
        ZStack {
            if item.isHeader {
                Color.gray.opacity(0.14)
            } else {
                let liveItem = isActive ? (engine.activeTimerItem ?? item) : item
                if isActive && liveItem.isRunning {
                    let style = overrunStyle(for: liveItem)
                    PulsingRowBackground(color: style.color, minOpacity: style.min, maxOpacity: style.max)
                } else {
                    Color.clear
                }
            }

            if isSelected {
                Color.accentColor.opacity(0.22)
            }
        }
    }

    private func overrunStyle(for item: PCOTimerItem) -> (color: Color, min: Double, max: Double) {
        if item.isOvertime {
            return (Color(red: 0.80, green: 0.09, blue: 0.09), 0.28, 0.55)
        }
        if item.lengthInSeconds > 0, Double(item.remainingSeconds) <= Double(item.lengthInSeconds) * 0.1 {
            return (.yellow, 0.14, 0.34)
        }
        return (.green, 0.12, 0.30)
    }
}

private struct PulsingRowBackground: View {
    let color: Color
    let minOpacity: Double
    let maxOpacity: Double

    private static let period: TimeInterval = 1.4

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Self.period) / Self.period
            let wave = 0.5 - 0.5 * cos(phase * 2 * .pi)
            color.opacity(minOpacity + (maxOpacity - minOpacity) * wave)
        }
    }
}

private struct InlineItemEditor: View {
    @EnvironmentObject var engine: CueEngine
    let item: PCOTimerItem
    let knownCategories: [String]

    @State private var minutesText: String = ""
    @State private var secondsText: String = ""
    @State private var newCategoryName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !item.isHeader {
                HStack(spacing: 8) {
                    Text("Duration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("min", text: $minutesText)
                        .frame(width: 44)
                        #if os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                    Text(":")
                    TextField("sec", text: $secondsText)
                        .frame(width: 44)
                        #if os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                    Button("Set") { commitDuration() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            ForEach(item.notes.keys.sorted(), id: \.self) { category in
                noteField(category: category)
            }

            addCategoryRow
        }
        .onAppear {
            minutesText = "\(item.lengthInSeconds / 60)"
            secondsText = "\(item.lengthInSeconds % 60)"
        }
    }

    private func noteField(category: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(category)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Note content", text: Binding(
                get: { item.notes[category] ?? "" },
                set: { newValue in
                    var notes = item.notes
                    notes[category] = newValue
                    engine.updatePlanItem(id: item.id, title: item.title, itemType: item.itemType, lengthInSeconds: item.lengthInSeconds, notes: notes)
                }
            ), axis: .vertical)
            #if os(macOS)
            .textFieldStyle(.roundedBorder)
            #endif
        }
    }

    private var addCategoryRow: some View {
        HStack {
            if !unusedKnownCategories.isEmpty {
                Menu {
                    ForEach(unusedKnownCategories, id: \.self) { category in
                        Button(category) { addCategory(category) }
                    }
                } label: {
                    Label("Add Known Category", systemImage: "plus.circle")
                        .font(.caption)
                }
            }
            TextField("New category name", text: $newCategoryName)
                .font(.caption)
                #if os(macOS)
                .textFieldStyle(.roundedBorder)
                #endif
            Button("Add") {
                let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                addCategory(trimmed)
                newCategoryName = ""
            }
            .controlSize(.small)
            .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var unusedKnownCategories: [String] {
        knownCategories.filter { !item.notes.keys.contains($0) }
    }

    private func addCategory(_ category: String) {
        var notes = item.notes
        notes[category] = ""
        engine.updatePlanItem(id: item.id, title: item.title, itemType: item.itemType, lengthInSeconds: item.lengthInSeconds, notes: notes)
    }

    private func commitDuration() {
        let minutes = Int(minutesText) ?? (item.lengthInSeconds / 60)
        let seconds = Int(secondsText) ?? (item.lengthInSeconds % 60)
        engine.updatePlanItem(id: item.id, title: item.title, itemType: item.itemType, lengthInSeconds: minutes * 60 + seconds)
    }
}
