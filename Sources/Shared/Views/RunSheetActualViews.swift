// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

enum RunSheetActualStyle {
    static let lengthThreshold = 5

    static func signed(_ seconds: Int, threshold: HourFormatThreshold) -> String {
        let text = TimeFormatting.string(forSeconds: abs(seconds), threshold: threshold)
        return seconds < 0 ? "\u{2212}\(text)" : "+\(text)"
    }

    static func color(forDelta delta: Int?) -> Color {
        guard let delta, abs(delta) >= lengthThreshold else { return .secondary }
        return delta > 0 ? AppPalette.driftLate : AppPalette.driftEarly
    }
}

struct RunSheetActualText: View {
    @EnvironmentObject var engine: CueEngine
    let entry: RunSheetSchedule.Entry
    var compact = true

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let actual = entry.actualLength {
                HStack(spacing: 4) {
                    Text(format(actual))
                        .foregroundStyle(entry.isActualComplete ? Color.primary : Color.accentColor)
                    if let delta = entry.actualDeltaSeconds, abs(delta) >= RunSheetActualStyle.lengthThreshold {
                        Text(RunSheetActualStyle.signed(delta, threshold: engine.hourFormatThreshold))
                            .foregroundStyle(RunSheetActualStyle.color(forDelta: delta))
                    }
                }
                .font(.clock(compact ? .caption2 : .caption, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .help(entry.isActualComplete ? "Actual time spent on this item" : "Time spent on this item so far")
            }
            if let pco = entry.pcoActualLength {
                Text("PCO \(format(pco))")
                    .font(.clock(.caption2, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .help("Planning Center recorded \(format(pco)) for this item")
            }
        }
    }

    private func format(_ seconds: Int) -> String {
        TimeFormatting.string(forSeconds: seconds, threshold: engine.hourFormatThreshold)
    }
}

struct RehearsalBadge: View {
    @EnvironmentObject var engine: CueEngine

    var body: some View {
        if engine.isRehearsalMode {
            Label(engine.rehearsalLabel, systemImage: "theatermasks")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.rehearsal)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppPalette.rehearsal.opacity(0.15), in: Capsule())
                .lineLimit(1)
                .help("Rehearsal mode: actual times aren't recorded and Planning Center Live isn't stepped")
        }
    }
}

struct RehearsalControl: View {
    @EnvironmentObject var engine: CueEngine

    var body: some View {
        if engine.isRehearsalMode || !engine.rehearsalPlanTimes.isEmpty {
            HStack(spacing: 12) {
                Toggle(isOn: Binding(
                    get: { engine.isRehearsalMode },
                    set: { engine.setRehearsalMode($0) }
                )) {
                    Label("Rehearsal Mode", systemImage: "theatermasks")
                }
                .help("Run the sheet against a rehearsal time: nothing is recorded and Planning Center Live isn't stepped. Turning it off returns to the live event time.")

                if engine.isRehearsalMode, engine.rehearsalPlanTimes.count > 1 {
                    Picker(selection: Binding(
                        get: { engine.rehearsalPlanTimeId ?? "" },
                        set: { engine.setRehearsalMode(true, planTimeId: $0) }
                    )) {
                        ForEach(engine.rehearsalPlanTimes) { time in
                            Text(label(for: time)).tag(time.id)
                        }
                    } label: {
                        Text("Rehearsal Time")
                    }
                    .fixedSize()
                }
            }
        }
    }

    private func label(for time: PCOPlanTimeInfo) -> String {
        let start = time.startsAt.map { engine.clockFormat.string(from: $0) }
        return [time.name, start].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }
}

struct RunSheetActualsMenu: View {
    @EnvironmentObject var engine: CueEngine
    @State private var confirmingSave = false

    var body: some View {
        let changes = engine.actualLengthChanges()
        Menu {
            if engine.planItems.first?.pcoPlanId != nil {
                Button {
                    confirmingSave = true
                } label: {
                    Label("Save Actual Lengths to PCO Plan\u{2026}", systemImage: "square.and.arrow.up")
                }
                .disabled(changes.isEmpty)
            }
            Button(role: .destructive) {
                engine.clearActuals()
            } label: {
                Label("Clear Actuals", systemImage: "eraser")
            }
            .disabled(engine.itemActuals.isEmpty)
        } label: {
            Label("Actuals", systemImage: "stopwatch")
        }
        .help("Actual times recorded while the event runs")
        .confirmationDialog(
            "Save actual lengths to Planning Center?",
            isPresented: $confirmingSave,
            titleVisibility: .visible
        ) {
            Button("Save \(changes.count) \(changes.count == 1 ? "Length" : "Lengths")") {
                engine.saveActualLengthsToPCO()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message(for: changes))
        }
    }

    private func message(for changes: [ActualLengthChange]) -> String {
        let format = { (seconds: Int) in TimeFormatting.string(forSeconds: seconds, threshold: engine.hourFormatThreshold) }
        var lines = changes.prefix(6).map { "\($0.title): \(format($0.plannedSeconds)) to \(format($0.actualSeconds))" }
        if changes.count > lines.count { lines.append("and \(changes.count - lines.count) more") }
        let summary = "\(changes.count) \(changes.count == 1 ? "item" : "items") will change."
        return ([summary] + lines + ["This changes the planned length in Planning Center for every event time of this plan."])
            .joined(separator: "\n")
    }
}
