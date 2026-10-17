// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS)
import SwiftUI

struct RunSheetKeyPill: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.caption.weight(.bold))
            .foregroundStyle(AppPalette.keyPillText)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(AppPalette.keyPillFill, in: Capsule())
            .lineLimit(1)
            .accessibilityLabel("Key \(key)")
    }
}

struct RunSheetSequenceChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(AppPalette.surfaceSubtle, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .lineLimit(1)
            .fixedSize()
    }
}

struct RunSheetNowNextPane: View {
    @EnvironmentObject var engine: CueEngine
    let schedule: RunSheetSchedule
    let categories: [String]
    let containerWidth: CGFloat

    static let defaultWidth: CGFloat = 360
    static let minimumWidth: CGFloat = 280
    static let maximumFraction: CGFloat = 0.6
    static let defaultSplit: Double = 0.5

    private static let handleWidth: CGFloat = 9
    private static let minimumCardHeight: CGFloat = 120
    private static let splitHandleHeight: CGFloat = 9
    private static let coveredColumnIds: Set<String> = ["status", "title", "start"]

    @State private var widthDrag: (start: CGFloat, width: CGFloat)?
    @State private var splitDrag: (start: CGFloat, nowHeight: CGFloat)?

    private var maximumWidth: CGFloat {
        max(Self.minimumWidth, (containerWidth * Self.maximumFraction).rounded(.down))
    }

    private var paneWidth: CGFloat {
        let stored = widthDrag?.width ?? engine.runSheetLayout.nowNextPaneWidth.map { CGFloat($0) } ?? Self.defaultWidth
        return min(max(stored, Self.minimumWidth), maximumWidth)
    }

    private var fieldColumns: [RunSheetTableColumn] {
        let layout = engine.runSheetLayout
        let hidden = layout.hiddenSet
        return RunSheetTableColumn.ordered(categories, layout: layout)
            .filter { !hidden.contains($0.id) && !Self.coveredColumnIds.contains($0.id) }
    }

    var body: some View {
        HStack(spacing: 0) {
            widthHandle
            GeometryReader { proxy in
                cards(height: proxy.size.height)
            }
        }
        .frame(width: paneWidth)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var widthHandle: some View {
        Color.clear
            .frame(width: Self.handleWidth)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .trailing) { Divider() }
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = widthDrag?.start ?? paneWidth
                        let proposed = start - value.translation.width
                        widthDrag = (start, min(max(proposed.rounded(), Self.minimumWidth), maximumWidth))
                    }
                    .onEnded { _ in
                        if let drag = widthDrag {
                            engine.runSheetLayout.nowNextPaneWidth = Double(drag.width)
                        }
                        widthDrag = nil
                    }
            )
            .onTapGesture(count: 2) {
                engine.runSheetLayout.nowNextPaneWidth = nil
            }
            .help("Drag to resize the pane. Double-click to reset it.")
    }

    private func nowHeight(in total: CGFloat) -> CGFloat {
        let available = max(total - Self.splitHandleHeight, 0)
        let lower = min(Self.minimumCardHeight, available / 2)
        let upper = max(available - Self.minimumCardHeight, lower)
        if let drag = splitDrag { return min(max(drag.nowHeight, lower), upper) }
        let fraction = engine.runSheetLayout.nowNextSplit ?? Self.defaultSplit
        return min(max((available * CGFloat(fraction)).rounded(), lower), upper)
    }

    private func cards(height: CGFloat) -> some View {
        let now = nowHeight(in: height)
        return VStack(spacing: 0) {
            RunSheetFocusCard(role: .now, item: nowItem, schedule: schedule, columns: fieldColumns)
                .frame(height: now)
            splitHandle(totalHeight: height, currentNowHeight: now)
            RunSheetFocusCard(role: .next, item: nextItem, schedule: schedule, columns: fieldColumns)
                .frame(maxHeight: .infinity)
        }
    }

    private func splitHandle(totalHeight: CGFloat, currentNowHeight: CGFloat) -> some View {
        let available = max(totalHeight - Self.splitHandleHeight, 1)
        return Color.clear
            .frame(height: Self.splitHandleHeight)
            .frame(maxWidth: .infinity)
            .overlay { Divider() }
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = splitDrag?.start ?? currentNowHeight
                        splitDrag = (start, start + value.translation.height)
                    }
                    .onEnded { _ in
                        if splitDrag != nil {
                            let fraction = Double(nowHeight(in: totalHeight) / available)
                            engine.runSheetLayout.nowNextSplit = (fraction * 1000).rounded() / 1000
                        }
                        splitDrag = nil
                    }
            )
            .onTapGesture(count: 2) {
                engine.runSheetLayout.nowNextSplit = nil
            }
            .help("Drag to resize the Now and Next cards. Double-click to reset.")
    }

    private var nowItem: PCOTimerItem? {
        guard let active = engine.activeTimerItem, !active.isHeader else { return nil }
        return active
    }

    private var nextItem: PCOTimerItem? {
        guard let next = engine.derivedNextPlanItem, !next.isHeader else { return nil }
        return next
    }
}

private struct RunSheetFocusCard: View {
    enum Role {
        case now
        case next
    }

    private enum Field {
        case text(String)
        case number(String)
        case key(String)
        case chips([String])
        case drift(Int)
        case note(String)
    }

    @EnvironmentObject var engine: CueEngine
    @Environment(\.runSheetReferencePresenter) private var reference
    let role: Role
    let item: PCOTimerItem?
    let schedule: RunSheetSchedule
    let columns: [RunSheetTableColumn]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(role == .now ? "NOW" : "NEXT")
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(role == .now ? AppPalette.timerOnTime : Color.accentColor)

