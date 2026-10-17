// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS)
import SwiftUI

struct RunSheetTableView: View {
    @EnvironmentObject var engine: CueEngine
    let schedule: RunSheetSchedule
    @Binding var selection: String?
    let knownCategories: [String]
    let excludedLabel: String?
    var compact = false
    let onEdit: (PCOTimerItem) -> Void
    let onDelete: (PCOTimerItem) -> Void
    let onNewWaypoint: (PCOTimerItem) -> Void

    @AppStorage(RunSheetTableColumn.storageKey) private var hiddenRaw = RunSheetTableColumn.defaultHiddenRaw
    @SceneStorage("runSheetCollapsedHeaders") private var collapsedRaw = ""
    @FocusState private var isFocused: Bool

    private static let rowHeight: CGFloat = 38
    private static let headerHeight: CGFloat = 34
    private static let cardRadius: CGFloat = 10
    private static let cardGap: CGFloat = 10
    private static let outerPadding: CGFloat = 12
    private static let rowPadding: CGFloat = 10
    private static let columnSpacing: CGFloat = 8

    private struct CardGroup: Identifiable {
        let id: String
        let header: PCOTimerItem?
        let items: [PCOTimerItem]
    }

    private var collapsedIds: Set<String> {
        Set(collapsedRaw.split(separator: ",").map(String.init))
    }

    private var hiddenIds: Set<String> {
        Set(hiddenRaw.split(separator: ",").map(String.init))
    }

    private var columns: [RunSheetTableColumn] {
        if compact {
            return RunSheetTableColumn.compact
        }
        let hidden = hiddenIds
        return RunSheetTableColumn.all(knownCategories).filter { !hidden.contains($0.id) }
    }

    private var groups: [CardGroup] {
        var result: [CardGroup] = []
        var header: PCOTimerItem?
        var items: [PCOTimerItem] = []
        func flush() {
            if header != nil || !items.isEmpty {
                result.append(CardGroup(id: header?.id ?? "untitled", header: header, items: items))
            }
        }
        for item in engine.planItems {
            if item.isHeader {
                flush()
                header = item
                items = []
            } else {
                items.append(item)
            }
        }
        flush()
        return result
    }

    private var navigableIds: [String] {
        let collapsed = collapsedIds
        var ids: [String] = []
        for group in groups {
            if let header = group.header { ids.append(header.id) }
            if group.header.map({ collapsed.contains($0.id) }) != true {
                ids.append(contentsOf: group.items.map(\.id))
            }
        }
        return ids
    }

