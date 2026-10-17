// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

struct RunSheetTotalsView: View {
    @EnvironmentObject var engine: CueEngine
    let schedule: RunSheetSchedule

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                if engine.isRehearsalMode {
                    RehearsalBadge()
                }
                total("Planned", duration(schedule.plannedLength))
                if let plannedEnd = schedule.plannedEnd {
                    total("Ends", clock(plannedEnd))
                    if let projectedEnd = schedule.projectedEnd, hasDrift {
                        total("Projected", clock(projectedEnd), tint: driftColor)
                    }
                    if let overUnder = schedule.overUnderSeconds {
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
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.clock(.callout, weight: .medium))
                .foregroundStyle(tint)
        }
    }

    private func duration(_ seconds: Int) -> String {
        TimeFormatting.string(forSeconds: seconds, threshold: engine.hourFormatThreshold)
    }

    private func clock(_ date: Date) -> String {
        engine.clockFormat.string(from: date)
    }
}
