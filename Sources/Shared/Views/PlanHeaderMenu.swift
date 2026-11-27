// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS) || os(iOS)
import SwiftUI

/// The left side of the app header: which plan and event is running, and whether the Producer is
/// driving Planning Center Live or rehearsing. The plan name is a menu for everything that changes the plan.
struct PlanHeaderMenu: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.openURL) private var openURL
    @AppStorage(RunSheetPlanPanelStorage.key) private var planPanelVisible = false
    @State private var showingPlanPicker = false
    @State private var showingEventTimes = false
    @State private var showingPopover = false
    @State private var confirmingUnlink = false
    @State private var addingTime: PlanTimeKind?

    private var planName: String {
        engine.pcoPlanContext?.title ?? engine.planTitle ?? "Unnamed Run Sheet"
    }

    private var hasPCOPlan: Bool { engine.planItems.first?.pcoPlanId != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                planMenu
                statusTag
            }
            timeCard
                .frame(width: 118)
            summary
        }
        .sheet(isPresented: $showingPlanPicker) { PCOPlanPickerView() }
        .sheet(isPresented: $showingEventTimes) { EventTimesView() }
        .sheet(item: $addingTime) { kind in
            EventTimeEditorView(target: .add, isRehearsal: kind == .rehearsal)
        }
        .confirmationDialog("Run this plan only in 13 Years?", isPresented: $confirmingUnlink, titleVisibility: .visible) {
            Button("Unlink from Planning Center", role: .destructive) { engine.unlinkPCOPlan() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Items, notes, event times and rehearsal times stay and become yours to edit here. Planning Center changes stop syncing, and Live control and saving actual lengths back end. Sync a plan again to relink.")
        }
    }

    /// The running event or rehearsal, in the same card the plan popover shows. Click it to change.
    @ViewBuilder
    private var timeCard: some View {
        let card = Group {
            if engine.isRehearsalMode {
                let time = engine.rehearsalPlanTimes.first(where: { $0.id == engine.rehearsalPlanTimeId })
                let name = time?.name.flatMap { $0.isEmpty ? nil : $0 }
                PlanTimeCard(
                    title: name ?? time?.startsAt.map { Self.dayFormatter.string(from: $0) } ?? "Rehearsal",
                    detail: nil,
                    time: time?.startsAt.map { engine.clockFormat.string(from: $0) } ?? "Rehearsal",
                    badge: "REHEARSING",
                    tint: AppPalette.rehearsal,
                    isSelected: true,
                    fill: AppPalette.rehearsalFill
                )
            } else if let time = engine.liveEventTime ?? engine.eventTimes.first {
                let isLive = engine.liveEventTime != nil
                PlanTimeCard(
                    title: time.name ?? time.day?.formatted ?? "",
                    detail: time.name != nil ? time.day?.formatted : nil,
                    time: time.startTime?.formatted(engine.clockFormat) ?? time.name ?? "Event",
                    badge: isLive ? "LIVE" : nil,
                    tint: AppPalette.positive,
                    isSelected: isLive
                )
            }
        }
        if engine.isRehearsalMode || engine.liveEventTime != nil || !engine.eventTimes.isEmpty {
            Button { showingPopover.toggle() } label: { card }
                .buttonStyle(.plain)
                .help("Change the event time or rehearse")
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()

    /// Planned length, planned end and pace, moved up from the run sheet footer so every screen shows them.
    @ViewBuilder
    private var summary: some View {
        if engine.planItems.contains(where: { !$0.isHeader }) {
            let schedule = engine.runSheetSchedule()
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                RunSheetTotalFigure(label: "Planned", value: duration(schedule.plannedLength))
                if let end = schedule.plannedEnd {
                    RunSheetTotalFigure(label: "Ends", value: engine.clockFormat.string(from: end))
                    if let seconds = schedule.overUnderSeconds {
                        if abs(seconds) < RunSheetSchedule.driftThreshold {
                            RunSheetTotalFigure(label: "Pace", value: "On time")
                        } else {
                            RunSheetTotalFigure(
                                label: seconds > 0 ? "Over" : "Under",
                                value: duration(abs(seconds)),
                                tint: seconds > 0 ? AppPalette.driftLate : AppPalette.driftEarly
                            )
                        }
                    }
                }
            }
            .padding(.leading, 5)
        }
    }

    private func duration(_ seconds: Int) -> String {
        TimeFormatting.string(forSeconds: seconds, threshold: engine.hourFormatThreshold)
    }

    /// One popover for the whole plan: event times as cards, rehearsal times beneath, live sync, plan actions.
    private var planMenu: some View {
        Button {
            showingPopover.toggle()
        } label: {
            HStack(alignment: .center, spacing: 6) {
                Text(planName)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: TimeEntryPopoverDefaults.arrowEdge) {
            PlanPopover(
                planName: planName,
                isLinked: engine.isLinkedToPCOPlan,
                subtitle: engine.pcoPlanContext?.dates,
                hasPCOPlan: hasPCOPlan,
                planPanelVisible: $planPanelVisible,
                onChangePlan: {
                    showingPopover = false
                    engine.whenPCOConnected { showingPlanPicker = true }
                },
                onEventTimes: {
                    showingPopover = false
                    showingEventTimes = true
                },
                onAddTime: { kind in
                    showingPopover = false
                    addingTime = kind
                },
                onUnlink: {
                    showingPopover = false
                    confirmingUnlink = true
                },
                onOpenInPCO: {
                    if let raw = engine.pcoPlanContext?.planningCenterURL, let url = URL(string: raw) { openURL(url) }
                }
            )
            .environmentObject(engine)
        }
        .help("Plan and event time: switch event, rehearse, change the plan, or sync with Planning Center Live")
    }

    /// The PCO Live tag. Rehearsal shows as the purple card instead, since you are either rehearsing or in the event.
    @ViewBuilder
    private var statusTag: some View {
        if engine.isPCOLiveSyncEnabled && !engine.isRehearsalMode {
            Label("PCO Live", systemImage: "dot.radiowaves.left.and.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppPalette.positive)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppPalette.positive.opacity(0.18), in: Capsule())
                .help("This app is controlling Planning Center Live")
        }
    }

    private func rehearsalLabel(for time: PCOPlanTimeInfo) -> String {
        let start = time.startsAt.map { engine.clockFormat.string(from: $0) }
        return [time.name, start].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }
}

private struct PlanPopover: View {
    @EnvironmentObject var engine: CueEngine
    let planName: String
    let isLinked: Bool
    let subtitle: String?
    let hasPCOPlan: Bool
    @Binding var planPanelVisible: Bool
    let onChangePlan: () -> Void
    let onEventTimes: () -> Void
    let onAddTime: (PlanTimeKind) -> Void
    let onUnlink: () -> Void
    let onOpenInPCO: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if isLinked {
                    Text(planName).font(.headline).lineLimit(2)
                } else {
                    PlanNameField()
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }

            section("Event", addKind: .event) {
                if engine.eventTimes.isEmpty {
                    emptyNote(isLinked ? "This plan has no service times in Planning Center." : "No event times yet.")
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(engine.eventTimes) { time in
                            eventCard(time)
                        }
                    }
                }
            }

            section("Rehearsal", addKind: .rehearsal) {
                if engine.rehearsalPlanTimes.isEmpty {
                    emptyNote(isLinked ? "This plan has no rehearsal time in Planning Center." : "No rehearsal times yet.")
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(engine.rehearsalPlanTimes) { time in
                            rehearsalCard(time)
                        }
                    }
                }
            }

            if hasPCOPlan {
                Divider()
                Toggle(isOn: Binding(
                    get: { engine.isPCOLiveSyncEnabled },
                    set: { $0 ? engine.enablePCOLiveSync() : engine.disablePCOLiveSync() }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sync with PCO Live")
                        Text(engine.isRehearsalMode ? "Off while rehearsing" : "Controls Planning Center Live")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(engine.isRehearsalMode)
            }

            Divider()
            ChipFlowLayout {
                Button(action: onChangePlan) {
                    Label(engine.isPCOConnected ? "Change plan" : "Sync PCO", systemImage: "arrow.triangle.2.circlepath")
                }
                Button(action: onEventTimes) {
                    Label("Event times", systemImage: "clock")
                }
                Button { planPanelVisible.toggle() } label: {
                    Label(planPanelVisible ? "Hide details" : "Details", systemImage: "sidebar.trailing")
                }
                PlanActualsActions()
                if engine.pcoPlanContext?.planningCenterURL != nil {
                    Button(action: onOpenInPCO) {
                        Label("Planning Center", systemImage: "arrow.up.right.square")
                    }
                }
                if engine.isLinkedToPCOPlan {
                    Button(role: .destructive, action: onUnlink) {
                        Label("Unlink", systemImage: "link.badge.minus")
                    }
                    .help("Stop syncing with Planning Center and run this plan only in 13 Years")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 330)
    }

    private func section<Content: View>(_ title: String, addKind: PlanTimeKind, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                Spacer()
                if !isLinked {
                    Button { onAddTime(addKind) } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .help(addKind == .event ? "Add an event time" : "Add a rehearsal time")
                    .accessibilityLabel(addKind == .event ? "Add event time" : "Add rehearsal time")
                }
            }
            content()
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func eventCard(_ time: EventTime) -> some View {
        let isSelected = !engine.isRehearsalMode && engine.liveEventTime?.id == time.id
        return Button {
            if engine.isRehearsalMode { engine.setRehearsalMode(false) }
            if engine.liveEventTime?.id != time.id { engine.setLiveEventTime(id: time.id) }
        } label: {
            PlanTimeCard(
                title: time.name ?? time.day?.formatted ?? "",
                detail: time.name != nil ? time.day?.formatted : nil,
                time: time.startTime?.formatted(engine.clockFormat) ?? time.name ?? "Event",
                badge: isSelected ? "LIVE" : nil,
                tint: AppPalette.positive,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .disabled(engine.isChangingEventTime)
    }

    private func rehearsalCard(_ time: PCOPlanTimeInfo) -> some View {
        let isSelected = engine.isRehearsalMode && engine.rehearsalPlanTimeId == time.id
        return Button {
            engine.setRehearsalMode(true, planTimeId: time.id)
        } label: {
            PlanTimeCard(
                title: time.name.flatMap { $0.isEmpty ? nil : $0 } ?? time.startsAt.map { Self.dayFormatter.string(from: $0) } ?? "",
                detail: time.name.flatMap { $0.isEmpty ? nil : $0 } != nil ? time.startsAt.map { Self.dayFormatter.string(from: $0) } : nil,
                time: time.startsAt.map { engine.clockFormat.string(from: $0) } ?? "Rehearsal",
                badge: isSelected ? "REHEARSING" : nil,
                tint: AppPalette.rehearsal,
                isSelected: isSelected,
                fill: AppPalette.rehearsalFill
            )
        }
        .buttonStyle(.plain)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()
}

/// Which kind of time to add from the plan popover. Both open the same editor.
enum PlanTimeKind: String, Identifiable {
    case event
    case rehearsal
    var id: String { rawValue }
}

/// An event or rehearsal time as a card: the name or day small on top, the time large in the clock font and a
/// bold badge beneath (LIVE, REHEARSING), outlined in its color when it is the one running. Used in the plan
/// popover and in the header, so they read the same.
struct PlanTimeCard: View {
    let title: String
    let detail: String?
    let time: String
    let badge: String?
    let tint: Color
    let isSelected: Bool
    var fill: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption)
                .foregroundStyle(fill == nil ? Color.secondary : tint)
                .lineLimit(1)
            Text(time)
                .font(.clock(.title3, weight: .semibold))
            if let badge {
                Text(badge)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(tint)
            } else {
                Text(detail ?? " ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill ?? Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(isSelected ? tint : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
    }
}

/// The plan's name, editable when it is not linked to Planning Center. Saved on Return or when focus leaves.
private struct PlanNameField: View {
    @EnvironmentObject var engine: CueEngine
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name this run sheet", text: $draft)
            .textFieldStyle(.plain)
            .font(.headline)
            .focused($focused)
            .onAppear { draft = engine.planTitle ?? "" }
            .onSubmit { engine.setPlanTitle(draft) }
            .onChange(of: focused) { _, isFocused in if !isFocused { engine.setPlanTitle(draft) } }
            .onChange(of: engine.planTitle) { _, title in if !focused { draft = title ?? "" } }
            .help("Name this run sheet")
    }
}
#endif
