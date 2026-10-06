// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct LiveTimerHeaderView: View {
    @EnvironmentObject var engine: CueEngine
    @State private var isEditingTimer: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 10) {
            if !engine.isLANConnected {
                Label("Not connected to the LAN cue network — retrying in the background", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = engine.pcoLastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button(action: { engine.previousPlanItem() }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .help("Previous item")

                VStack(spacing: 2) {
                    Text(engine.activeTimerItem?.servicePlanTitle ?? "Sunday Service")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(engine.activeTimerItem?.title ?? "No Item Selected")
                        .font(.headline)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                if engine.isAtEndOfPlan && engine.canLoadNextService {
                    Button(action: { engine.loadNextService() }) {
                        Label("Next Service", systemImage: "calendar.badge.clock")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Load the next scheduled service from Planning Center")
                } else {
                    Button(action: { engine.nextPlanItem() }) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    .disabled(engine.isAtEndOfPlan)
                    .help("Next item")
                }
            }

            if let item = engine.activeTimerItem {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Remaining")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            projectedActualPicker(item)
                        }

                        remainingTimeControl(item)
                    }

                    Spacer()

                    ControlGroup {
                        Button("+1m") { engine.adjustTimerRemainingTime(bySeconds: 60) }
                            .help("Add 1 minute")
                        Button("+30s") { engine.adjustTimerRemainingTime(bySeconds: 30) }
                            .help("Add 30 seconds")
                        Button("−30s") { engine.adjustTimerRemainingTime(bySeconds: -30) }
                            .help("Subtract 30 seconds")
                        Button("−1m") { engine.adjustTimerRemainingTime(bySeconds: -60) }
                            .help("Subtract 1 minute")
                    }
                    .controlGroupStyle(.automatic)

                    Button(action: { engine.toggleTimerRunning() }) {
                        Image(systemName: item.isRunning ? "pause.fill" : "play.fill")
                            .frame(width: 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(item.isRunning ? .blue : .green)
                    .help(item.isRunning ? "Pause the timer" : "Start the timer")

                    Button(action: { engine.resetTimer() }) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .help("Reset elapsed time")
                }
            }
        }
    }

    private func projectedActualPicker(_ item: PCOTimerItem) -> some View {
        Picker("", selection: Binding(
            get: { engine.activeTimerActualForDisplay },
            set: { isActual in
                engine.setActiveTimerActualOverride(isActual)
                if isActual {
                    isEditingTimer = true
                }
            }
        )) {
            Text("Projected").tag(false)
            Text("Actual").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 160)
        .help("Actual is a temporary override for when you know the real time from outside the plan — e.g. a stream delay — Projected is the plan's own projection.")
    }

    @ViewBuilder
    private func remainingTimeControl(_ item: PCOTimerItem) -> some View {
        Text(TimeFormatting.string(forSeconds: item.remainingSeconds, threshold: engine.hourFormatThreshold))
            .font(.inter(size: 32, weight: .bold))
            .foregroundStyle(isEditingTimer ? Color.primary : (item.isOvertime ? .red : .primary))
            #if !os(tvOS)
            .contentTransition(.numericText())
            #endif
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(isEditingTimer ? Color.accentColor.opacity(0.35) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isEditingTimer else { return }
                isEditingTimer = true
            }
            .timeEntryPopover(
                isPresented: $isEditingTimer,
                previewBaseSeconds: item.remainingSeconds,
                hourFormatThreshold: engine.hourFormatThreshold
            ) { action in
                switch action {
                case .setAbsolute(let seconds):
                    engine.setTimerRemainingTime(seconds: seconds)
                case .adjustRelative(let delta):
                    engine.adjustTimerRemainingTime(bySeconds: delta)
                }
            }
    }
}
