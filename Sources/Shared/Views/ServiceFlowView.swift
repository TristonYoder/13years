// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

enum RunSheetLayout: String {
    case list
    case table

    static let storageKey = "runSheetLayout"
}

public struct ServiceFlowView: View {
    @EnvironmentObject var engine: CueEngine
    @State private var editorMode: PlanItemEditorView.Mode?
    @State private var expandedItemId: String?
    @State private var showingPlanPicker = false
    @State private var newWaypointTargetItemId: String?
    @State private var newWaypointName: String = ""
    @State private var pendingDeleteItem: PCOTimerItem?
    @State private var selectedItemId: String?
    @State private var showingEventTimes = false
    #if os(macOS) || os(iOS)
    @State private var referenceRequest: RunSheetReferenceRequest?
    #endif
    @AppStorage(RunSheetLayout.storageKey) private var layoutRaw = RunSheetLayout.list.rawValue
    @AppStorage(RunSheetPlanPanelStorage.key) private var planPanelVisible = false
    @SceneStorage("runSheetCollapsedHeaders") private var collapsedRaw = ""
    #if os(macOS)
    @AppStorage("runSheetNowNextPane") private var nowNextPane = false
    #endif

    public init() {}

    private var layout: RunSheetLayout {
        #if os(macOS)
        RunSheetLayout(rawValue: layoutRaw) ?? .list
        #else
        .list
        #endif
    }

    private var collapsedHeaderIds: Set<String> {
        Set(collapsedRaw.split(separator: ",").map(String.init))
    }

