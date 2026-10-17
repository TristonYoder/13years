// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS) || os(iOS)
import SwiftUI

struct RunSheetPlanPanel: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.openURL) private var openURL
    @State private var isRefreshing = false
    @StateObject private var attachmentOpener = AttachmentOpener()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let context = engine.pcoPlanContext {
                List {
                    planSection(context)
                    if engine.canBrowsePCOReference { attachmentsSection(context) }
                    if !context.notes.isEmpty { notesSection(context) }
                    if !context.times.isEmpty { timesSection(context) }
                    if !context.team.isEmpty { teamSections(context) }
                    if !context.neededPositions.isEmpty { neededSection(context) }
                }
            } else {
                ContentUnavailableView(
                    "No Planning Center Plan",
                    systemImage: "person.3",
                    description: Text("Sync a Planning Center plan to see its notes, times and team here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .attachmentPreview(attachmentOpener)
        .inspectorColumnWidthIfAvailable()
    }

    private func attachmentsSection(_ context: PCOPlanContext) -> some View {
        Section("Attachments") {
            AttachmentRows(
                opener: attachmentOpener,
                owner: .plan(serviceTypeId: context.serviceTypeId, planId: context.planId),
                refreshToken: context.fetchedAt,
                emptyText: "No plan attachments"
            )
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Plan")
                .font(.headline)
            Spacer()
            if isRefreshing || engine.isRefreshingPCOPlanContext {
                ProgressView()
                    .controlSize(.small)
            }
            Button(action: refresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing || engine.isRefreshingPCOPlanContext || !engine.isPCOConnected)
            .help("Reload the plan details, notes, times and team from Planning Center")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func refresh() {
        let previous = engine.pcoPlanContext?.fetchedAt
        isRefreshing = true
        Task {
            await engine.refreshPCOPlanContext()
            if engine.isRemoteMirror {
                for _ in 0..<16 where engine.pcoPlanContext?.fetchedAt == previous {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            isRefreshing = false
        }
    }

    private func planSection(_ context: PCOPlanContext) -> some View {
        Section("Plan") {
            if let error = engine.pcoPlanContextError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppPalette.warning)
                    .font(.footnote)
            }
            LabeledContent("Title", value: context.title ?? engine.planItems.first?.servicePlanTitle ?? "Untitled")
            if let series = context.seriesTitle, !series.isEmpty {
                LabeledContent("Series", value: series)
            }
            if let dates = context.dates, !dates.isEmpty {
                LabeledContent("Dates", value: dates)
            }
            if let total = context.totalLength, total > 0 {
                LabeledContent("Total length", value: Self.duration(total))
            }
            LabeledContent("Updated") {
                Text(context.fetchedAt, style: .relative)
                    .foregroundStyle(.secondary)
            }
            if let raw = context.planningCenterURL, let url = URL(string: raw) {
                Button {
                    openURL(url)
                } label: {
                    Label("Open in Planning Center", systemImage: "arrow.up.right.square")
                }
            }
        }
    }

    private func notesSection(_ context: PCOPlanContext) -> some View {
        Section("Plan Notes") {
            ForEach(context.notes) { note in
                VStack(alignment: .leading, spacing: 2) {
                    if let category = note.category, !category.isEmpty {
                        Text(category)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(note.content)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func timesSection(_ context: PCOPlanContext) -> some View {
        Section("Times") {
            ForEach(context.times) { time in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(time.name?.isEmpty == false ? time.name! : Self.typeLabel(time.timeType))
                        Spacer()
                        Text(Self.typeLabel(time.timeType))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let starts = time.startsAt {
                        HStack(spacing: 6) {
                            Text(starts, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                            Text(range(starts, time.endsAt))
                                .font(.clock(.caption, weight: .regular))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func range(_ starts: Date, _ ends: Date?) -> String {
        let start = engine.clockFormat.string(from: starts)
        guard let ends else { return start }
        return "\(start) \u{2013} \(engine.clockFormat.string(from: ends))"
    }

    @ViewBuilder
    private func teamSections(_ context: PCOPlanContext) -> some View {
        let groups = Self.groupedTeam(context.team)
        ForEach(groups, id: \.name) { group in
            Section(group.name) {
                ForEach(group.people) { person in
                    personRow(person, context: context)
                }
            }
        }
    }

    private func personRow(_ person: PCOPlanPersonInfo, context: PCOPlanContext) -> some View {
        let status = TeamStatus(code: person.status)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                if let position = person.positionName, !position.isEmpty {
                    Text(position)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                let declined = Self.declinedTimeNames(person, context: context)
                if !declined.isEmpty {
                    Text("Declined: \(declined.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(AppPalette.negative)
                }
            }
            Spacer()
            Label(status.label, systemImage: status.symbol)
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.medium))
                .foregroundStyle(status.color)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func neededSection(_ context: PCOPlanContext) -> some View {
        Section("Needed Positions") {
            ForEach(Array(context.neededPositions.enumerated()), id: \.offset) { _, needed in
                HStack {
                    Text(needed.teamPositionReference ?? "Position")
                    Spacer()
                    Text("\u{00D7} \(needed.quantity)")
                        .font(.clock(.body, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private struct TeamStatus {
        let label: String
        let symbol: String
        let color: Color

        init(code: String) {
            switch code.uppercased() {
            case "C": self = TeamStatus(label: "Confirmed", symbol: "checkmark.circle.fill", color: AppPalette.positive)
            case "D": self = TeamStatus(label: "Declined", symbol: "xmark.circle.fill", color: AppPalette.negative)
            default: self = TeamStatus(label: "Unconfirmed", symbol: "questionmark.circle.fill", color: AppPalette.warning)
            }
        }

        private init(label: String, symbol: String, color: Color) {
            self.label = label
            self.symbol = symbol
            self.color = color
        }
    }

    private struct TeamGroup {
        let name: String
        let people: [PCOPlanPersonInfo]
    }

    private static func groupedTeam(_ team: [PCOPlanPersonInfo]) -> [TeamGroup] {
        var order: [String] = []
        var buckets: [String: [PCOPlanPersonInfo]] = [:]
        for person in team {
            let name = person.teamName?.isEmpty == false ? person.teamName! : "Team"
            if buckets[name] == nil { order.append(name) }
            buckets[name, default: []].append(person)
        }
        return order.map { TeamGroup(name: $0, people: buckets[$0] ?? []) }
    }

    private static func declinedTimeNames(_ person: PCOPlanPersonInfo, context: PCOPlanContext) -> [String] {
        guard !person.declinedPlanTimeIds.isEmpty else { return [] }
        return person.declinedPlanTimeIds.map { id in
            guard let time = context.times.first(where: { $0.id == id }) else { return "a time" }
            if let name = time.name, !name.isEmpty { return name }
            return typeLabel(time.timeType)
        }
    }

    private static func typeLabel(_ type: String) -> String {
        switch type.lowercased() {
        case "service": return "Event"
        case "rehearsal": return "Rehearsal"
        case "other": return "Other"
        default: return type.capitalized
        }
    }

    private static func duration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}

private extension View {
    @ViewBuilder
    func inspectorColumnWidthIfAvailable() -> some View {
        #if os(macOS)
        self.inspectorColumnWidth(min: 280, ideal: 340, max: 520)
        #else
        self.inspectorColumnWidth(min: 300, ideal: 360, max: 480)
        #endif
    }
}

struct RunSheetPlanInspectorModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.inspector(isPresented: $isPresented) {
            RunSheetPlanPanel()
        }
    }
}
#endif

enum RunSheetPlanPanelStorage {
    static let key = "runSheetPlanPanelVisible"
}