    private var minContentWidth: CGFloat {
        let cols = columns
        let widths = cols.reduce(CGFloat(0)) { $0 + $1.minWidth }
        let spacing = Self.columnSpacing * CGFloat(max(cols.count - 1, 0))
        return widths + spacing + 2 * Self.rowPadding + 2 * Self.outerPadding
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: Self.cardGap, pinnedViews: [.sectionHeaders]) {
                            Section {
                                ForEach(groups) { group in
                                    card(group)
                                }
                            } header: {
                                columnHeader
                            }
                        }
                        .padding(.horizontal, Self.outerPadding)
                        .padding(.bottom, Self.outerPadding)
                    }
                    .focusable()
                    .focused($isFocused)
                    .focusEffectDisabled()
                    .onKeyPress(.upArrow) { moveSelection(-1, proxy: proxy) }
                    .onKeyPress(.downArrow) { moveSelection(1, proxy: proxy) }
                    .onKeyPress(.return) { performPrimaryAction() }
                }
                .frame(width: max(geometry.size.width, minContentWidth), height: geometry.size.height)
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: Self.columnSpacing) {
            ForEach(columns) { column in
                Text(column.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .modifier(RunSheetColumnFrame(column: column))
            }
        }
        .padding(.horizontal, Self.rowPadding)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .background(.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.sectionCardBorder).frame(height: 0.5)
        }
    }

    private func card(_ group: CardGroup) -> some View {
        let isCollapsed = group.header.map { collapsedIds.contains($0.id) } ?? false
        let shape = RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
        return VStack(spacing: 0) {
            if let header = group.header {
                headerRow(header, group: group, isCollapsed: isCollapsed)
            }
            if !isCollapsed {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    if group.header != nil || index > 0 {
                        separator
                    }
                    itemRow(item)
                }
            }
        }
        .background(AppPalette.sectionCard)
        .clipShape(shape)
        .overlay(shape.strokeBorder(AppPalette.sectionCardBorder, lineWidth: 0.75))
    }

    private var separator: some View {
        Rectangle().fill(AppPalette.sectionCardBorder).frame(height: 0.5)
    }

    private func headerRow(_ header: PCOTimerItem, group: CardGroup, isCollapsed: Bool) -> some View {
        let entry = schedule.entry(forItemId: header.id)
        let subtotal = schedule.headerSubtotals[header.id] ?? 0
        let count = group.items.count
        return HStack(spacing: 10) {
            Button {
                toggleCollapsed(header.id)
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppPalette.sectionHeaderText)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCollapsed ? "Expand section" : "Collapse section")
            .help(isCollapsed ? "Show the items in this section" : "Hide the items in this section")

            Text(header.title.uppercased())
                .font(.caption.weight(.heavy))
                .tracking(1.0)
                .foregroundStyle(AppPalette.sectionHeaderText)
                .lineLimit(1)

            (Text("\(count)").font(.clock(.caption)) + Text(count == 1 ? " item" : " items").font(.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let entry, !entry.isOmitted, let start = entry.plannedStart, subtotal > 0 {
                let end = start.addingTimeInterval(TimeInterval(subtotal))
                Text("\(engine.clockFormat.string(from: start)) \u{2013} \(engine.clockFormat.string(from: end))")
                    .font(.clock(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help("Planned start and end of this section")
            }

            Spacer(minLength: 8)

            if subtotal > 0 {
                Text(format(subtotal))
                    .font(.clock(.body))
                    .foregroundStyle(AppPalette.sectionHeaderText)
                    .help("Total length of the items in this section")
            }
        }
        .padding(.horizontal, Self.rowPadding)
        .frame(maxWidth: .infinity, minHeight: Self.headerHeight, alignment: .leading)
        .opacity(isDimmed(header) ? 0.5 : 1)
        .background(rowBackground(header, tint: AppPalette.sectionHeaderTint))
        .modifier(RunSheetRowInteraction(
            item: header,
            selection: $selection,
            focus: $isFocused,
            onPrimary: { primaryAction(header) },
            menu: { contextMenu(header) }
        ))
    }

    private func itemRow(_ item: PCOTimerItem) -> some View {
        HStack(spacing: Self.columnSpacing) {
            ForEach(columns) { column in
                cellContent(column, item)
                    .modifier(RunSheetColumnFrame(column: column))
            }
        }
        .padding(.horizontal, Self.rowPadding)
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
        .opacity(isDimmed(item) ? 0.5 : 1)
        .background(rowBackground(item, tint: nil))
        .modifier(RunSheetRowInteraction(
            item: item,
            selection: $selection,
            focus: $isFocused,
            onPrimary: { primaryAction(item) },
            menu: { contextMenu(item) }
        ))
    }

    @ViewBuilder
    private func rowBackground(_ item: PCOTimerItem, tint: Color?) -> some View {
        ZStack {
            if let tint { tint }
            if isActive(item) { AppPalette.rowActive }
            if selection == item.id { AppPalette.rowSelected }
        }
    }

    @ViewBuilder
    private func cellContent(_ column: RunSheetTableColumn, _ item: PCOTimerItem) -> some View {
        switch column.id {
        case "status": statusCell(item)
        case "start": startCell(item)
        case "title": itemCell(item, detailed: !compact)
        case "time": timeCell(item)
        case "drift": driftCell(item)
        case "key": keyCell(item)
        case "sequence": sequenceCell(item)
        case "number": cell(item, text: String(item.sequence), monospaced: true)
        case "type": cell(item, text: item.runSheetTypeLabel)
        case "bpm": cell(item, text: item.runSheetBPMText, monospaced: true)
        case "meter": cell(item, text: item.runSheetMeter)
        case "arrangement": cell(item, text: item.runSheetArrangementName)
        case "description": cell(item, text: item.runSheetDescription)
        case "pco-actual": cell(item, text: pcoActualText(item), monospaced: true)
        default: noteCell(item, text: item.notes[RunSheetTableColumn.category(fromNoteID: column.id)])
        }
    }

    private func toggleCollapsed(_ headerId: String) {
        var ids = collapsedIds
        if ids.contains(headerId) {
            ids.remove(headerId)
        } else {
            ids.insert(headerId)
        }
        let valid = Set(engine.planItems.map(\.id))
        collapsedRaw = ids.intersection(valid).sorted().joined(separator: ",")
    }

    private func moveSelection(_ delta: Int, proxy: ScrollViewProxy) -> KeyPress.Result {
        let ids = navigableIds
        guard !ids.isEmpty else { return .ignored }
        let next: String
        if let current = selection, let index = ids.firstIndex(of: current) {
            next = ids[min(max(index + delta, 0), ids.count - 1)]
        } else {
            next = delta > 0 ? ids[0] : ids[ids.count - 1]
        }
        selection = next
        proxy.scrollTo(next)
        return .handled
    }

    private func performPrimaryAction() -> KeyPress.Result {
        guard let id = selection, let item = engine.planItems.first(where: { $0.id == id }) else { return .ignored }
        primaryAction(item)
        return .handled
    }

    private func isActive(_ item: PCOTimerItem) -> Bool {
        engine.activeTimerItem?.id == item.id
    }

    private func isExcluded(_ item: PCOTimerItem) -> Bool {
        schedule.entry(forItemId: item.id)?.isExcluded ?? false
    }

    private func isSkipped(_ item: PCOTimerItem) -> Bool {
        schedule.entry(forItemId: item.id)?.isSkipped ?? false
    }

    private func isDimmed(_ item: PCOTimerItem) -> Bool {
        schedule.entry(forItemId: item.id)?.isOmitted ?? false
    }

    private func isCompleted(_ item: PCOTimerItem) -> Bool {
        if schedule.entry(forItemId: item.id)?.isActualComplete == true { return true }
        guard engine.activeTimerItem != nil, let index = engine.planItems.firstIndex(where: { $0.id == item.id }) else { return false }
        return index < engine.activeItemIndex
    }

    private func format(_ seconds: Int) -> String {
        TimeFormatting.string(forSeconds: seconds, threshold: engine.hourFormatThreshold)
    }

    private func pcoActualText(_ item: PCOTimerItem) -> String? {
        schedule.entry(forItemId: item.id)?.pcoActualLength.map(format)
    }

    private func styled<Content: View>(_ item: PCOTimerItem, @ViewBuilder _ content: () -> Content) -> some View {
        content()
    }

    private func statusCell(_ item: PCOTimerItem) -> some View {
        styled(item) {
            if item.isHeader {
                Color.clear
            } else if isSkipped(item) {
                Image(systemName: "forward.fill")
                    .foregroundStyle(.secondary)
                    .help("Skipped")
            } else if isActive(item) {
                Image(systemName: "play.fill")
                    .foregroundStyle(AppPalette.timerOnTime)
                    .help("Running now")
            } else if isCompleted(item) {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .help("Done")
            } else {
                Color.clear
            }
        }
        .font(.caption)
    }

    private func startCell(_ item: PCOTimerItem) -> some View {
        let entry = schedule.entry(forItemId: item.id)
        return styled(item) {
            VStack(alignment: .leading, spacing: 1) {
                if let entry, !entry.isOmitted, let planned = entry.plannedStart {
                    Text(engine.clockFormat.string(from: planned))
                        .font(.clock(.body))
                        .foregroundStyle(item.isHeader ? .secondary : .primary)
                    if !item.isHeader, let drift = entry.driftSeconds, abs(drift) >= RunSheetSchedule.driftThreshold,
                       let projected = entry.projectedStart {
                        Text(engine.clockFormat.string(from: projected))
                            .font(.caption.weight(.semibold))
                            .font(.clock(.body))
                            .foregroundStyle(drift > 0 ? AppPalette.driftLate : AppPalette.driftEarly)
                            .help(drift > 0 ? "Projected to start later than planned" : "Projected to start earlier than planned")
                    }
                }
            }
            .lineLimit(1)
        }
    }

    private func itemCell(_ item: PCOTimerItem, detailed: Bool) -> some View {
        let subtitle = detailed && !item.isHeader ? item.runSheetTableSubtitle : nil
        return styled(item) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    if !item.isHeader, let glyph = kindGlyph(item) {
                        Image(systemName: glyph)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(item.isHeader ? item.title.uppercased() : item.title)
                        .fontWeight(isActive(item) ? .semibold : (item.isHeader ? .heavy : .regular))
                        .foregroundStyle(item.isHeader ? .secondary : .primary)
                        .lineLimit(1)
                    if isExcluded(item), let excludedLabel {
                        Text("Not in \(excludedLabel)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppPalette.warning)
                            .lineLimit(1)
                    }
                    if isSkipped(item) {
                        Text("Skipped")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(subtitle)
                }
            }
        }
    }

    private func kindGlyph(_ item: PCOTimerItem) -> String? {
        switch item.runSheetKind {
        case .song: return "music.note"
        case .media: return "film"
        case .header, .item: return nil
        }
    }

    private func timeCell(_ item: PCOTimerItem) -> some View {
        let entry = schedule.entry(forItemId: item.id)
        let live = isActive(item) ? engine.activeTimerItem : nil
        return styled(item) {
            if item.isHeader {
                if let subtotal = schedule.headerSubtotals[item.id], subtotal > 0 {
                    Text(format(subtotal))
                        .font(.clock(.body))
                        .foregroundStyle(.secondary)
                        .help("Total length of the items in this section")
                }
            } else {
                let planned = entry?.length ?? item.lengthInSeconds
                let actual = entry?.actualLength
                VStack(alignment: .leading, spacing: 3) {
                    (Text(actual.map(format) ?? "\u{2014}")
                        .foregroundStyle(actual == nil ? Color.secondary : (entry?.isActualComplete == true ? Color.primary : Color.accentColor))
                        + Text(" / \(format(planned))").foregroundStyle(.secondary))
                        .font(.clock(.body))
                        .lineLimit(1)
                    if let live {
                        ProgressView(value: Double(min(live.elapsedSeconds, max(live.lengthInSeconds, 1))), total: Double(max(live.lengthInSeconds, 1)))
                            .progressViewStyle(.linear)
                            .tint(live.isOvertime ? AppPalette.warning : AppPalette.timerOnTime)
                    }
                }
                .help(timeHelp(entry))
            }
        }
    }

    private func timeHelp(_ entry: RunSheetSchedule.Entry?) -> String {
        var text = "Actual time spent / planned length"
        if let pco = entry?.pcoActualLength {
            text += "\nPlanning Center recorded \(format(pco)) for this item"
        }
        return text
    }

    private func driftCell(_ item: PCOTimerItem) -> some View {
        let delta = schedule.entry(forItemId: item.id)?.actualDeltaSeconds
        return styled(item) {
            if let delta, abs(delta) >= RunSheetActualStyle.lengthThreshold {
                let color = RunSheetActualStyle.color(forDelta: delta)
                Text(RunSheetActualStyle.signed(delta, threshold: engine.hourFormatThreshold))
                    .font(.clock(.callout, weight: .semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(RunSheetActualStyle.fillColor(forDelta: delta), in: Capsule())
                    .lineLimit(1)
                    .help(delta > 0 ? "Ran longer than planned" : "Ran shorter than planned")
            }
        }
    }

    private func keyCell(_ item: PCOTimerItem) -> some View {
        styled(item) {
            if let key = item.details?.displayKey {
                RunSheetKeyPill(key: key)
            }
        }
    }

    private func sequenceCell(_ item: PCOTimerItem) -> some View {
        let sequence = item.details?.effectiveSequenceShort ?? []
        let shown = Array(sequence.prefix(Self.sequenceChipLimit))
        let extra = sequence.count - shown.count
        return styled(item) {
            if !sequence.isEmpty {
                HStack(spacing: 3) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, section in
                        RunSheetSequenceChip(text: section)
                    }
                    if extra > 0 {
                        RunSheetSequenceChip(text: "+\(extra)")
                    }
                }
                .help(sequence.joined(separator: " "))
            }
        }
    }

    private static let sequenceChipLimit = 4

    private func cell(_ item: PCOTimerItem, text: String?, monospaced: Bool = false) -> some View {
        styled(item) {
            Text(text ?? "")
                .font(monospaced ? .clock(.body) : .body)
                .fontWeight(isActive(item) ? .semibold : (item.isHeader ? .heavy : .regular))
                .foregroundStyle(item.isHeader ? .secondary : .primary)
                .lineLimit(1)
        }
    }

    private func noteCell(_ item: PCOTimerItem, text: String?) -> some View {
        let value = text.flatMap { $0.isEmpty ? nil : $0 }
        return styled(item) {
            Text(value ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .help(value ?? "")
        }
    }


    @ViewBuilder
    private func contextMenu(_ item: PCOTimerItem) -> some View {
        RunSheetItemActions(
            item: item,
            onEdit: { onEdit(item) },
            onDelete: { onDelete(item) },
            onNewWaypoint: { onNewWaypoint(item) }
        )
    }

    private func primaryAction(_ item: PCOTimerItem) {
        if item.isHeader {
            onEdit(item)
        } else {
            engine.setActivePlanItem(id: item.id)
        }
    }
}

private struct RunSheetRowInteraction<Menu: View>: ViewModifier {
    let item: PCOTimerItem
    @Binding var selection: String?
    var focus: FocusState<Bool>.Binding
    let onPrimary: () -> Void
    @ViewBuilder let menu: () -> Menu

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                selection = item.id
                onPrimary()
            }
            .simultaneousGesture(TapGesture().onEnded {
                selection = item.id
                focus.wrappedValue = true
            })
            .contextMenu { menu() }
            .id(item.id)
    }
}

private struct RunSheetColumnFrame: ViewModifier {
    let column: RunSheetTableColumn

    func body(content: Content) -> some View {
        if let width = column.fixedWidth {
            content.frame(width: width, alignment: .leading)
        } else {
            content.frame(minWidth: column.minWidth, maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct RunSheetTableColumn: Identifiable {
    let id: String
    let title: String
    let isHiddenByDefault: Bool
    var fixedWidth: CGFloat?
    var flexMinWidth: CGFloat = 0

    var minWidth: CGFloat { fixedWidth ?? flexMinWidth }

    static let storageKey = "runSheetHiddenColumns"

    static var defaultHiddenRaw: String {
        fixed.filter(\.isHiddenByDefault).map(\.id).joined(separator: ",")
    }

    static func noteID(_ category: String) -> String { "note-\(category)" }

    static func category(fromNoteID id: String) -> String { String(id.dropFirst("note-".count)) }

    static let fixed: [RunSheetTableColumn] = [
        .init(id: "status", title: "Status", isHiddenByDefault: false, fixedWidth: 22),
        .init(id: "start", title: "Start", isHiddenByDefault: false, fixedWidth: 84),
        .init(id: "title", title: "Item", isHiddenByDefault: false, flexMinWidth: 160),
        .init(id: "time", title: "Time", isHiddenByDefault: false, fixedWidth: 112),
        .init(id: "drift", title: "Drift", isHiddenByDefault: false, fixedWidth: 64),
        .init(id: "key", title: "Key", isHiddenByDefault: false, fixedWidth: 52),
        .init(id: "sequence", title: "Sequence", isHiddenByDefault: false, fixedWidth: 200),
        .init(id: "number", title: "#", isHiddenByDefault: true, fixedWidth: 36),
        .init(id: "type", title: "Type", isHiddenByDefault: true, fixedWidth: 70),
        .init(id: "bpm", title: "BPM", isHiddenByDefault: true, fixedWidth: 48),
        .init(id: "meter", title: "Meter", isHiddenByDefault: true, fixedWidth: 48),
        .init(id: "arrangement", title: "Arrangement", isHiddenByDefault: true, fixedWidth: 110),
        .init(id: "description", title: "Description", isHiddenByDefault: true, fixedWidth: 220),
        .init(id: "pco-actual", title: "PCO Actual", isHiddenByDefault: true, fixedWidth: 76),
    ]

    static let compact: [RunSheetTableColumn] = {
        var columns = fixed.filter { ["status", "start", "title", "time", "drift"].contains($0.id) }
        if let index = columns.firstIndex(where: { $0.id == "title" }) { columns[index].flexMinWidth = 120 }
        return columns
    }()

    static func noteColumns(_ categories: [String]) -> [RunSheetTableColumn] {
        categories.map { .init(id: noteID($0), title: $0, isHiddenByDefault: false, flexMinWidth: 140) }
    }

    static func all(_ categories: [String]) -> [RunSheetTableColumn] {
        Array(fixed.prefix(7)) + noteColumns(categories) + Array(fixed.dropFirst(7))
    }
}

struct RunSheetColumnsMenu: View {
    @AppStorage(RunSheetTableColumn.storageKey) private var hiddenRaw = RunSheetTableColumn.defaultHiddenRaw
    let categories: [String]

    private var hiddenIds: Set<String> {
        Set(hiddenRaw.split(separator: ",").map(String.init))
    }

    var body: some View {
        Menu {
            Section("Columns") {
                ForEach(RunSheetTableColumn.fixed) { column in
                    toggle(column)
                }
            }
            let notes = RunSheetTableColumn.noteColumns(categories)
            if !notes.isEmpty {
                Section("Notes") {
                    ForEach(notes) { column in
                        toggle(column)
                    }
                }
            }
            Divider()
            Button("Show All Columns") {
                hiddenRaw = ""
            }
            Button("Reset Columns") {
                hiddenRaw = RunSheetTableColumn.defaultHiddenRaw
            }
        } label: {
            Label("Columns", systemImage: "tablecells.badge.ellipsis")
        }
        .help("Choose which columns the run sheet table shows")
    }

    private func toggle(_ column: RunSheetTableColumn) -> some View {
        Toggle(column.title, isOn: Binding(
            get: { !hiddenIds.contains(column.id) },
            set: { visible in
                var ids = hiddenIds
                if visible { ids.remove(column.id) } else { ids.insert(column.id) }
                hiddenRaw = ids.sorted().joined(separator: ",")
            }
        ))
    }
}

extension PCOTimerItem {
    fileprivate var runSheetTableSubtitle: String? {
        switch runSheetKind {
        case .song:
            let parts = [runSheetAuthor, runSheetBPMText.map { "\($0) BPM" }, runSheetMeter, runSheetArrangementName].compactMap { $0 }
            return parts.isEmpty ? runSheetDescription : parts.joined(separator: " \u{00B7} ")
        case .media, .item:
            return runSheetDescription
        case .header:
            return nil
        }
    }
}
#endif
