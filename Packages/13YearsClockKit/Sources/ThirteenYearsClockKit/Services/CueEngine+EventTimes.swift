// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

extension CueEngine {
    public static let maxEventTimes = 24

    public var liveEventTime: EventTime? {
        if let liveEventTimeId, let match = eventTimes.first(where: { $0.id == liveEventTimeId }) {
            return match
        }
        return eventTimes.first
    }

    public var nextEventTime: EventTime? {
        guard let live = liveEventTime,
              let index = eventTimes.firstIndex(where: { $0.id == live.id }),
              eventTimes.indices.contains(index + 1) else { return nil }
        return eventTimes[index + 1]
    }

    public var canAdvanceToNextEventTime: Bool {
        nextEventTime != nil && planItems.contains(where: { !$0.isHeader })
    }

    func restoreEventTimes(_ times: [EventTime], liveId: String?) {
        eventTimes = EventTime.sorted(Array(times.prefix(Self.maxEventTimes)))
        liveEventTimeId = liveId.flatMap { id in eventTimes.contains(where: { $0.id == id }) ? id : nil }
    }

    public func eventTime(id: String) -> EventTime? {
        eventTimes.first { $0.id == id }
    }

    @discardableResult
    public func addEventTime(name: String?, day: EventDay?, startTime: TimeOfDay?) -> EventTime? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if isRemoteMirror {
            remoteCommands?.send(.eventTimeCreate(name: trimmed, day: day?.string, startTime: startTime?.string))
            return nil
        }
        guard eventTimes.count < Self.maxEventTimes else { return nil }
        let time = EventTime(name: trimmed, day: day, startTime: startTime)
        eventTimes = EventTime.sorted(eventTimes + [time])
        return time
    }

    public func updateEventTime(id: String, name: String?, day: EventDay?, startTime: TimeOfDay?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if isRemoteMirror {
            remoteCommands?.send(.eventTimeUpdate(id: id, name: trimmed ?? "", day: day?.string ?? "", startTime: startTime?.string ?? ""))
            return
        }
        guard let index = eventTimes.firstIndex(where: { $0.id == id }) else { return }
        var updated = eventTimes
        updated[index].name = trimmed.flatMap { $0.isEmpty ? nil : $0 }
        updated[index].day = day
        updated[index].startTime = startTime
        eventTimes = EventTime.sorted(updated)
    }

    public func removeEventTime(id: String) {
        if isRemoteMirror {
            remoteCommands?.send(.eventTimeDelete(id: id))
            return
        }
        eventTimes.removeAll { $0.id == id }
        if liveEventTimeId == id { liveEventTimeId = nil }
    }

    public func setLiveEventTime(id: String) {
        if isRemoteMirror {
            remoteCommands?.send(.eventTimeLive(id: id))
            return
        }
        guard eventTimes.contains(where: { $0.id == id }) else { return }
        liveEventTimeId = id
        if let item = activeTimerItem ?? planItems.first(where: { !$0.isHeader }) {
            jumpPCOLive(toEventTime: id, itemId: item.id)
        }
    }

    public func advanceToNextEventTime() {
        if isRemoteMirror {
            remoteCommands?.send(.eventTimeNext)
            return
        }
        guard let next = nextEventTime,
              let firstIndex = planItems.firstIndex(where: { !$0.isHeader }) else { return }
        liveEventTimeId = next.id
        activeItemIndex = firstIndex
        var item = planItems[firstIndex]
        item.servicePlanTitle = activeTimerItem?.servicePlanTitle
        item.elapsedSeconds = 0
        item.isRunning = false
        activeTimerItem = item
        broadcastTimerUpdate()
        jumpPCOLive(toEventTime: next.id, itemId: item.id)
    }
}
