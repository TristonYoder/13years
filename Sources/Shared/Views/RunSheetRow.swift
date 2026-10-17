// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

struct MarkerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.height * 0.14
        let r = rect.insetBy(dx: 0, dy: inset)
        let w = r.width
        let h = r.height
        let skew = min(h * 0.22, 6)
        var path = Path()
        path.move(to: CGPoint(x: r.minX + skew, y: r.minY + h * 0.06))
        path.addCurve(
            to: CGPoint(x: r.maxX, y: r.minY),
            control1: CGPoint(x: r.minX + w * 0.30, y: r.minY - h * 0.07),
            control2: CGPoint(x: r.minX + w * 0.68, y: r.minY + h * 0.12)
        )
        path.addQuadCurve(
            to: CGPoint(x: r.maxX - skew, y: r.maxY - h * 0.04),
            control: CGPoint(x: r.maxX + skew * 0.4, y: r.midY)
        )
        path.addCurve(
            to: CGPoint(x: r.minX, y: r.maxY),
            control1: CGPoint(x: r.minX + w * 0.72, y: r.maxY + h * 0.07),
            control2: CGPoint(x: r.minX + w * 0.28, y: r.maxY - h * 0.10)
        )
        path.addQuadCurve(
            to: CGPoint(x: r.minX + skew, y: r.minY + h * 0.06),
            control: CGPoint(x: r.minX - skew * 0.3, y: r.midY)
        )
        path.closeSubpath()
        return path
    }
}

private struct MarkerHighlight: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.background {
                MarkerShape()
                    .fill(AppPalette.highlightMarker)
                    .padding(.horizontal, -4)
                    .padding(.vertical, -1)
            }
        } else {
            content
        }
    }
}

extension View {
    func markerHighlight(_ isOn: Bool) -> some View {
        modifier(MarkerHighlight(isOn: isOn))
    }
}

struct RunSheetFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

enum RunSheetCardPosition {
    case only
    case first
    case middle
    case last

    static let cornerRadius: CGFloat = 10
    static let gap: CGFloat = 10
    static let horizontalInset: CGFloat = 6

    var roundsTop: Bool { self == .only || self == .first }
    var roundsBottom: Bool { self == .only || self == .last }

    static func positions(for items: [PCOTimerItem]) -> [RunSheetCardPosition] {
        items.indices.map { index in
            let starts = index == 0 || items[index].isHeader
            let ends = index == items.count - 1 || items[index + 1].isHeader
            switch (starts, ends) {
            case (true, true): return .only
            case (true, false): return .first
            case (false, true): return .last
            case (false, false): return .middle
            }
        }
    }
}

private struct RunSheetCardEdge: Shape {
    let roundsTop: Bool
    let roundsBottom: Bool

    func path(in rect: CGRect) -> Path {
        let r = RunSheetCardPosition.cornerRadius
        let frame = rect.insetBy(dx: 0.5, dy: 0.5)
        var path = Path()
        path.move(to: CGPoint(x: frame.minX, y: roundsBottom ? frame.maxY - r : rect.maxY))
        path.addLine(to: CGPoint(x: frame.minX, y: roundsTop ? frame.minY + r : rect.minY))
        if roundsTop {
            path.addArc(tangent1End: CGPoint(x: frame.minX, y: frame.minY), tangent2End: CGPoint(x: frame.minX + r, y: frame.minY), radius: r)
            path.addLine(to: CGPoint(x: frame.maxX - r, y: frame.minY))
            path.addArc(tangent1End: CGPoint(x: frame.maxX, y: frame.minY), tangent2End: CGPoint(x: frame.maxX, y: frame.minY + r), radius: r)
        } else {
            path.move(to: CGPoint(x: frame.maxX, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: frame.maxX, y: roundsBottom ? frame.maxY - r : rect.maxY))
        if roundsBottom {
            path.addArc(tangent1End: CGPoint(x: frame.maxX, y: frame.maxY), tangent2End: CGPoint(x: frame.maxX - r, y: frame.maxY), radius: r)
            path.addLine(to: CGPoint(x: frame.minX + r, y: frame.maxY))
            path.addArc(tangent1End: CGPoint(x: frame.minX, y: frame.maxY), tangent2End: CGPoint(x: frame.minX, y: frame.maxY - r), radius: r)
        }
        return path
    }
}

struct RunSheetRowBackground: View {
    let item: PCOTimerItem
    let activeItem: PCOTimerItem?
    let isActive: Bool
    let isSelected: Bool
    var position: RunSheetCardPosition = .only

