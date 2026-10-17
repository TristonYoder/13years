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
    let onEdit: (PCOTimerItem) -> Void
    let onDelete: (PCOTimerItem) -> Void
    let onNewWaypoint: (PCOTimerItem) -> Void

    @SceneStorage("runSheetTableColumns") private var customization = TableColumnCustomization<PCOTimerItem>()

    var body: some View {
        if #available(macOS 14.4, *) {
            table(withNoteColumns: true)
        } else {
            table(withNoteColumns: false)
        }
    }

    @ViewBuilder
    private func table(withNoteColumns: Bool) -> some View {
        if withNoteColumns, #available(macOS 14.4, *) {
            Table(engine.planItems, selection: $selection, columnCustomization: $customization) {
                leadingColumns
                detailColumns
                TableColumnForEach(knownCategories, id: \.self) { category in
                    TableColumn(category) { item in
                        cell(item, text: item.notes[category])
                    }
                    .customizationID("note-\(category)")
                    .defaultVisibility(.hidden)
                }
            }
            .contextMenu(forSelectionType: String.self, menu: contextMenu, primaryAction: primaryAction)
        } else {
            Table(engine.planItems, selection: $selection, columnCustomization: $customization) {
                leadingColumns
                detailColumns
                TableColumn("Notes") { item in
                    cell(item, text: item.notes.keys.sorted().compactMap { key in
                        item.notes[key].flatMap { $0.isEmpty ? nil : "\(key): \($0)" }
                    }.joined(separator: " \u{2022} "))
                }
                .customizationID("notes")
                .defaultVisibility(.hidden)
            }
            .contextMenu(forSelectionType: String.self, menu: contextMenu, primaryAction: primaryAction)
        }
    }

    @TableColumnBuilder<PCOTimerItem, Never>
    private var leadingColumns: some TableColumnContent<PCOTimerItem, Never> {
        TableColumn("#") { item in
            cell(item, text: item.isHeader ? nil : String(item.sequence), monospaced: true)
        }
        .width(min: 28, ideal: 36, max: 60)
        .customizationID("number")

        TableColumn("Start") { item in
            startCell(item)
        }
        .width(min: 64, ideal: 84, max: 130)
        .customizationID("start")

        TableColumn("Length") { item in
            cell(item, text: lengthText(item), monospaced: true)
        }
        .width(min: 48, ideal: 60, max: 100)
        .customizationID("length")

        TableColumn("Title") { item in
            titleCell(item)
        }
        .width(min: 140, ideal: 260)
        .customizationID("title")

        TableColumn("Type") { item in
            cell(item, text: item.isHeader ? nil : item.runSheetTypeLabel)
        }
        .width(min: 50, ideal: 70, max: 140)
        .customizationID("type")
    }

    @TableColumnBuilder<PCOTimerItem, Never>
    private var detailColumns: some TableColumnContent<PCOTimerItem, Never> {
        TableColumn("Key") { item in
            cell(item, text: item.details?.displayKey)
        }
        .width(min: 32, ideal: 44, max: 80)
        .customizationID("key")

        TableColumn("BPM") { item in
            cell(item, text: item.runSheetBPMText, monospaced: true)
        }
        .width(min: 36, ideal: 48, max: 80)
        .customizationID("bpm")

        TableColumn("Meter") { item in
            cell(item, text: item.runSheetMeter)
        }
        .width(min: 36, ideal: 48, max: 80)
        .customizationID("meter")

        TableColumn("Arrangement") { item in
            cell(item, text: item.runSheetArrangementName)
        }
        .width(min: 70, ideal: 110)
        .customizationID("arrangement")
        .defaultVisibility(.hidden)

        TableColumn("Sequence") { item in
            cell(item, text: item.runSheetSequenceText)
        }
        .width(min: 80, ideal: 180)
        .customizationID("sequence")

        TableColumn("Description") { item in
            cell(item, text: item.runSheetDescription)
        }
        .width(min: 100, ideal: 220)
        .customizationID("description")
        .defaultVisibility(.hidden)
    }

    private func isActive(_ item: PCOTimerItem) -> Bool {
        engine.activeTimerItem?.id == item.id
    }

    private func isExcluded(_ item: PCOTimerItem) -> Bool {
        schedule.entry(forItemId: item.id)?.isExcluded ?? false
    }

    private func lengthText(_ item: PCOTimerItem) -> String? {
        if item.isHeader {
            guard let subtotal = schedule.headerSubtotals[item.id], subtotal > 0 else { return nil }
            return TimeFormatting.string(forSeconds: subtotal, threshold: engine.hourFormatThreshold)
        }
        let length = schedule.entry(forItemId: item.id)?.length ?? item.lengthInSeconds
        return TimeFormatting.string(forSeconds: length, threshold: engine.hourFormatThreshold)
    }

    private func cell(_ item: PCOTimerItem, text: String?, monospaced: Bool = false) -> some View {
        Text(text ?? "")
            .font(monospaced ? .body.monospacedDigit() : .body)
            .fontWeight(isActive(item) ? .semibold : (item.isHeader ? .heavy : .regular))
            .foregroundStyle(item.isHeader ? .secondary : .primary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(RunSheetCellStyle(isActive: isActive(item), isExcluded: isExcluded(item)))
    }

    private func titleCell(_ item: PCOTimerItem) -> some View {
        HStack(spacing: 6) {
            if isActive(item) {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
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
            Spacer(minLength: 0)
        }
        .modifier(RunSheetCellStyle(isActive: isActive(item), isExcluded: isExcluded(item)))
    }

    private func startCell(_ item: PCOTimerItem) -> some View {
        let entry = schedule.entry(forItemId: item.id)
        return HStack(spacing: 6) {
            if let entry, !entry.isExcluded, let planned = entry.plannedStart {
                Text(engine.clockFormat.string(from: planned))
                    .monospacedDigit()
                    .foregroundStyle(item.isHeader ? .secondary : .primary)
                if !item.isHeader, let drift = entry.driftSeconds, abs(drift) >= RunSheetSchedule.driftThreshold,
                   let projected = entry.projectedStart {
                    Text(engine.clockFormat.string(from: projected))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(drift > 0 ? Color.orange : Color.green)
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .modifier(RunSheetCellStyle(isActive: isActive(item), isExcluded: isExcluded(item)))
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

private struct RunSheetCellStyle: ViewModifier {
    let isActive: Bool
    let isExcluded: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isExcluded ? 0.5 : 1)
            .background(isActive ? Color.green.opacity(0.22) : Color.clear)
    }
}
#endif
