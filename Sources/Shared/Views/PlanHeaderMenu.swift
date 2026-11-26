// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS)
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

    private var planName: String {
        engine.pcoPlanContext?.title ?? engine.planTitle ?? "No plan"
    }

    private var hasPCOPlan: Bool { engine.planItems.first?.pcoPlanId != nil }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // A Menu label collapses to its first Text on macOS, so the time is a sibling, not part of the label.
            VStack(alignment: .leading, spacing: 1) {
                planMenu
                if let time = currentTimeText {
                    Text(time)
                        .font(.clock(.callout, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.leading, 5)
                }
            }
            statusTag
        }
        .sheet(isPresented: $showingPlanPicker) { PCOPlanPickerView() }
        .sheet(isPresented: $showingEventTimes) { EventTimesView() }
    }

    /// The time shown under the plan name: the rehearsal time while rehearsing, otherwise the live event time.
    private var currentTimeText: String? {
        if engine.isRehearsalMode {
            return engine.rehearsalLabel.replacingOccurrences(of: "Rehearsal \u{00B7} ", with: "")
        }
        return engine.liveEventTime?.displayName(engine.clockFormat) ?? engine.eventTimes.first?.displayName(engine.clockFormat)
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
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            PlanPopover(
                planName: planName,
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
                onOpenInPCO: {
                    if let raw = engine.pcoPlanContext?.planningCenterURL, let url = URL(string: raw) { openURL(url) }
                }
            )
            .environmentObject(engine)
        }
        .help("Plan and event time: switch event, rehearse, change the plan, or sync with Planning Center Live")
    }

    /// Rehearsal replaces the PCO Live tag: you are either rehearsing or in the event.
    @ViewBuilder
    private var statusTag: some View {
        if engine.isRehearsalMode {
            Label("Rehearsal", systemImage: "theatermasks")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppPalette.rehearsal)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppPalette.rehearsalFill, in: Capsule())
                .help("Rehearsal mode: actual times aren't recorded and Planning Center Live isn't stepped")
        } else if engine.isPCOLiveSyncEnabled {
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
    let subtitle: String?
    let hasPCOPlan: Bool
    @Binding var planPanelVisible: Bool
    let onChangePlan: () -> Void
    let onEventTimes: () -> Void
    let onOpenInPCO: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(planName).font(.headline).lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }

            if !engine.eventTimes.isEmpty {
                section("Event") {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(engine.eventTimes) { time in
                            eventCard(time)
                        }
                    }
                }
            }

            section("Rehearsal") {
                if engine.rehearsalPlanTimes.isEmpty {
                    if engine.isEventTimesManagedByPCO {
                        Text("This plan has no rehearsal time in Planning Center.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if engine.isRemoteMirror {
                        Text("No rehearsal times on this Producer. Add them there.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button(action: onEventTimes) {
                            Label("Add a rehearsal time", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
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
                if engine.pcoPlanContext?.planningCenterURL != nil {
                    Button(action: onOpenInPCO) {
                        Label("Planning Center", systemImage: "arrow.up.right.square")
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 330)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
            content()
        }
    }

    private func eventCard(_ time: EventTime) -> some View {
        let isSelected = !engine.isRehearsalMode && engine.liveEventTime?.id == time.id
        return Button {
            if engine.isRehearsalMode { engine.setRehearsalMode(false) }
            if engine.liveEventTime?.id != time.id { engine.setLiveEventTime(id: time.id) }
        } label: {
            card(
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
            card(
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

    private func card(title: String, detail: String?, time: String, badge: String?, tint: Color, isSelected: Bool, fill: Color? = nil) -> some View {
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

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()
}
#endif
