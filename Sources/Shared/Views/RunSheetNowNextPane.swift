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
    var selectedItemId: String?

    static let defaultWidth: CGFloat = 360
    static let minimumWidth: CGFloat = 280
    static let maximumFraction: CGFloat = 0.6
    static let defaultSplit: Double = 0.5

    private static let handleWidth: CGFloat = 9
    private static let minimumCardHeight: CGFloat = 120
    private static let splitHandleHeight: CGFloat = 9
    private static let coveredColumnIds: Set<String> = ["status", "title", "start", "leader", "leaderPhoto"]

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
            VStack(spacing: 0) {
                tabBar
                if engine.runSheetLayout.showsDetailsTab {
                    RunSheetDetailsPane(selectedItemId: selectedItemId)
                } else {
                    GeometryReader { proxy in
                        cards(height: proxy.size.height)
                    }
                }
            }
        }
        .frame(width: paneWidth)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var tabBar: some View {
        Picker("Side pane", selection: Binding(
            get: { engine.runSheetLayout.showsDetailsTab },
            set: { engine.runSheetLayout.sidePaneTab = $0 ? RunSheetLayoutSettings.detailsTabId : nil }
        )) {
            Text("Now & Next").tag(false)
            Text("Details").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
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

private struct RunSheetDetailsPane: View {
    @EnvironmentObject var engine: CueEngine
    let selectedItemId: String?

    private var followsLive: Bool { engine.runSheetLayout.followsLiveItem }

    private var item: PCOTimerItem? {
        let id = followsLive ? engine.activeTimerItem?.id : selectedItemId
        guard let id else { return nil }
        return engine.planItems.first { $0.id == id }
    }

    private var scale: Double { engine.runSheetLayout.effectiveDetailsTextScale }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            Divider()
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.title3.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            RunSheetByline(leaders: item.runSheetLeaders, avatarSize: 18)
                        }
                        if let html = Self.source(for: item) {
                            RunSheetHTMLText(html: html, scale: scale)
                        } else {
                            Text("No details for this item")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .id(followsLive ? item.id : "pinned")
            } else {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyText: String {
        followsLive ? "Nothing is running" : "Select an item in the run sheet"
    }

    static func source(for item: PCOTimerItem) -> String? {
        if let html = item.details?.htmlDetails, !html.isEmpty { return html }
        return item.details?.description.flatMap { $0.isEmpty ? nil : $0 }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { followsLive },
                set: { engine.runSheetLayout.detailsUnpinned = $0 ? nil : true }
            )) {
                Label("Follow live item", systemImage: followsLive ? "pin.fill" : "pin.slash")
                    .font(.caption)
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help(followsLive ? "Showing the live item. Turn off to show the item selected in the run sheet." : "Showing the selected item. Turn on to follow the live item.")
            Spacer(minLength: 0)
            Button {
                adjustScale(by: -RunSheetLayoutSettings.detailsTextScaleStep)
            } label: {
                Text("A\u{2212}").font(.system(size: 11, weight: .semibold))
            }
            .disabled(scale <= RunSheetLayoutSettings.detailsTextScaleRange.lowerBound + 0.001)
            .help("Smaller text")
            Button {
                adjustScale(by: RunSheetLayoutSettings.detailsTextScaleStep)
            } label: {
                Text("A+").font(.system(size: 14, weight: .semibold))
            }
            .disabled(scale >= RunSheetLayoutSettings.detailsTextScaleRange.upperBound - 0.001)
            .help("Larger text")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func adjustScale(by delta: Double) {
        let next = min(max(scale + delta, RunSheetLayoutSettings.detailsTextScaleRange.lowerBound), RunSheetLayoutSettings.detailsTextScaleRange.upperBound)
        let rounded = (next * 100).rounded() / 100
        engine.runSheetLayout.detailsTextScale = abs(rounded - 1.0) < 0.001 ? nil : rounded
    }
}

private struct RunSheetHTMLText: View {
    let html: String
    let scale: Double

    @Environment(\.colorScheme) private var colorScheme
    @State private var rendered: AttributedString

    private static let baseSize: CGFloat = 13
    private static let minimumContrast = 2.5

    init(html: String, scale: Double) {
        self.html = html
        self.scale = scale
        _rendered = State(initialValue: HTMLAttributedConverter.attributedString(fromHTML: html))
    }

    var body: some View {
        Text(styled)
            .font(.system(size: Self.baseSize * CGFloat(scale)))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: html) { rendered = HTMLAttributedConverter.attributedString(fromHTML: html) }
    }

    private var pageColor: HTMLColor {
        colorScheme == .dark ? HTMLColor(red: 0.12, green: 0.12, blue: 0.13) : HTMLColor(red: 1, green: 1, blue: 1)
    }

    private func color(_ value: HTMLColor) -> Color {
        Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }

    private var styled: AttributedString {
        var text = rendered
        let size = Self.baseSize * CGFloat(scale)
        for run in text.runs {
            let range = run.range
            let background = run[HTMLBackgroundColorKey.self].flatMap(HTMLColor.init(css:))
            if let background {
                text[range].backgroundColor = color(background)
            }
            let ground = background.map { $0.alpha >= 0.5 ? $0 : pageColor } ?? pageColor
            if let foreground = run[HTMLForegroundColorKey.self].flatMap(HTMLColor.init(css:)),
               HTMLColor.contrast(foreground, ground) >= Self.minimumContrast {
                text[range].foregroundColor = color(foreground)
            } else if background != nil {
                text[range].foregroundColor = ground.luminance > 0.4 ? .black : .white
            }
            if run[HTMLUnderlineKey.self] == true {
                text[range].underlineStyle = .single
            }
            if run[HTMLStrikethroughKey.self] == true {
                text[range].strikethroughStyle = .single
            }
            var runSize = size * CGFloat(run[HTMLFontScaleKey.self] ?? 1)
            var weight: Font.Weight?
            if let level = run[HTMLHeadingLevelKey.self] {
                let factors: [Int: CGFloat] = [1: 1.5, 2: 1.3, 3: 1.15, 4: 1.05, 5: 1, 6: 0.9]
                runSize *= factors[level] ?? 1
                weight = .bold
            }
            if let baseline = run[HTMLBaselineKey.self] {
                text[range].baselineOffset = CGFloat(baseline) * runSize * 0.35
            }
            let intent = run.inlinePresentationIntent ?? []
            let resolvedWeight = weight ?? (intent.contains(.stronglyEmphasized) ? .bold : nil)
            let needsFont = runSize != size || weight != nil || run[HTMLMonospaceKey.self] == true
            if needsFont {
                var font: Font = run[HTMLMonospaceKey.self] == true
                    ? .system(size: runSize, design: .monospaced)
                    : .system(size: runSize)
                if let resolvedWeight { font = font.weight(resolvedWeight) }
                if intent.contains(.emphasized) { font = font.italic() }
                text[range].font = font
            }
        }
        return text
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

        leadersBlock(item.runSheetLeaders)

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

    @ViewBuilder
    private func leadersBlock(_ leaders: [PCOItemLeader]) -> some View {
        let hidden = engine.runSheetLayout.hiddenSet
        let showsName = !hidden.contains("leader")
        let showsPhoto = !hidden.contains("leaderPhoto")
        if !leaders.isEmpty, showsName || showsPhoto {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(leaders) { leader in
                    HStack(spacing: 10) {
                        if showsPhoto {
                            LeaderAvatar(leader: leader, size: 40)
                        }
                        if showsName {
                            (Text("Leader: ").foregroundStyle(.secondary) + Text(leader.name).fontWeight(.medium))
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
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
