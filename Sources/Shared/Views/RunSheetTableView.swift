// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS)
import SwiftUI

struct RunSheetTableView: View {
    @EnvironmentObject var engine: CueEngine
    let schedule: RunSheetSchedule
    @Binding var selection: String?
    @Binding var customization: TableColumnCustomization<PCOTimerItem>
    let knownCategories: [String]
    let excludedLabel: String?
    var compact = false
    let onEdit: (PCOTimerItem) -> Void
    let onDelete: (PCOTimerItem) -> Void
    let onNewWaypoint: (PCOTimerItem) -> Void

    private static let rowHeight: CGFloat = 38

    var body: some View {
        if compact {
            compactTable
        } else if #available(macOS 14.4, *) {
            table(withNoteColumns: true)
        } else {
            table(withNoteColumns: false)
        }
    }

    private var compactTable: some View {
        Table(engine.planItems, selection: $selection) {
            statusColumn
            startColumn
            TableColumn("Item") { item in
                itemCell(item, detailed: false)
            }
            .width(min: 120, ideal: 220)
            timeColumn
            driftColumn
        }
        .contextMenu(forSelectionType: String.self, menu: contextMenu, primaryAction: primaryAction)
    }

    @ViewBuilder
    private func table(withNoteColumns: Bool) -> some View {
        if withNoteColumns, #available(macOS 14.4, *) {
            Table(engine.planItems, selection: $selection, columnCustomization: $customization) {
                primaryColumns
                TableColumnForEach(knownCategories, id: \.self) { category in
                    TableColumn(category) { item in
                        noteCell(item, text: item.notes[category])
                    }
                    .width(min: 80, ideal: 180)
                    .customizationID(RunSheetTableColumn.noteID(category))
                }
                optionalColumns
            }
            .contextMenu(forSelectionType: String.self, menu: contextMenu, primaryAction: primaryAction)
        } else {
            Table(engine.planItems, selection: $selection, columnCustomization: $customization) {
                primaryColumns
                TableColumn("Notes") { item in
                    noteCell(item, text: item.notes.keys.sorted().compactMap { key in
                        item.notes[key].flatMap { $0.isEmpty ? nil : "\(key): \($0)" }
                    }.joined(separator: " \u{2022} "))
                }
                .width(min: 100, ideal: 240)
                .customizationID(RunSheetTableColumn.combinedNotesID)
                optionalColumns
            }
            .contextMenu(forSelectionType: String.self, menu: contextMenu, primaryAction: primaryAction)
        }
    }

    private var statusColumn: some TableColumnContent<PCOTimerItem, Never> {
        TableColumn("") { item in
            statusCell(item)
        }
        .width(22)
        .customizationID("status")
    }

    private var startColumn: some TableColumnContent<PCOTimerItem, Never> {
        TableColumn("Start") { item in
            startCell(item)
        }
        .width(min: 64, ideal: 84, max: 130)
        .customizationID("start")
    }

    private var timeColumn: some TableColumnContent<PCOTimerItem, Never> {
        TableColumn("Time") { item in
            timeCell(item)
        }
        .width(min: 76, ideal: 96, max: 140)
        .customizationID("time")
    }

    private var driftColumn: some TableColumnContent<PCOTimerItem, Never> {
        TableColumn("Drift") { item in
            driftCell(item)
        }
        .width(min: 52, ideal: 64, max: 100)
        .customizationID("drift")
    }

    @TableColumnBuilder<PCOTimerItem, Never>
    private var primaryColumns: some TableColumnContent<PCOTimerItem, Never> {
        statusColumn
        startColumn

        TableColumn("Item") { item in
            itemCell(item, detailed: true)
        }
        .width(min: 160, ideal: 280)
        .customizationID("title")

        timeColumn
        driftColumn

        TableColumn("Key") { item in
            keyCell(item)
        }
        .width(min: 40, ideal: 52, max: 80)
        .customizationID("key")

        TableColumn("Sequence") { item in
            sequenceCell(item)
        }
        .width(min: 100, ideal: 220)
        .customizationID("sequence")
    }

    @TableColumnBuilder<PCOTimerItem, Never>
    private var optionalColumns: some TableColumnContent<PCOTimerItem, Never> {
        TableColumn("#") { item in
            cell(item, text: item.isHeader ? nil : String(item.sequence), monospaced: true)
        }
        .width(min: 28, ideal: 36, max: 60)
        .customizationID("number")
        .defaultVisibility(.hidden)

        TableColumn("Type") { item in
            cell(item, text: item.isHeader ? nil : item.runSheetTypeLabel)
        }
        .width(min: 50, ideal: 70, max: 140)
        .customizationID("type")
        .defaultVisibility(.hidden)

        TableColumn("BPM") { item in
            cell(item, text: item.runSheetBPMText, monospaced: true)
        }
        .width(min: 36, ideal: 48, max: 80)
        .customizationID("bpm")
        .defaultVisibility(.hidden)

        TableColumn("Meter") { item in
            cell(item, text: item.runSheetMeter)
        }
        .width(min: 36, ideal: 48, max: 80)
        .customizationID("meter")
        .defaultVisibility(.hidden)

        TableColumn("Arrangement") { item in
            cell(item, text: item.runSheetArrangementName)
        }
        .width(min: 70, ideal: 110)
        .customizationID("arrangement")
        .defaultVisibility(.hidden)

        TableColumn("Description") { item in
            cell(item, text: item.runSheetDescription)
        }
        .width(min: 100, ideal: 220)
        .customizationID("description")
        .defaultVisibility(.hidden)

        TableColumn("PCO Actual") { item in
            cell(item, text: pcoActualText(item), monospaced: true)
        }
        .width(min: 56, ideal: 72, max: 110)
        .customizationID("pco-actual")
        .defaultVisibility(.hidden)
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
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight, alignment: .leading)
            .modifier(RunSheetCellStyle(isActive: isActive(item), isExcluded: isDimmed(item)))
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
                    .foregroundStyle(.green)
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
                        .monospacedDigit()
                        .foregroundStyle(item.isHeader ? .secondary : .primary)
                    if !item.isHeader, let drift = entry.driftSeconds, abs(drift) >= RunSheetSchedule.driftThreshold,
                       let projected = entry.projectedStart {
                        Text(engine.clockFormat.string(from: projected))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(drift > 0 ? Color.orange : Color.green)
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
                            .foregroundStyle(.orange)
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
                        .monospacedDigit()
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
                        .monospacedDigit()
                        .lineLimit(1)
                    if let live {
                        ProgressView(value: Double(min(live.elapsedSeconds, max(live.lengthInSeconds, 1))), total: Double(max(live.lengthInSeconds, 1)))
                            .progressViewStyle(.linear)
                            .tint(live.isOvertime ? .orange : .green)
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
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.16), in: Capsule())
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
                .font(monospaced ? .body.monospacedDigit() : .body)
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
    private func contextMenu(_ ids: Set<String>) -> some View {
        if let id = ids.first, let item = engine.planItems.first(where: { $0.id == id }) {
            RunSheetItemActions(
                item: item,
                onEdit: { onEdit(item) },
                onDelete: { onDelete(item) },
                onNewWaypoint: { onNewWaypoint(item) }
            )
        }
    }

    private func primaryAction(_ ids: Set<String>) {
        guard let id = ids.first, let item = engine.planItems.first(where: { $0.id == id }) else { return }
        if item.isHeader {
            onEdit(item)
        } else {
            engine.setActivePlanItem(id: item.id)
        }
    }
}

