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

    private var planName: String {
        engine.pcoPlanContext?.title ?? engine.planTitle ?? "No plan"
    }

    private var hasPCOPlan: Bool { engine.planItems.first?.pcoPlanId != nil }
    private var canRehearse: Bool { engine.isRehearsalMode || !engine.rehearsalPlanTimes.isEmpty }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            planMenu
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

    /// One menu for the whole plan: which event time is running, changing the plan, rehearsal and live sync.
    private var planMenu: some View {
        Menu {
            if engine.isRehearsalMode {
                if engine.rehearsalPlanTimes.count > 1 {
                    Section("Rehearsal Time") {
                        Picker("Rehearsal Time", selection: Binding(
                            get: { engine.rehearsalPlanTimeId ?? "" },
                            set: { engine.setRehearsalMode(true, planTimeId: $0) }
                        )) {
                            ForEach(engine.rehearsalPlanTimes) { time in
                                Text(rehearsalLabel(for: time)).tag(time.id)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
            } else if engine.eventTimes.count > 1 {
                Section("Event Time") {
                    Picker("Live Event Time", selection: Binding(
                        get: { engine.liveEventTime?.id ?? "" },
                        set: { id in
                            guard !id.isEmpty else { return }
                            engine.setLiveEventTime(id: id)
                        }
                    )) {
                        ForEach(engine.eventTimes) { time in
                            Text(time.displayName(engine.clockFormat)).tag(time.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .disabled(engine.isChangingEventTime)
                }
            }

            Section("Plan") {
                Button(engine.isPCOConnected ? "Change Plan\u{2026}" : "Sync PCO\u{2026}") {
                    engine.whenPCOConnected { showingPlanPicker = true }
                }
                Button("Event Times\u{2026}") { showingEventTimes = true }
                Button(planPanelVisible ? "Hide Plan Details" : "Show Plan Details") { planPanelVisible.toggle() }
                if let raw = engine.pcoPlanContext?.planningCenterURL, let url = URL(string: raw) {
                    Button("Open in Planning Center") { openURL(url) }
                }
            }

            Section("Mode") {
                if canRehearse {
                    Toggle("Rehearsal Mode", isOn: Binding(
                        get: { engine.isRehearsalMode },
                        set: { engine.setRehearsalMode($0) }
                    ))
                } else {
                    Toggle("Rehearsal Mode", isOn: .constant(false))
                        .disabled(true)
                }
                if hasPCOPlan {
                    Toggle("Sync with PCO Live", isOn: Binding(
                        get: { engine.isPCOLiveSyncEnabled },
                        set: { $0 ? engine.enablePCOLiveSync() : engine.disablePCOLiveSync() }
                    ))
                    .disabled(engine.isRehearsalMode)
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(planName)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                    if let time = currentTimeText {
                        Text(time)
                            .font(.clock(.callout, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Plan and event time: switch event, change the plan, rehearse, or sync with Planning Center Live")
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
#endif
