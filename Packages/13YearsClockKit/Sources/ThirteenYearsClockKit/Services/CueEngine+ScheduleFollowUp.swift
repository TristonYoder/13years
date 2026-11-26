// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

extension CueEngine {
    /// What a schedule does once it has gone live: make its event or rehearsal time current, then optionally start
    /// the first item so a pre-show countdown runs by itself. A time that no longer exists is skipped.
    func runScheduleFollowUp(_ followUp: (target: ServiceSchedule.TimeTarget?, startsFirstItem: Bool)) {
        if let target = followUp.target {
            switch target.kind {
            case .event:
                if eventTime(id: target.id) != nil {
                    if isRehearsalMode { setRehearsalMode(false) }
                    if liveEventTime?.id != target.id { setLiveEventTime(id: target.id) }
                }
            case .rehearsal:
                if rehearsalPlanTimes.contains(where: { $0.id == target.id }) {
                    _ = setRehearsalMode(true, planTimeId: target.id)
                }
            }
        }
        if followUp.startsFirstItem, let first = planItems.first(where: { !$0.isHeader }) {
            setActivePlanItem(id: first.id)
        }
    }

    /// The next time an event or rehearsal time happens, for turning it into a schedule: its day and start time,
    /// rolled forward a week when a weekday's time has passed. nil without a start time.
    public static func nextStart(day: EventDay?, time: TimeOfDay?, after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let time else { return nil }
        let dayStart = day?.onOrAfter(now, calendar: calendar) ?? calendar.startOfDay(for: now)
        var start = time.date(on: dayStart, calendar: calendar)
        if start <= now, case .weekday? = day { start = calendar.date(byAdding: .day, value: 7, to: start) ?? start }
        else if start <= now, day == nil { start = calendar.date(byAdding: .day, value: 1, to: start) ?? start }
        return start
    }
}