struct RunSheetTableColumn: Identifiable {
    let id: String
    let title: String
    let isHiddenByDefault: Bool

    static let combinedNotesID = "notes"

    static func noteID(_ category: String) -> String { "note-\(category)" }

    static let fixed: [RunSheetTableColumn] = [
        .init(id: "status", title: "Status", isHiddenByDefault: false),
        .init(id: "start", title: "Start", isHiddenByDefault: false),
        .init(id: "title", title: "Item", isHiddenByDefault: false),
        .init(id: "time", title: "Time", isHiddenByDefault: false),
        .init(id: "drift", title: "Drift", isHiddenByDefault: false),
        .init(id: "key", title: "Key", isHiddenByDefault: false),
        .init(id: "sequence", title: "Sequence", isHiddenByDefault: false),
        .init(id: "number", title: "#", isHiddenByDefault: true),
        .init(id: "type", title: "Type", isHiddenByDefault: true),
        .init(id: "bpm", title: "BPM", isHiddenByDefault: true),
        .init(id: "meter", title: "Meter", isHiddenByDefault: true),
        .init(id: "arrangement", title: "Arrangement", isHiddenByDefault: true),
        .init(id: "description", title: "Description", isHiddenByDefault: true),
        .init(id: "pco-actual", title: "PCO Actual", isHiddenByDefault: true),
    ]

    static func noteColumns(_ categories: [String]) -> [RunSheetTableColumn] {
        if #available(macOS 14.4, *) {
            return categories.map { .init(id: noteID($0), title: $0, isHiddenByDefault: false) }
        }
        return [.init(id: combinedNotesID, title: "Notes", isHiddenByDefault: false)]
    }
}

struct RunSheetColumnsMenu: View {
    @Binding var customization: TableColumnCustomization<PCOTimerItem>
    let categories: [String]

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
                for column in RunSheetTableColumn.fixed + notes { customization[visibility: column.id] = .visible }
            }
            Button("Reset Columns") {
                customization = TableColumnCustomization<PCOTimerItem>()
            }
        } label: {
            Label("Columns", systemImage: "tablecells.badge.ellipsis")
        }
        .help("Choose which columns the run sheet table shows")
    }

    private func toggle(_ column: RunSheetTableColumn) -> some View {
        Toggle(column.title, isOn: Binding(
            get: { isVisible(column) },
            set: { customization[visibility: column.id] = $0 ? .visible : .hidden }
        ))
    }

    private func isVisible(_ column: RunSheetTableColumn) -> Bool {
        switch customization[visibility: column.id] {
        case .visible: return true
        case .hidden: return false
        default: return !column.isHiddenByDefault
        }
    }
}

private struct RunSheetCellStyle: ViewModifier {
    let isActive: Bool
    let isExcluded: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isExcluded ? 0.5 : 1)
            .background {
                if isActive {
                    Color.green.opacity(0.14)
                        .padding(.horizontal, -12)
                        .padding(.vertical, -8)
                }
            }
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