    var body: some View {
        let radius = RunSheetCardPosition.cornerRadius
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: position.roundsTop ? radius : 0,
            bottomLeadingRadius: position.roundsBottom ? radius : 0,
            bottomTrailingRadius: position.roundsBottom ? radius : 0,
            topTrailingRadius: position.roundsTop ? radius : 0,
            style: .continuous
        )
        ZStack {
            AppPalette.sectionCard

            if item.isHeader {
                AppPalette.sectionHeaderTint
            } else {
                let liveItem = isActive ? (activeItem ?? item) : item
                if isActive && liveItem.isRunning {
                    let style = overrunStyle(for: liveItem)
                    PulsingRowBackground(color: style.color, minOpacity: style.min, maxOpacity: style.max)
                } else if isActive {
                    AppPalette.rowActive
                }
            }

            if isSelected {
                AppPalette.rowSelected
            }
        }
        .overlay(alignment: .top) {
            if !position.roundsTop {
                Rectangle().fill(AppPalette.sectionCardBorder).frame(height: 0.5)
            }
        }
        .clipShape(shape)
        .overlay(RunSheetCardEdge(roundsTop: position.roundsTop, roundsBottom: position.roundsBottom).stroke(AppPalette.sectionCardBorder, lineWidth: 1))
        .padding(.top, position.roundsTop ? RunSheetCardPosition.gap : 0)
        .padding(.horizontal, RunSheetCardPosition.horizontalInset)
    }

    private func overrunStyle(for item: PCOTimerItem) -> (color: Color, min: Double, max: Double) {
        if item.isOvertime {
            return (AppPalette.timerOvertime, 0.28, 0.55)
        }
        if item.lengthInSeconds > 0, Double(item.remainingSeconds) <= Double(item.lengthInSeconds) * 0.1 {
            return (AppPalette.timerWarning, 0.14, 0.34)
        }
        return (AppPalette.timerOnTime, 0.12, 0.30)
    }
}

struct PulsingRowBackground: View {
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

struct InlineItemEditor: View {
    @EnvironmentObject var engine: CueEngine
    #if os(macOS) || os(iOS)
    @Environment(\.runSheetReferencePresenter) private var reference
    #endif
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
                        .producerSecondaryButton()
                        .compactControlSize()
                    #if os(macOS) || os(iOS)
                    Spacer(minLength: 0)
                    referenceButtons
                    #endif
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

