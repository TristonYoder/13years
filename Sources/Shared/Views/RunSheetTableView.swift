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

    @SceneStorage("runSheetCollapsedHeaders") private var collapsedRaw = ""
    @FocusState private var isFocused: Bool
    @State private var columnDrag: (id: String, startWidth: CGFloat, width: CGFloat)?

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

    private var columns: [RunSheetTableColumn] {
        if compact {
            return RunSheetTableColumn.compact
        }
        let layout = engine.runSheetLayout
        let hidden = layout.hiddenSet
        return RunSheetTableColumn.ordered(knownCategories, layout: layout).filter { !hidden.contains($0.id) && !$0.isItemPart }
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
        let widths = cols.reduce(CGFloat(0)) { $0 + baseWidth($1) }
        let spacing = Self.columnSpacing * CGFloat(max(cols.count - 1, 0))
        return widths + spacing + 2 * Self.rowPadding + 2 * Self.outerPadding
    }

    private static let minimumColumnWidth: CGFloat = 24

    private static var verticalScrollerWidth: CGFloat {
        NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            : 0
    }

    private func userWidth(_ column: RunSheetTableColumn) -> CGFloat? {
        if let drag = columnDrag, drag.id == column.id { return drag.width }
        return engine.runSheetColumnWidths[column.id].map { max(Self.minimumColumnWidth, CGFloat($0)) }
    }

    private func baseWidth(_ column: RunSheetTableColumn) -> CGFloat {
        userWidth(column) ?? column.minWidth
    }

    private func resolvedWidths(for totalWidth: CGFloat) -> [String: CGFloat] {
        let cols = columns
        let fixedTotal = cols.reduce(CGFloat(0)) { $0 + baseWidth($1) }
        let chrome = 2 * Self.rowPadding + 2 * Self.outerPadding + Self.columnSpacing * CGFloat(max(cols.count - 1, 0))
        let available = totalWidth - chrome
        let extra = max(0, available - fixedTotal)
        let weights = cols.map { column -> CGFloat in
            guard column.fixedWidth == nil, userWidth(column) == nil else { return 0 }
            return column.id == "title" ? 2 : 1
        }
        let totalWeight = weights.reduce(0, +)
        var result: [String: CGFloat] = [:]
        for (column, weight) in zip(cols, weights) {
            let share = totalWeight > 0 ? extra * weight / totalWeight : 0
            result[column.id] = (baseWidth(column) + share).rounded(.down)
        }
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            let viewportWidth = max(0, geometry.size.width - Self.verticalScrollerWidth)
            let widths = resolvedWidths(for: viewportWidth)
            let rowWidth = self.rowWidth(widths)
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: Self.cardGap, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(groups) { group in
                                card(group, widths: widths, rowWidth: rowWidth)
                            }
                        } header: {
                            columnHeader(widths)
                                .frame(width: rowWidth, alignment: .leading)
                                .padding(.horizontal, Self.outerPadding)
                                .background(.background)
                        }
                    }
                    .padding(.bottom, Self.outerPadding)
                    .frame(minWidth: viewportWidth, alignment: .leading)
                }
                .scrollIndicators(rowWidth + 2 * Self.outerPadding > viewportWidth + 0.5 ? .visible : .hidden, axes: .horizontal)
                .scrollIndicators(.automatic, axes: .vertical)
                .focusable()
                .focused($isFocused)
                .focusEffectDisabled()
                .onKeyPress(.upArrow) { moveSelection(-1, proxy: proxy) }
                .onKeyPress(.downArrow) { moveSelection(1, proxy: proxy) }
                .onKeyPress(.return) { performPrimaryAction() }
            }
        }
    }

    private func columnHeader(_ widths: [String: CGFloat]) -> some View {
        HStack(spacing: Self.columnSpacing) {
            ForEach(columns) { column in
                Text(column.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .modifier(RunSheetColumnFrame(width: widths[column.id] ?? column.minWidth))
                    .contentShape(Rectangle())
                    .modifier(RunSheetColumnReorder(
                        column: column,
                        enabled: !compact,
                        onMove: { moveColumn($0, to: column.id) }
                    ))
                    .overlay(alignment: .trailing) {
                        resizeHandle(column, currentWidth: widths[column.id] ?? column.minWidth)
                    }
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

    private func moveColumn(_ id: String, to target: String) {
        let current = RunSheetTableColumn.ordered(knownCategories, layout: engine.runSheetLayout).map(\.id)
        let moved = RunSheetTableColumn.reordered(current, moving: id, to: target)
        guard moved != current else { return }
        engine.runSheetLayout.columnOrder = moved
    }

    private func resizeHandle(_ column: RunSheetTableColumn, currentWidth: CGFloat) -> some View {
        Rectangle()
            .fill(columnDrag?.id == column.id ? AppPalette.sectionCardBorder : Color.clear)
            .frame(width: 1)
            .padding(.horizontal, 3)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .offset(x: (Self.columnSpacing / 2) + 3)
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = columnDrag?.startWidth ?? currentWidth
                        columnDrag = (column.id, start, max(Self.minimumColumnWidth, (start + value.translation.width).rounded()))
                    }
                    .onEnded { _ in
                        if let drag = columnDrag {
                            engine.runSheetColumnWidths[drag.id] = Double(drag.width)
                        }
                        columnDrag = nil
                    }
            )
            .onTapGesture(count: 2) {
                engine.runSheetColumnWidths[column.id] = nil
            }
            .help("Drag to resize this column. Double-click to reset it.")
    }

    private func rowWidth(_ widths: [String: CGFloat]) -> CGFloat {
        let cols = columns
        let total = cols.reduce(CGFloat(0)) { $0 + (widths[$1.id] ?? $1.minWidth) }
        return total + Self.columnSpacing * CGFloat(max(cols.count - 1, 0)) + 2 * Self.rowPadding
    }

    private func card(_ group: CardGroup, widths: [String: CGFloat], rowWidth: CGFloat) -> some View {
        let isCollapsed = group.header.map { collapsedIds.contains($0.id) } ?? false
        let shape = RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            if let header = group.header {
                headerRow(header, group: group, isCollapsed: isCollapsed)
                    .frame(width: rowWidth, alignment: .leading)
            }
            if !isCollapsed {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    if group.header != nil || index > 0 {
                        separator
                    }
                    itemRow(item, widths: widths)
                        .frame(width: rowWidth, alignment: .leading)
                }
            }
        }
        .frame(width: rowWidth, alignment: .leading)
        .background(AppPalette.sectionCard)
        .clipShape(shape)
        .overlay(shape.strokeBorder(AppPalette.sectionCardBorder, lineWidth: 0.75))
        .padding(.horizontal, Self.outerPadding)
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
        .clipped()
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

    private func itemRow(_ item: PCOTimerItem, widths: [String: CGFloat]) -> some View {
        HStack(spacing: Self.columnSpacing) {
            ForEach(columns) { column in
                cellContent(column, item)
                    .modifier(RunSheetColumnFrame(width: widths[column.id] ?? column.minWidth))
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
        let on = engine.runSheetLayout.highlightedSet.contains(column.id)
        switch column.id {
        case "status": statusCell(item)
        case "start": startCell(item).markerHighlight(on)
        case "title": itemCell(item, detailed: !compact).markerHighlight(on)
        case "time": timeCell(item).markerHighlight(on)
        case "drift": driftCell(item).markerHighlight(on)
        case "key": keyCell(item).markerHighlight(on)
        case "sequence": sequenceCell(item).markerHighlight(on)
        case "number": cell(item, text: String(item.sequence), monospaced: true, highlight: on)
        case "type": cell(item, text: item.runSheetTypeLabel, highlight: on)
        case "bpm": cell(item, text: item.runSheetBPMText, monospaced: true, highlight: on)
        case "meter": cell(item, text: item.runSheetMeter, highlight: on)
        case "arrangement": cell(item, text: item.runSheetArrangementName, highlight: on)
        case "description": cell(item, text: item.runSheetDescription, highlight: on)
        case "pco-actual": cell(item, text: pcoActualText(item), monospaced: true, highlight: on)
        default: noteCell(item, text: item.notes[RunSheetTableColumn.category(fromNoteID: column.id)], highlight: on)
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
        let hidden = engine.runSheetLayout.hiddenSet
        let leaders = detailed && !item.isHeader ? item.runSheetLeaders : []
        let showsPhoto = !hidden.contains("leaderPhoto") && !leaders.isEmpty
        let showsLeader = !hidden.contains("leader") && !leaders.isEmpty
        return styled(item) {
            HStack(spacing: 8) {
                if showsPhoto, let first = leaders.first {
                    LeaderAvatar(leader: first, size: Self.rowHeight - 6)
                        .help(leaders.map(\.name).joined(separator: ", "))
                }
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
                            .layoutPriority(1)
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
                    if showsLeader {
                        (Text("Leader: ").foregroundStyle(.secondary) + Text(leaders.map(\.name).joined(separator: ", ")))
                            .font(.caption)
                            .lineLimit(1)
                    }
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
                let hasStarted = live != nil || isCompleted(item) || actual != nil
                VStack(alignment: .leading, spacing: 3) {
                    Group {
                        if hasStarted {
                            Text(format(live?.elapsedSeconds ?? actual ?? 0))
                                .foregroundStyle(live != nil ? Color.accentColor : Color.primary)
                                + Text(" / \(format(planned))").foregroundStyle(.secondary)
                        } else {
                            Text(format(planned))
                                .foregroundStyle(Color.primary)
                        }
                    }
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
        return styled(item) {
            if !sequence.isEmpty {
                RunSheetFittingSequence(sequence: sequence)
            }
        }
    }

    private func cell(_ item: PCOTimerItem, text: String?, monospaced: Bool = false, highlight: Bool = false) -> some View {
        styled(item) {
            Text(text ?? "")
                .font(monospaced ? .clock(.body) : .body)
                .fontWeight(isActive(item) ? .semibold : (item.isHeader ? .heavy : .regular))
                .foregroundStyle(item.isHeader ? .secondary : .primary)
                .lineLimit(1)
                .markerHighlight(highlight && !(text ?? "").isEmpty)
        }
    }

    private func noteCell(_ item: PCOTimerItem, text: String?, highlight: Bool = false) -> some View {
        let value = text.flatMap { $0.isEmpty ? nil : $0 }
        return styled(item) {
            Text(value ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .markerHighlight(highlight && value != nil)
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
    let width: CGFloat

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            Color.clear.frame(width: width, height: 0)
        }
        .frame(width: width, alignment: .leading)
        .clipped()
    }
}

struct RunSheetTableColumn: Identifiable {
    let id: String
    let title: String
    var fixedWidth: CGFloat?
    var flexMinWidth: CGFloat = 0
    var isItemPart = false

    var minWidth: CGFloat { fixedWidth ?? flexMinWidth }

    var isNote: Bool { id.hasPrefix("note-") }

    var pickerTitle: String { title.isEmpty ? "Status" : title }

    static func noteID(_ category: String) -> String { RunSheetLayoutSettings.noteColumnId(category) }

    static func category(fromNoteID id: String) -> String { String(id.dropFirst("note-".count)) }

    static let fixed: [RunSheetTableColumn] = [
        .init(id: "status", title: "", fixedWidth: 22),
        .init(id: "start", title: "Start", fixedWidth: 84),
        .init(id: "title", title: "Item", flexMinWidth: 160),
        .init(id: "leaderPhoto", title: "Leader photo", isItemPart: true),
        .init(id: "leader", title: "Leader", isItemPart: true),
        .init(id: "time", title: "Time", fixedWidth: 112),
        .init(id: "drift", title: "Drift", fixedWidth: 64),
        .init(id: "key", title: "Key", fixedWidth: 52),
        .init(id: "sequence", title: "Sequence", fixedWidth: 200),
        .init(id: "number", title: "#", fixedWidth: 36),
        .init(id: "type", title: "Type", fixedWidth: 70),
        .init(id: "bpm", title: "BPM", fixedWidth: 48),
        .init(id: "meter", title: "Meter", fixedWidth: 48),
        .init(id: "arrangement", title: "Arrangement", fixedWidth: 110),
        .init(id: "description", title: "Description", fixedWidth: 220),
        .init(id: "pco-actual", title: "PCO Actual", fixedWidth: 76),
    ]

    static let compact: [RunSheetTableColumn] = {
        var columns = fixed.filter { ["status", "start", "title", "time", "drift"].contains($0.id) }
        if let index = columns.firstIndex(where: { $0.id == "title" }) { columns[index].flexMinWidth = 120 }
        return columns
    }()

    static func noteColumns(_ categories: [String]) -> [RunSheetTableColumn] {
        categories.map { .init(id: noteID($0), title: $0, flexMinWidth: 140) }
    }

    static func all(_ categories: [String]) -> [RunSheetTableColumn] {
        Array(fixed.prefix(9)) + noteColumns(categories) + Array(fixed.dropFirst(9))
    }

    static func ordered(_ categories: [String], layout: RunSheetLayoutSettings) -> [RunSheetTableColumn] {
        let available = all(categories)
        let byId = Dictionary(available.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return layout.orderedIds(defaultOrder: available.map(\.id)).compactMap { byId[$0] }
    }

    static func reordered(_ ids: [String], moving id: String, to target: String) -> [String] {
        guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return ids }
        var result = ids
        result.remove(at: from)
        result.insert(id, at: to)
        return result
    }
}

struct RunSheetColumnsMenu: View {
    @EnvironmentObject var engine: CueEngine
    let categories: [String]

    @State private var isPresented = false

    private var ordered: [RunSheetTableColumn] {
        RunSheetTableColumn.ordered(categories, layout: engine.runSheetLayout).filter { !$0.isItemPart }
    }

    private static let itemParts: [(id: String, title: String)] = [("leaderPhoto", "Photo"), ("leader", "Leader")]

    var body: some View {
        Button(action: { isPresented.toggle() }) {
            Label("Columns", systemImage: "tablecells.badge.ellipsis")
        }
        .help("Choose which columns the run sheet table shows, and their order")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            picker
        }
    }

    private var picker: some View {
        let columns = ordered
        return VStack(alignment: .leading, spacing: 10) {
            Text("Drag to reorder")
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(columns) { column in
                    row(column)
                }
                .onMove(perform: move)
            }
            .listStyle(.plain)
            .frame(height: min(CGFloat(columns.count) * 28 + 8, 380))
            Divider()
            HStack {
                Button("Show All") { engine.runSheetLayout.hiddenColumns = [] }
                Button("Reset") {
                    engine.runSheetLayout.columnOrder = nil
                    engine.runSheetLayout.hiddenColumns = nil
                    engine.runSheetLayout.columnWidths = nil
                    engine.runSheetLayout.highlightedColumns = nil
                }
                .help("Restore the default column order, visibility, widths and highlights")
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func row(_ column: RunSheetTableColumn) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
            visibilityToggle(column.pickerTitle, id: column.id)
            if column.id == "title" {
                ForEach(Self.itemParts, id: \.id) { part in
                    visibilityToggle(part.title, id: part.id)
                        .font(.caption)
                        .help("Show the leader's \(part.title.lowercased()) in the Item column and the Now and Next cards")
                }
            }
            Spacer(minLength: 0)
            if column.id != "status" {
                highlightButton(column)
            }
            if column.isNote {
                Text("Note")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 24)
    }

    private func visibilityToggle(_ title: String, id: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { !engine.runSheetLayout.hiddenSet.contains(id) },
            set: { visible in
                var ids = engine.runSheetLayout.hiddenSet
                if visible { ids.remove(id) } else { ids.insert(id) }
                engine.runSheetLayout.hiddenColumns = ids.sorted()
            }
        ))
        .toggleStyle(.checkbox)
    }

    private func highlightButton(_ column: RunSheetTableColumn) -> some View {
        let on = engine.runSheetLayout.highlightedSet.contains(column.id)
        return Button {
            var ids = engine.runSheetLayout.highlightedSet
            if on { ids.remove(column.id) } else { ids.insert(column.id) }
            engine.runSheetLayout.highlightedColumns = ids.isEmpty ? nil : ids.sorted()
        } label: {
            Image(systemName: "highlighter")
                .font(.caption)
                .foregroundStyle(on ? Color.primary : Color.secondary)
                .frame(width: 22, height: 18)
                .background(on ? AppPalette.highlightMarker : Color.clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(on ? "Stop highlighting this column" : "Highlight this column's values everywhere they appear")
        .accessibilityLabel("Highlight \(column.pickerTitle)")
        .accessibilityValue(on ? "On" : "Off")
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = ordered.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        engine.runSheetLayout.columnOrder = ids + Self.itemParts.map(\.id)
    }
}

struct RunSheetFittingSequence: View {
    let sequence: [String]
    @State private var isShowingAll = false

    private static let maxCandidates = 24

    var body: some View {
        let count = sequence.count
        let lowest = max(1, count - Self.maxCandidates)
        ViewThatFits(in: .horizontal) {
            chips(count)
            ForEach(Array(stride(from: count - 1, through: lowest, by: -1)), id: \.self) { shown in
                chips(shown)
            }
            overflowButton(count)
        }
        .help(sequence.joined(separator: " "))
    }

    private func chips(_ shown: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(sequence.prefix(shown).enumerated()), id: \.offset) { _, section in
                RunSheetSequenceChip(text: section)
            }
            if shown < sequence.count {
                overflowButton(sequence.count - shown)
            }
        }
        .fixedSize()
    }

    private func overflowButton(_ hidden: Int) -> some View {
        Button {
            isShowingAll.toggle()
        } label: {
            Text("+\(hidden)")
                .font(.clock(.caption2, weight: .semibold))
                .foregroundStyle(AppPalette.info)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(AppPalette.surfaceMuted, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show the full sequence")
        .popover(isPresented: $isShowingAll, arrowEdge: .bottom) {
            RunSheetFlowLayout(spacing: 4) {
                ForEach(Array(sequence.enumerated()), id: \.offset) { _, section in
                    RunSheetSequenceChip(text: section)
                }
            }
            .padding(12)
            .frame(width: 260)
        }
    }
}

private struct RunSheetColumnReorder: ViewModifier {
    let column: RunSheetTableColumn
    let enabled: Bool
    let onMove: (String) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .draggable(column.id) {
                    Text(column.pickerTitle)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppPalette.surfaceMuted, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .dropDestination(for: String.self) { ids, _ in
                    guard let id = ids.first else { return false }
                    onMove(id)
                    return true
                }
        } else {
            content
        }
    }
}
#endif
