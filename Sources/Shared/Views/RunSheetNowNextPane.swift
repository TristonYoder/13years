// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS)
import SwiftUI

struct RunSheetKeyPill: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.caption.weight(.bold))
            .foregroundStyle(.purple)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Color.purple.opacity(0.16), in: Capsule())
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
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .lineLimit(1)
            .fixedSize()
    }
}

struct RunSheetNowNextPane: View {
    @EnvironmentObject var engine: CueEngine
    let schedule: RunSheetSchedule

    static let width: CGFloat = 360

    var body: some View {
        HStack(spacing: 0) {
            Divider()
            VSplitView {
                RunSheetFocusCard(role: .now, item: nowItem, schedule: schedule)
                    .frame(minHeight: 160, maxHeight: .infinity)
                RunSheetFocusCard(role: .next, item: nextItem, schedule: schedule)
                    .frame(minHeight: 140, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 300, idealWidth: Self.width, maxWidth: Self.width)
        .background(Color(nsColor: .windowBackgroundColor))
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

    @EnvironmentObject var engine: CueEngine
    @Environment(\.runSheetReferencePresenter) private var reference
    let role: Role
    let item: PCOTimerItem?
    let schedule: RunSheetSchedule

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(role == .now ? "NOW" : "NEXT")
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(role == .now ? Color.green : Color.accentColor)

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

        details(for: item)

        switch role {
        case .now:
            nowTiming(timing)
        case .next:
            nextTiming(item, entry: entry)
        }

        let sequence = item.details?.effectiveSequenceShort ?? []
        if !sequence.isEmpty {
            RunSheetFlowLayout(spacing: 4) {
                ForEach(Array(sequence.enumerated()), id: \.offset) { _, section in
                    RunSheetSequenceChip(text: section)
                }
            }
        }

        if let description = item.runSheetDescription {
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        ForEach(item.notes.keys.sorted(), id: \.self) { category in
            if let text = item.notes[category], !text.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        referenceButtons(for: item)
    }

    @ViewBuilder
    private func details(for item: PCOTimerItem) -> some View {
        let key = item.details?.displayKey
        let bpm = item.runSheetBPMText
        let meter = item.runSheetMeter
        let arrangement = item.runSheetArrangementName
        if key != nil || bpm != nil || meter != nil || arrangement != nil {
            RunSheetFlowLayout(spacing: 8) {
                if let key { RunSheetKeyPill(key: key) }
                if let bpm { Text("\(bpm) BPM") }
                if let meter { Text(meter) }
                if let arrangement { Text(arrangement) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func nowTiming(_ timing: PCOTimerItem) -> some View {
        let color = progressColor(timing)
        let length = max(timing.lengthInSeconds, 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text(remainingText(timing.remainingSeconds))
                .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(timing.isOvertime ? color : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            ProgressView(value: Double(min(timing.elapsedSeconds, length)), total: Double(length))
                .progressViewStyle(.linear)
                .tint(color)
        }
    }

    private func nextTiming(_ item: PCOTimerItem, entry: RunSheetSchedule.Entry?) -> some View {
        let start = entry?.projectedStart ?? entry?.plannedStart
        let length = entry?.length ?? item.lengthInSeconds
        return HStack(alignment: .firstTextBaseline, spacing: 16) {
            if let start {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Starts")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(engine.clockFormat.string(from: start))
                        .font(.title3.monospacedDigit().weight(.semibold))
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Length")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(TimeFormatting.string(forSeconds: length, threshold: engine.hourFormatThreshold))
                    .font(.title3.monospacedDigit().weight(.semibold))
            }
        }
    }

    private func remainingText(_ seconds: Int) -> String {
        let text = TimeFormatting.string(forSeconds: TimerLimits.safeAbs(seconds), threshold: engine.hourFormatThreshold)
        return seconds < 0 ? "+\(text)" : text
    }

    private func progressColor(_ item: PCOTimerItem) -> Color {
        if item.isOvertime { return Color(red: 0.80, green: 0.09, blue: 0.09) }
        if item.lengthInSeconds > 0, Double(item.remainingSeconds) <= Double(item.lengthInSeconds) * 0.1 { return .orange }
        return .green
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
