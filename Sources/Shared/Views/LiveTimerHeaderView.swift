// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

private struct DocumentSaveIndicatorKey: EnvironmentKey {
    static let defaultValue: DocumentSaveIndicator? = nil
}

public extension EnvironmentValues {
    var documentSaveIndicator: DocumentSaveIndicator? {
        get { self[DocumentSaveIndicatorKey.self] }
        set { self[DocumentSaveIndicatorKey.self] = newValue }
    }
}

private struct DocumentSaveStatusLabel: View {
    @ObservedObject var indicator: DocumentSaveIndicator

    var body: some View {
        let status = indicator.status
        let label = Text(status.text)
            .font(.system(size: 10))
            .foregroundStyle(status == .failed ? AppPalette.warning : Color.secondary.opacity(0.8))
            .lineLimit(1)
        if status.isActionable {
            Button(action: { indicator.onActivate?() }) { label }
                .buttonStyle(.plain)
                .accessibilityLabel(status.text)
        } else {
            label.accessibilityLabel("Document \(status.text)")
        }
    }
}

public struct LiveTimerHeaderView: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.documentSaveIndicator) private var saveIndicator
    @State private var isEditingTimer: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 10) {
            if !engine.isLANConnected {
                Label("Not connected to the LAN cue network — retrying in the background", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(AppPalette.negative)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = engine.pcoLastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppPalette.warning)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                HStack {
                    #if os(macOS)
                    Color.clear.frame(width: engine.isRemoteMirror ? 1 : 64, height: 1)
                    #endif
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 2) {
                    #if os(macOS)
                    Text(engine.isRemoteMirror ? (engine.remoteProducerName ?? "Remote Producer") : (engine.currentDocumentURL?.deletingPathExtension().lastPathComponent ?? "Untitled"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    #endif
                    if !engine.isRemoteMirror, let saveIndicator {
                        DocumentSaveStatusLabel(indicator: saveIndicator)
                    }
                    Text(engine.activeTimerItem?.title ?? "No Item Selected")
                        .font(.system(size: 20, weight: .heavy))
                        .textCase(.uppercase)
                        .lineLimit(1)
                    if let item = engine.activeTimerItem {
                        remainingTimeControl(item)
                        projectedActualPicker(item)
                    }
                }

                VStack(alignment: .trailing, spacing: 8) {
                    if engine.activeTimerItem != nil {
                        HStack(spacing: 8) {
                            Button(action: { engine.previousPlanItem() }) {
                                Image(systemName: "chevron.left").font(.title2.weight(.semibold)).frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .producerSecondaryButton()
                            .disabled(engine.isAtStartOfPlan)
                            .help("Previous item")

                            if let item = engine.activeTimerItem {
                                Button(action: { engine.toggleTimerRunning() }) {
                                    Image(systemName: item.isRunning ? "pause.fill" : "play.fill")
                                        .font(.title2)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .producerButtonShape()
                                .tint(item.isRunning ? AppPalette.info : AppPalette.positive)
                                .help(item.isRunning ? "Pause the timer" : "Start the timer")

                                Button(action: { engine.resetTimer() }) {
                                    Image(systemName: "arrow.counterclockwise").font(.title2).frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .producerSecondaryButton()
                                .help("Reset elapsed time")
                            }

                            if engine.isAtEndOfPlan && engine.canAdvanceToNextEventTime {
                                let nextName = engine.nextEventTime?.displayName(engine.clockFormat) ?? "the next event time"
                                Button(action: { engine.advanceToNextEventTime() }) {
                                    Image(systemName: "arrow.uturn.forward").font(.title2.weight(.semibold)).frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .producerButtonShape()
                                .disabled(engine.isChangingEventTime)
                                .accessibilityLabel("Start \(nextName)")
                                .help("Start \(nextName): make it live and return to the top of the run sheet")
                            } else if engine.isAtEndOfPlan && engine.canLoadNextService {
                                Button(action: { engine.loadNextService() }) {
                                    Image(systemName: "calendar.badge.clock").font(.title2.weight(.semibold)).frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .producerButtonShape()
                                .accessibilityLabel("Load the next event")
                                .help("Load the next scheduled event from Planning Center")
                            } else {
                                Button(action: { engine.nextPlanItem() }) {
                                    Image(systemName: "chevron.right").font(.title2.weight(.semibold)).frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .producerSecondaryButton()
                                .disabled(engine.isAtEndOfPlan)
                                .help("Next item")
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                    cueButtons
                }
                .frame(width: 340)
                .frame(maxHeight: .infinity)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cueButtons: some View {
        let count = engine.selectedRoleIds.count
        return HStack(spacing: 8) {
            Button(action: { engine.setCueForSelectedRoles(.standby) }) {
                Text("STANDBY")
                    .font(.system(size: 13, weight: .black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .frame(maxHeight: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .producerButtonShape()
            .tint(AppPalette.cueStandby)
            .foregroundStyle(.black)
            .help("Set STANDBY for the \(count) selected role(s)")

            Button(action: { engine.setCueForSelectedRoles(.go) }) {
                Text("GO!")
                    .font(.system(size: 13, weight: .black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .frame(maxHeight: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .producerButtonShape()
            .tint(AppPalette.cueGo)
            .help("Set GO for the \(count) selected role(s)")

            Button(action: { engine.setCueForSelectedRoles(.off) }) {
                Text("CLEAR")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .frame(maxHeight: .infinity)
            }
            .producerSecondaryButton()
            .help("Clear the cue for the \(count) selected role(s)")
        }
        .frame(maxHeight: .infinity)
    }

    private func projectedActualPicker(_ item: PCOTimerItem) -> some View {
        Picker("", selection: Binding(
            get: { engine.activeTimerActualForDisplay },
            set: { isActual in
                engine.setActiveTimerActualOverride(isActual)
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
            .font(.inter(size: 52, weight: .black))
            .foregroundStyle(isEditingTimer ? Color.primary : (item.isOvertime ? AppPalette.timerOvertime : .primary))
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
                previewElapsedSeconds: item.elapsedSeconds,
                hourFormatThreshold: engine.hourFormatThreshold,
                clockFormat: engine.clockFormat
            ) { action in
                switch action {
                case .setAbsolute(let seconds):
                    engine.setTimerRemainingTime(seconds: seconds)
                case .adjustRelative(let delta):
                    engine.adjustTimerRemainingTime(bySeconds: delta)
                case .endAt(let time):
                    engine.setTimerRemainingTime(seconds: time.secondsUntil(now: Date()))
                }
            }
    }
}
