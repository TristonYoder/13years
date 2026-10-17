// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

extension CueEngine {
    public func runSheetSchedule(now: Date = Date()) -> RunSheetSchedule {
        let live = liveEventTime
        let active = activeTimerItem
        let activeIndex = active.flatMap { active in planItems.firstIndex { $0.id == active.id } }
        return RunSheetSchedule(
            items: planItems,
            startDate: live?.startDate(onOrAfter: now),
            planTimeId: live?.pcoPlanTimeId,
            activeIndex: active?.isRunning == true ? activeIndex : nil,
            activeElapsed: active?.elapsedSeconds ?? 0,
            activeLength: active?.lengthInSeconds,
            now: now
        )
    }

    public var liveEventTimeLabel: String? {
        guard let live = liveEventTime else { return nil }
        if let name = live.name, !name.isEmpty { return name }
        return live.startTime.map { $0.formatted(clockFormat) } ?? live.displayName(clockFormat)
    }
}