    #if os(macOS) || os(iOS)
    @ViewBuilder
    private var referenceButtons: some View {
        if engine.hasChart(item) {
            Button {
                reference.present(.chart(item))
            } label: {
                Label("Chart", systemImage: "music.note.list")
            }
            .producerSecondaryButton()
            .compactControlSize()
            .help("Show the lyrics and chord chart from Planning Center")
        }
        if engine.hasAttachments(item) {
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
    #endif

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
            .compactControlSize()
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

struct RunSheetRow: View {
    @EnvironmentObject var engine: CueEngine
    let item: PCOTimerItem
    let entry: RunSheetSchedule.Entry?
    let showsStart: Bool
    let isActive: Bool
    let isExpanded: Bool
    let isCollapsed: Bool
    let subtotal: Int?
    let excludedLabel: String?
    let knownCategories: [String]
    let onToggleExpanded: () -> Void
    let onToggleCollapsed: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onNewWaypoint: () -> Void

    private var isExcluded: Bool { entry?.isExcluded ?? false }
    private var isSkipped: Bool { entry?.isSkipped ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
                    .accessibilityHidden(true)

                if showsStart {
                    startColumn
                        .padding(.top, 2)
                }

                lengthColumn
                    .padding(.top, 2)

                content

                Spacer()

                trailingControls
            }
            .opacity(isExcluded || isSkipped ? 0.5 : 1)

            if isExpanded {
                InlineItemEditor(item: item, knownCategories: knownCategories)
                    .padding(.leading, 32)
            }
        }
    }

    private var startColumn: some View {
        Group {
            if let entry, !entry.isOmitted, let planned = entry.plannedStart {
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.clockFormat.string(from: planned))
                        .font(.clock(.caption))
                        .foregroundStyle(item.isHeader ? .tertiary : .secondary)
                    if !item.isHeader, let drift = entry.driftSeconds, abs(drift) >= RunSheetSchedule.driftThreshold,
                       let projected = entry.projectedStart {
                        Text(engine.clockFormat.string(from: projected))
                            .font(.clock(.caption2, weight: .semibold))
                            .foregroundStyle(drift > 0 ? AppPalette.driftLate : AppPalette.driftEarly)
                            .help(drift > 0 ? "Projected to start later than planned" : "Projected to start earlier than planned")
                    }
                }
            } else {
                Color.clear
            }
        }
        .frame(width: 72, alignment: .leading)
    }

