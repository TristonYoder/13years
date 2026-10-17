// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

struct PCOLiveSyncToggle: View {
    @EnvironmentObject var engine: CueEngine

    var body: some View {
        Toggle(isOn: Binding(
            get: { engine.isPCOLiveSyncEnabled },
            set: { newValue in
                if newValue {
                    engine.enablePCOLiveSync()
                } else {
                    engine.disablePCOLiveSync()
                }
            }
        )) {
            Label("Sync with PCO Live", systemImage: "dot.radiowaves.left.and.right")
        }
    }

    static var explanation: String {
        "Takes control of Planning Center Live and mirrors item navigation to it. Only use this on the plan you're actually running."
    }
}

struct LiveEventTimePicker: View {
    @EnvironmentObject var engine: CueEngine

    var body: some View {
        Picker(selection: Binding(
            get: { engine.liveEventTime?.id ?? "" },
            set: { id in
                guard !id.isEmpty else { return }
                engine.setLiveEventTime(id: id)
            }
        )) {
            ForEach(engine.eventTimes) { time in
                Text(time.displayName(engine.clockFormat)).tag(time.id)
            }
        } label: {
            Label("Live Event Time", systemImage: "clock")
        }
        .disabled(engine.isChangingEventTime)
        .help(engine.isPCOLiveSyncEnabled
            ? "Which event time is running \u{2014} Planning Center Live follows along"
            : "Which event time is running")
    }
}

struct StartNextEventButton: View {
    @EnvironmentObject var engine: CueEngine

    var body: some View {
        if engine.isAtEndOfPlan, engine.canAdvanceToNextEventTime, let next = engine.nextEventTime {
            Button(action: { engine.advanceToNextEventTime() }) {
                Label("Start Next \u{00B7} \(next.displayName(engine.clockFormat))", systemImage: "arrow.uturn.forward")
            }
            .buttonStyle(.borderedProminent)
            .disabled(engine.isChangingEventTime)
            .help("Make the next event time live and return to the top of the run sheet")
        }
    }
}