    public var body: some View {
        let schedule = engine.runSheetSchedule()

        VStack(spacing: 0) {
            SectionHeaderBar(mode: .serviceFlow, showsTitles: true) {
                #if os(macOS)
                Picker("Layout", selection: $layoutRaw) {
                    Label("List", systemImage: "list.bullet").tag(RunSheetLayout.list.rawValue)
                    Label("Table", systemImage: "tablecells").tag(RunSheetLayout.table.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 84)
                .padding(.trailing, 6)
                .help("Switch the run sheet between a list and a table with customizable columns")

                if layout == .table {
                    RunSheetColumnsMenu(categories: knownNoteCategories)

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { nowNextPane.toggle() }
                    } label: {
                        Label("Now & Next", systemImage: "rectangle.split.2x1")
                    }
                    .help(nowNextPane ? "Hide the Now & Next pane" : "Show the current and next items in a side pane")
                }
                #endif

                #if os(macOS)
                Menu {
                    RunSheetTimingToggles()
                } label: {
                    Label("Display", systemImage: "slider.horizontal.3")
                }
                .headerActionPrimary()
                .help("End times and Follow by default")
                #elseif os(iOS)
                Button(action: { planPanelVisible.toggle() }) {
                    Label("Plan", systemImage: "sidebar.trailing")
                }
                .headerActionPrimary()
                .help("Plan name, Sync PCO and Event Times, plus the Planning Center notes, times and team")
                #endif

                #if !os(macOS)
                RehearsalBadge()
                #endif

                RunSheetActualsMenu()

                #if !(os(macOS) || os(iOS))
                Button(action: { engine.whenPCOConnected { showingPlanPicker = true } }) {
                    Label(engine.isPCOConnected ? "Change Plan" : "Sync PCO", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Pick a Planning Center plan type and plan to sync")

                Button(action: { showingEventTimes = true }) {
                    Label("Event Times", systemImage: "clock")
                }
                .help("Set up the times this run sheet runs, like a 9:00 and an 11:00 event")
                #endif

                Button(action: { editorMode = .add }) {
                    Label("Add Item", systemImage: "plus")
                }
                .headerActionPrimary()
                .help("Add a single item to the flow")

                #if os(iOS)
                EditButton()
                    .help("Reorder or delete items")
                #endif
            }

            PCOChangesBanner()

            Group {
                if engine.planItems.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        switch layout {
                        case .list:
                            flowList(schedule)
                        case .table:
                            tableLayout(schedule)
                        }
                        RunSheetTotalsView(schedule: schedule)
                    }
                }
            }
        }
        #if os(macOS) || os(iOS)
        .modifier(RunSheetPlanInspectorModifier(
            isPresented: $planPanelVisible,
            onChangePlan: { engine.whenPCOConnected { showingPlanPicker = true } },
            onEventTimes: { showingEventTimes = true }
        ))
        #endif
        #if os(macOS) || os(iOS)
        .environment(\.runSheetReferencePresenter, RunSheetReferencePresenter { referenceRequest = $0 })
        .sheet(item: $referenceRequest) { request in
            switch request {
            case .attachments(let item):
                RunSheetAttachmentsSheet(item: item)
            case .chart(let item):
                RunSheetChartSheet(item: item)
            }
        }
        #endif
        .onScreenshotTourSignal("runsheet.add-item") { _ in editorMode = .add }
        .onScreenshotTourSignal("runsheet.edit-item") { id in
            if let item = engine.planItems.first(where: { $0.id == id }) { editorMode = .edit(item) }
        }
        .onScreenshotTourSignal("runsheet.delete-item") { id in
            pendingDeleteItem = engine.planItems.first { $0.id == id }
        }
        .onScreenshotTourSignal("runsheet.new-waypoint") { id in newWaypointTargetItemId = id }
        .onScreenshotTourSignal("runsheet.import-text") { _ in
            UserDefaults.standard.set(PlanItemEditorView.EditorTab.importText.rawValue, forKey: "itemEditorTab")
            editorMode = .add
        }
        .onScreenshotTourSignal("runsheet.event-times") { _ in showingEventTimes = true }
        .sheet(item: $editorMode) { mode in
            PlanItemEditorView(mode: mode, knownCategories: knownNoteCategories, onImport: { items in
                engine.importFlow(title: nil, items: items)
            }) { id, title, itemType, lengthInSeconds, notes, isDurationActual, description, servicePosition, trigger, cueRoleIds, placement in
                if let id {
                    engine.updatePlanItem(id: id, title: title, itemType: itemType, lengthInSeconds: lengthInSeconds, notes: notes, isDurationActual: isDurationActual, description: description, servicePosition: servicePosition)
                    engine.setItemTrigger(id: id, trigger)
                    engine.setItemCueRoles(id: id, cueRoleIds)
                } else {
                    let countBefore = engine.planItems.count
                    let hasDetails = !(description ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (servicePosition ?? .during) != .during
                    for _ in 0..<placement.count {
                        let newId = engine.addPlanItem(title: title, itemType: itemType, lengthInSeconds: lengthInSeconds, isDurationActual: isDurationActual)
                        guard let newId else { continue }
                        if hasDetails {
                            engine.updatePlanItem(id: newId, title: title, itemType: itemType, lengthInSeconds: lengthInSeconds, description: description, servicePosition: servicePosition)
                        }
                        engine.setItemTrigger(id: newId, trigger)
                        engine.setItemCueRoles(id: newId, cueRoleIds)
                    }
                    let added = engine.planItems.count - countBefore
                    if let position = placement.position, added > 0 {
                        let target = min(max(position - 1, 0), countBefore)
                        if target < countBefore {
                            engine.movePlanItems(fromOffsets: IndexSet(countBefore..<(countBefore + added)), toOffset: target)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingPlanPicker) {
            PCOPlanPickerView()
        }
        .sheet(isPresented: $showingEventTimes) {
            EventTimesView()
        }
        .alert("New Waypoint", isPresented: Binding(
            get: { newWaypointTargetItemId != nil },
            set: { if !$0 { newWaypointTargetItemId = nil } }
        )) {
            TextField("Waypoint Name", text: $newWaypointName)
            Button("Cancel", role: .cancel) { newWaypointTargetItemId = nil; newWaypointName = "" }
            Button("Create") {
                let trimmed = newWaypointName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, let itemId = newWaypointTargetItemId {
                    engine.createWaypointAndAssign(name: trimmed, toItemId: itemId)
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
                    .foregroundStyle(AppPalette.warning)
                    .font(.footnote)
            }

            ContentUnavailableView(
                "No Run Sheet",
                systemImage: "list.bullet.rectangle",
                description: Text("Sync a Planning Center plan from the Plan tab, or use Add Item to add items one at a time or paste in a whole run sheet.")
            )
            #if os(macOS) || os(iOS)
            Button {
                planPanelVisible = true
            } label: {
                Label("Open Plan", systemImage: "sidebar.trailing")
            }
            .buttonStyle(.borderedProminent)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func tableLayout(_ schedule: RunSheetSchedule) -> some View {
        #if os(macOS)
        GeometryReader { proxy in
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                RunSheetTableView(
                    schedule: schedule,
                    selection: $selectedItemId,
                    knownCategories: knownNoteCategories,
                    excludedLabel: engine.liveEventTimeLabel,
                    compact: nowNextPane,
                    onEdit: { editorMode = .edit($0) },
                    onDelete: { pendingDeleteItem = $0 },
                    onNewWaypoint: { newWaypointTargetItemId = $0.id }
                )
            }
            if nowNextPane {
                RunSheetNowNextPane(schedule: schedule, categories: knownNoteCategories, containerWidth: proxy.size.width, selectedItemId: selectedItemId)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
        #else
        EmptyView()
        #endif
    }

    private struct SheetSection: Identifiable {
        let position: PCOServicePosition
        let items: [PCOTimerItem]
        var id: String { position.rawValue }
    }

    private var sheetSections: [SheetSection] {
        let items = engine.planItems
        let positions = RunSheetSchedule.positions(of: items)
        return [PCOServicePosition.pre, .during, .post].compactMap { position in
            let matching = items.indices.filter { positions[$0] == position }.map { items[$0] }
            return matching.isEmpty ? nil : SheetSection(position: position, items: matching)
        }
    }

    private func visibleItems(in section: SheetSection) -> [PCOTimerItem] {
        let collapsed = collapsedHeaderIds
        var result: [PCOTimerItem] = []
        var hidden = false
        for item in section.items {
            if item.isHeader {
                result.append(item)
                hidden = collapsed.contains(item.id)
            } else if !hidden {
                result.append(item)
            }
        }
        return result
    }

    private func toggleCollapsed(_ headerId: String) {
        var ids = collapsedHeaderIds
        if ids.contains(headerId) {
            ids.remove(headerId)
        } else {
            ids.insert(headerId)
        }
        let valid = Set(engine.planItems.map(\.id))
        collapsedRaw = ids.intersection(valid).sorted().joined(separator: ",")
    }

    private func moveItems(in section: SheetSection, visible: [PCOTimerItem], from offsets: IndexSet, to destination: Int) {
        let planItems = engine.planItems
        func globalIndex(_ id: String) -> Int? { planItems.firstIndex { $0.id == id } }

        var source = IndexSet()
        for offset in offsets where visible.indices.contains(offset) {
            let item = visible[offset]
            guard let index = globalIndex(item.id) else { continue }
            source.insert(index)
            if item.isHeader, collapsedHeaderIds.contains(item.id),
               let sectionIndex = section.items.firstIndex(where: { $0.id == item.id }) {
                for child in section.items[(sectionIndex + 1)...].prefix(while: { !$0.isHeader }) {
                    if let childIndex = globalIndex(child.id) { source.insert(childIndex) }
                }
            }
        }

        let target: Int?
        if destination < visible.count {
            target = globalIndex(visible[destination].id)
        } else {
            target = section.items.last.flatMap { globalIndex($0.id) }.map { $0 + 1 }
        }
        guard let target, !source.isEmpty else { return }
        engine.movePlanItems(fromOffsets: source, toOffset: target)
    }

    private func sectionTitle(_ section: SheetSection) -> String {
        switch section.position {
        case .pre: return "Before the event"
        case .post: return "After the event"
        case .during: return engine.planTitle ?? "Run Sheet"
        }
    }

    private func flowList(_ schedule: RunSheetSchedule) -> some View {
        #if os(macOS)
        List(selection: $selectedItemId) {
            flowListContent(schedule)
        }
        .onDeleteCommand {
            guard let selectedItemId,
                  let item = engine.planItems.first(where: { $0.id == selectedItemId })
            else { return }
            pendingDeleteItem = item
        }
        #else
        List {
            flowListContent(schedule)
        }
        #endif
    }

    @ViewBuilder
    private func flowListContent(_ schedule: RunSheetSchedule) -> some View {
        #if !os(macOS)
        if let error = engine.pcoLastError {
            Section {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppPalette.warning)
                    .font(.footnote)
            }
        }

        Section {
            RunSheetTimingToggles()
        } footer: {
            Text(RunSheetTimingToggles.explanation)
        }

        if engine.planItems.first?.pcoPlanId != nil {
            Section {
                PCOLiveSyncToggle()
            } footer: {
                Text(engine.isPCOLiveSyncEnabled
                    ? "This app controls Planning Center's Live view \u{2014} item navigation mirrors there too. Taking control can interrupt another controller."
                    : PCOLiveSyncToggle.explanation)
            }
        }

        if engine.eventTimes.count > 1 || engine.isRehearsalMode || !engine.rehearsalPlanTimes.isEmpty {
            Section {
                if engine.eventTimes.count > 1 {
                    LiveEventTimePicker()
                }
                RehearsalControl()
            }
        }
        #endif

        let sections = sheetSections
        ForEach(sections) { section in
            let visible = visibleItems(in: section)
            let isLast = section.id == sections.last?.id
            Section {
                let positions = RunSheetCardPosition.positions(for: visible)
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                    listRow(item, schedule: schedule, position: positions[index])
                }
                .onMove { offsets, destination in
                    moveItems(in: section, visible: visible, from: offsets, to: destination)
                }
                .onDelete { offsets in
                    if let index = offsets.first, visible.indices.contains(index) {
                        pendingDeleteItem = visible[index]
                    }
                }
            } header: {
                Text(sectionTitle(section))
            } footer: {
                if isLast {
                    StartNextEventButton()
                        .padding(.top, 8)
                }
            }
        }
    }

    private func listRow(_ item: PCOTimerItem, schedule: RunSheetSchedule, position: RunSheetCardPosition) -> some View {
        let isActive = engine.activeTimerItem?.id == item.id
        let isSelected = selectedItemId == item.id

        return RunSheetRow(
            item: item,
            entry: schedule.entry(forItemId: item.id),
            showsStart: schedule.plannedEnd != nil,
            isActive: isActive,
            isExpanded: expandedItemId == item.id,
            isCollapsed: collapsedHeaderIds.contains(item.id),
            subtotal: schedule.headerSubtotals[item.id],
            excludedLabel: engine.liveEventTimeLabel,
            knownCategories: knownNoteCategories,
            onToggleExpanded: { expandedItemId = expandedItemId == item.id ? nil : item.id },
            onToggleCollapsed: { toggleCollapsed(item.id) },
            onEdit: { editorMode = .edit(item) },
            onDelete: { pendingDeleteItem = item },
            onNewWaypoint: {
                newWaypointName = ""
                newWaypointTargetItemId = item.id
            }
        )
        .padding(.top, position.roundsTop ? RunSheetCardPosition.gap : 0)
        .listRowBackground(RunSheetRowBackground(item: item, activeItem: engine.activeTimerItem, isActive: isActive, isSelected: isSelected, position: position, timerColorHex: isActive ? engine.activeTimerItem.flatMap { engine.timerColorHex(for: $0) } : nil))
        #if !os(tvOS)
        .listRowSeparator(.hidden)
        #endif
        .rowActions {
            RunSheetItemActions(
                item: item,
                onEdit: { editorMode = .edit(item) },
                onDelete: { pendingDeleteItem = item },
                onNewWaypoint: {
                    newWaypointName = ""
                    newWaypointTargetItemId = item.id
                }
            )
        }
    }
}