    private var lengthColumn: some View {
        Group {
            if item.isHeader {
                if let subtotal, subtotal > 0 {
                    Text(formattedDuration(subtotal))
                        .font(.clock(.caption))
                        .foregroundStyle(AppPalette.sectionHeaderText)
                        .help("Total length of the items in this section")
                } else {
                    Color.clear
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedDuration(entry?.length ?? item.lengthInSeconds))
                        .font(.clock(.caption))
                        .foregroundStyle(.secondary)
                    durationModeBadge
                    if let entry {
                        RunSheetActualText(entry: entry)
                    }
                }
            }
        }
        .frame(width: 58, alignment: .leading)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 10) {
            if item.runSheetKind == .media, let url = item.details?.media?.thumbnailURL.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        AppPalette.surfaceMuted
                    }
                }
                .frame(width: 64, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                titleLine

                if !item.isHeader {
                    typeDetails
                    waypointsRow
                }

                ForEach(item.notes.keys.sorted(), id: \.self) { category in
                    if let text = item.notes[category], !text.isEmpty {
                        Text("\(category): \(text)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .markerHighlight(isHighlighted(RunSheetLayoutSettings.noteColumnId(category)))
                    }
                }
            }
        }
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            if item.isHeader {
                Button(action: onToggleCollapsed) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCollapsed ? "Expand section" : "Collapse section")
                .help(isCollapsed ? "Show the items in this section" : "Hide the items in this section")

                Text(item.title.uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(1.0)
                    .foregroundStyle(AppPalette.sectionHeaderText)
            } else {
                Text(item.title)
                    .font(.body.weight(isActive ? .bold : .regular))
                if item.runSheetKind == .song, let author = item.runSheetAuthor {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
            }
            if item.pcoPlanId != nil {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(AppPalette.info)
                    .help("Synced with Planning Center")
            }
            if isExcluded, let excludedLabel {
                Text("Not in \(excludedLabel)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppPalette.warning)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(AppPalette.warningFill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .lineLimit(1)
            }
            if isSkipped {
                Text("Skipped")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(AppPalette.surfaceMuted, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var typeDetails: some View {
        switch item.runSheetKind {
        case .song:
            songDetails
        case .media:
            if item.details?.media != nil {
                Text(item.runSheetTypeLabel.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(AppPalette.surfaceSubtle, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .markerHighlight(isHighlighted("type"))
            }
        case .item, .header:
            EmptyView()
        }
        if let description = item.runSheetDescription {
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .markerHighlight(isHighlighted("description"))
        }
    }

    @ViewBuilder
    private var songDetails: some View {
        let key = item.details?.displayKey
        let bpm = item.runSheetBPMText
        let meter = item.runSheetMeter
        let arrangement = item.runSheetArrangementName
        if key != nil || bpm != nil || meter != nil || arrangement != nil {
            RunSheetFlowLayout(spacing: 8) {
                if let key {
                    Text(key)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .accessibilityLabel("Key \(key)")
                        .markerHighlight(isHighlighted("key"))
                }
                if let bpm {
                    Text("\(bpm) BPM")
                        .font(.clock(.caption, weight: .regular))
                        .markerHighlight(isHighlighted("bpm"))
                }
                if let meter {
                    Text(meter)
                        .markerHighlight(isHighlighted("meter"))
                }
                if let arrangement {
                    Text(arrangement)
                        .markerHighlight(isHighlighted("arrangement"))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        let sequence = item.details?.effectiveSequenceShort ?? []
        if !sequence.isEmpty {
            RunSheetFlowLayout(spacing: 4) {
                ForEach(Array(sequence.enumerated()), id: \.offset) { _, section in
                    Text(section)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(AppPalette.surfaceSubtle, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .markerHighlight(isHighlighted("sequence"))
        }
    }

    private func isHighlighted(_ columnId: String) -> Bool {
        engine.runSheetLayout.highlightedSet.contains(columnId)
    }

    @ViewBuilder
    private var trailingControls: some View {
        Group {
            if item.isHeader {
                EmptyView()
            } else if isActive {
                HStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppPalette.timerOnTime)
                        .frame(width: 52, height: 52)

                    Button {
                        engine.resetTimer()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title2.weight(.bold))
                            .frame(width: 52, height: 52)
                    }
                    .producerSecondaryButton()
                    .buttonBorderShape(.roundedRectangle(radius: 10))
                    .tint(.secondary)
                    .accessibilityLabel("Reset")
                    .help("Reset this item's clock back to its full length \u{2014} if Planning Center Live sync is on, also steps back and immediately forward there so PCO's own clock restarts too")
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
                .tint(AppPalette.positive)
                .accessibilityLabel("Go")
                .help("Jump to this item and make it active")
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)

        Button {
            withAnimation(.easeInOut(duration: 0.15), onToggleExpanded)
        } label: {
            Image(systemName: isExpanded ? "chevron.up.circle" : "chevron.down.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Edit time and notes inline")

        #if os(macOS)
        RowActionButton(systemImage: "pencil", label: "Edit item\u{2026}", action: onEdit)
        RowActionButton(systemImage: "trash", label: "Delete item\u{2026}", action: onDelete)
        #endif
    }

    private var waypointsRow: some View {
        let waypoints = engine.waypoints(forItemId: item.id)
        return HStack(spacing: 4) {
            ForEach(waypoints) { waypoint in
                HStack(spacing: 3) {
                    Image(systemName: Waypoint.symbolName)
                    Text(waypoint.name)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(AppPalette.surfaceSubtle, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            Menu {
                RunSheetWaypointMenuItems(item: item, onNewWaypoint: onNewWaypoint)
            } label: {
                Image(systemName: waypoints.isEmpty ? Waypoint.symbolName : "plus")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(AppPalette.surfaceSubtle, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .menuIndicator(.hidden)
            .help("Assign waypoints\u{2026}")
        }
    }

    private var durationModeBadge: some View {
        Button {
            engine.setDurationIsActual(id: item.id, isActual: !item.isDurationActual)
        } label: {
            Text(item.isDurationActual ? "ACT" : "PROJ")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(item.isDurationActual ? Color.white : Color.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    item.isDurationActual ? AppPalette.info : AppPalette.surfaceMuted,
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(item.isDurationActual
            ? "Actual duration \u{2014} tap to mark as projected"
            : "Projected duration \u{2014} tap to mark as an actual, known duration")
    }

    private func formattedDuration(_ seconds: Int) -> String {
        TimeFormatting.string(forSeconds: seconds, threshold: engine.hourFormatThreshold)
    }
}