                if let item {
                    content(for: item)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyState: some View {
        Text(emptyText)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private var emptyText: String {
        switch role {
        case .now: return "Nothing is running"
        case .next: return engine.activeTimerItem == nil ? "Waiting for the event to start" : "End of the run sheet"
        }
    }

    @ViewBuilder
    private func content(for timing: PCOTimerItem) -> some View {
        let item = engine.planItems.first(where: { $0.id == timing.id }) ?? timing
        let entry = schedule.entry(forItemId: item.id)

        Text(item.title)
            .font(.title3.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)

        if item.runSheetKind == .song, let author = item.runSheetAuthor {
            Text(author)
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        switch role {
        case .now:
            nowTiming(item, entry: entry)
        case .next:
            nextTiming(item, entry: entry)
        }

        ForEach(columns) { column in
            if let field = field(for: column, item: item, entry: entry) {
                fieldView(column, field)
            }
        }

        referenceButtons(for: item)
    }

    private func field(for column: RunSheetTableColumn, item: PCOTimerItem, entry: RunSheetSchedule.Entry?) -> Field? {
        func nonEmpty(_ text: String?) -> String? {
            guard let text, !text.isEmpty else { return nil }
            return text
        }
        switch column.id {
        case "time":
            let live = engine.activeTimerItem?.id == item.id ? engine.activeTimerItem : nil
            guard let actual = live?.elapsedSeconds ?? entry?.actualLength else { return nil }
            let planned = entry?.length ?? item.lengthInSeconds
            return .number("\(format(actual)) / \(format(planned))")
        case "drift":
            guard let delta = entry?.actualDeltaSeconds, abs(delta) >= RunSheetActualStyle.lengthThreshold else { return nil }
            return .drift(delta)
        case "key":
            return item.details?.displayKey.map(Field.key)
        case "sequence":
            let sequence = item.details?.effectiveSequenceShort ?? []
            return sequence.isEmpty ? nil : .chips(sequence)
        case "number":
            return .number(String(item.sequence))
        case "type":
            return nonEmpty(item.runSheetTypeLabel).map(Field.text)
        case "bpm":
            return nonEmpty(item.runSheetBPMText).map(Field.number)
        case "meter":
            return nonEmpty(item.runSheetMeter).map(Field.text)
        case "arrangement":
            return nonEmpty(item.runSheetArrangementName).map(Field.text)
        case "description":
            return nonEmpty(item.runSheetDescription).map(Field.text)
        case "pco-actual":
            return entry?.pcoActualLength.map { Field.number(format($0)) }
        default:
            guard column.id.hasPrefix("note-") else { return nil }
            return nonEmpty(item.notes[RunSheetTableColumn.category(fromNoteID: column.id)]).map(Field.note)
        }
    }

    private func fieldView(_ column: RunSheetTableColumn, _ field: Field) -> some View {
        let on = engine.runSheetLayout.highlightedSet.contains(column.id)
        return VStack(alignment: .leading, spacing: 2) {
            Text(column.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Group {
            switch field {
            case .text(let text):
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            case .number(let text):
                Text(text)
                    .font(.clock(.callout))
            case .key(let key):
                RunSheetKeyPill(key: key)
            case .chips(let sections):
                RunSheetFlowLayout(spacing: 4) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        RunSheetSequenceChip(text: section)
                    }
                }
            case .drift(let delta):
                Text(RunSheetActualStyle.signed(delta, threshold: engine.hourFormatThreshold))
                    .font(.clock(.callout, weight: .semibold))
                    .foregroundStyle(RunSheetActualStyle.color(forDelta: delta))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(RunSheetActualStyle.fillColor(forDelta: delta), in: Capsule())
            case .note(let text):
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            }
            .markerHighlight(on)
        }
    }

    private func format(_ seconds: Int) -> String {
        TimeFormatting.string(forSeconds: seconds, threshold: engine.hourFormatThreshold)
    }

    private func nowTiming(_ item: PCOTimerItem, entry: RunSheetSchedule.Entry?) -> some View {
        let start = entry?.actualStart ?? entry?.projectedStart ?? entry?.plannedStart
        let length = entry?.length ?? item.lengthInSeconds
        return timingRow(startLabel: "Started", start: start, length: length)
    }

    private func nextTiming(_ item: PCOTimerItem, entry: RunSheetSchedule.Entry?) -> some View {
        let start = entry?.projectedStart ?? entry?.plannedStart
        let length = entry?.length ?? item.lengthInSeconds
        return timingRow(startLabel: "Starts", start: start, length: length)
    }

    private func timingRow(startLabel: String, start: Date?, length: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            if let start {
                VStack(alignment: .leading, spacing: 0) {
                    Text(startLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(engine.clockFormat.string(from: start))
                        .font(.clock(.title3, weight: .semibold))
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Length")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(TimeFormatting.string(forSeconds: length, threshold: engine.hourFormatThreshold))
                    .font(.clock(.title3, weight: .semibold))
            }
        }
    }

    @ViewBuilder
    private func referenceButtons(for item: PCOTimerItem) -> some View {
        let hasChart = engine.hasChart(item)
        let hasAttachments = engine.hasAttachments(item)
        if hasChart || hasAttachments {
            HStack(spacing: 8) {
                if hasChart {
                    Button {
                        reference.present(.chart(item))
                    } label: {
                        Label("Chart", systemImage: "music.note.list")
                    }
                    .producerSecondaryButton()
                    .compactControlSize()
                    .help("Show the lyrics and chord chart from Planning Center")
                }
                if hasAttachments {
                    Button {
                        reference.present(.attachments(item))
                    } label: {
                        Label("Attachments", systemImage: "paperclip")
                    }
                    .producerSecondaryButton()
                    .compactControlSize()
                    .help("Show the files and links attached in Planning Center")
                }
            }
        }
    }
}
#endif
