// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

/// A labeled figure: small caps label over a clock-font value. Shared by the footer and the header summary.
struct RunSheetTotalFigure: View {
    let label: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.clock(.callout, weight: .medium))
                .foregroundStyle(tint)
        }
    }
}

struct RunSheetTotalsView: View {
    @EnvironmentObject var engine: CueEngine
    let schedule: RunSheetSchedule
    /// Planned, Ends and Pace. The macOS header shows these, so its footer keeps only the rest.
    var showsSummary = true

    private var hasExtras: Bool {
        schedule.plannedEnd == nil || hasDrift || schedule.actualElapsedSeconds > 0 || engine.isRehearsalMode
    }

    var body: some View {
        if showsSummary || hasExtras { footer }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                if engine.isRehearsalMode {
                    RehearsalBadge()
                }
                if showsSummary { total("Planned", duration(schedule.plannedLength)) }
                if let plannedEnd = schedule.plannedEnd {
                    if showsSummary { total("Ends", clock(plannedEnd)) }
                    if let projectedEnd = schedule.projectedEnd, hasDrift {
                        total("Projected", clock(projectedEnd), tint: driftColor)
                    }
                    if showsSummary, let overUnder = schedule.overUnderSeconds {
                        overUnderView(overUnder)
                    }
                } else {
                    Text(engine.eventTimes.isEmpty ? "Add an event time to see start and end times." : "Set a start time on the live event time to see start and end times.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if schedule.actualElapsedSeconds > 0 {
                    total("Actual", duration(schedule.actualElapsedSeconds))
                    if let drift = schedule.actualDriftSeconds, abs(drift) >= RunSheetActualStyle.lengthThreshold {
                        total("Drift", RunSheetActualStyle.signed(drift, threshold: engine.hourFormatThreshold), tint: RunSheetActualStyle.color(forDelta: drift))
                    }
                }
                Spacer(minLength: 0)
                if let label = engine.liveEventTimeLabel, engine.eventTimes.count > 1, !engine.isRehearsalMode {
                    Label(label, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        #if os(tvOS)
        .background(AppPalette.scrimFaint)
        #else
        .background(.bar)
        #endif
    }

    private var hasDrift: Bool {
        guard let overUnder = schedule.overUnderSeconds else { return false }
        return abs(overUnder) >= RunSheetSchedule.driftThreshold
    }

    private var driftColor: Color {
        (schedule.overUnderSeconds ?? 0) > 0 ? AppPalette.driftLate : AppPalette.driftEarly
    }

    @ViewBuilder
    private func overUnderView(_ seconds: Int) -> some View {
        if abs(seconds) < RunSheetSchedule.driftThreshold {
            total("Pace", "On time")
        } else {
            total(seconds > 0 ? "Over" : "Under", duration(abs(seconds)), tint: driftColor)
        }
    }

    private func total(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        RunSheetTotalFigure(label: label, value: value, tint: tint)
    }

    private func duration(_ seconds: Int) -> String {
        TimeFormatting.string(forSeconds: seconds, threshold: engine.hourFormatThreshold)
    }

    private func clock(_ date: Date) -> String {
        engine.clockFormat.string(from: date)
    }
}
