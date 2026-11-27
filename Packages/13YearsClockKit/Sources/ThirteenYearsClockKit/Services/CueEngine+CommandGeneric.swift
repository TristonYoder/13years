// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

extension CueEngine {
    func runGeneric(_ command: GenericCommand) -> CommandOutcome? {
        func done(_ message: String) -> CommandOutcome { CommandOutcome(message: message, selectItemId: nil) }
        func role(_ name: String) -> RoleCue? { roles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
        let roleList = command.names.compactMap(role)
        let on = command.choices.last?.lowercased() == "on"

        switch command.key {
        case "store.role":
            guard let name = command.text else { return nil }
            addRole(name: name)
            return done("Stored role \(name)")
        case "label.role":
            guard let target = roleList.first, let name = command.text else { return nil }
            renameRole(id: target.id, name: name)
            return done("Renamed role")
        case "delete.role":
            roleList.forEach { removeRole(id: $0.id) }
            return done("Deleted \(roleList.count) \(roleList.count == 1 ? "role" : "roles")")
        case "standby.role":
            roleList.forEach { setCueForRole(id: $0.id, state: .standby) }
            return done("Standby")
        case "go.role":
            roleList.forEach { setCueForRole(id: $0.id, state: .go) }
            return done("Go")
        case "clear.role":
            roleList.forEach { setCueForRole(id: $0.id, state: .off) }
            return done("Cleared")
        case "store.message":
            guard let text = command.text else { return nil }
            if roleList.isEmpty {
                sendMessage(text)
            } else {
                roleList.forEach { sendMessage(text, targetRoleId: $0.id) }
            }
            return done("Message sent")
        case "delete.message":
            clearMessageHistory()
            return done("Cleared message history")
        case "clear.message":
            clearActiveNotification()
            return done("Dismissed message")
        case "store.waypoint":
            guard let name = command.text, addWaypoint(name: name) != nil else { return done("Couldn't store the waypoint") }
            return done("Stored waypoint \(name)")
        case "label.waypoint":
            guard let ref = command.names.first, let waypoint = waypoint(matching: ref), let name = command.text else { return nil }
            renameWaypoint(id: waypoint.id, name: name)
            return done("Renamed waypoint")
        case "delete.waypoint":
            guard let ref = command.names.first, let waypoint = waypoint(matching: ref) else { return nil }
            removeWaypoint(id: waypoint.id)
            return done("Deleted waypoint")
        case "go.waypoint":
            guard let ref = command.names.first else { return nil }
            _ = fireWaypoint(ref)
            return done("Go \(ref)")
        case "store.event", "store.rehearsal":
            let day = command.day.flatMap { EventDay(string: $0) }
            let time = command.timeOfDay.flatMap { TimeOfDay(string: $0) }
            if command.key == "store.event" {
                guard !isEventTimesManagedByPCO else { return done("Event times come from Planning Center") }
                guard addEventTime(name: command.text, day: day, startTime: time) != nil else { return done("Couldn't store the event") }
                return done("Stored event")
            }
            guard addRehearsalTime(name: command.text, day: day, startTime: time) != nil else { return done("Couldn't store the rehearsal") }
            return done("Stored rehearsal")
        case "go.event":
            guard let number = command.number, eventTimes.indices.contains(number - 1) else { return nil }
            setLiveEventTime(id: eventTimes[number - 1].id)
            return done("Event \(number) is live")
        case "delete.event":
            guard !isEventTimesManagedByPCO else { return done("Event times come from Planning Center") }
            guard let number = command.number, eventTimes.indices.contains(number - 1) else { return nil }
            removeEventTime(id: eventTimes[number - 1].id)
            return done("Deleted event")
        case "next.event":
            guard canAdvanceToNextEventTime else { return done("No next event") }
            advanceToNextEventTime()
            return done("Next event")
        case "delete.rehearsal":
            guard let number = command.number, manualRehearsalTimes.indices.contains(number - 1) else { return nil }
            removeRehearsalTime(id: manualRehearsalTimes[number - 1].id)
            return done("Deleted rehearsal")
        case "go.schedule":
            guard let number = command.number, serviceSchedules.indices.contains(number - 1) else { return nil }
            goLiveWithSchedule(id: serviceSchedules[number - 1].id)
            return done("Schedule \(number) is live")
        case "delete.schedule":
            guard let number = command.number, serviceSchedules.indices.contains(number - 1) else { return nil }
            removeServiceSchedule(id: serviceSchedules[number - 1].id)
            return done("Deleted schedule")
        case "clock":
            guard activeTimerItem != nil, let action = command.clock else { return done("No active cue") }
            switch action {
            case .setAbsolute(let seconds): setTimerRemainingTime(seconds: seconds)
            case .adjustRelative(let delta): adjustTimerRemainingTime(bySeconds: delta)
            case .endAt(let time): setTimerRemainingTime(seconds: time.secondsUntil(now: Date()))
            }
            return done("Clock set")
        case "plan.title":
            guard !isLinkedToPCOPlan else { return done("A linked plan takes its name from Planning Center") }
            setPlanTitle(command.text)
            return done("Plan renamed")
        case "set.format":
            setClockFormat(command.choices.last == "24h" ? .twentyFourHour : .twelveHour)
            return done("Clock format set")
        case "set.threshold":
            switch command.choices.last?.lowercased() {
            case "60m": hourFormatThreshold = .over60Minutes
            case "90m": hourFormatThreshold = .over90Minutes
            default: hourFormatThreshold = .never
            }
            return done("Hour format set")
        case "set.follow":
            followByDefault = on
            return done(on ? "Follow by default is on" : "Follow by default is off")
        case "set.endtimes":
            runSheetLayout.showsEndTimes = on
            return done(on ? "End times are on" : "End times are off")
        case "pco.live":
            if on { enablePCOLiveSync() } else { disablePCOLiveSync() }
            return done(on ? "Live sync is on" : "Live sync is off")
        case "pco.unlink":
            unlinkPCOPlan()
            return done("Unlinked from Planning Center")
        case "pco.changes":
            if command.choices.last == "Accept" { _ = acceptPCOChanges() } else { _ = dismissPCOChanges() }
            return done("Planning Center changes handled")
        case "pager.ping":
            guard let ip = command.ip else { return nil }
            return done(pingDevice(atIP: ip) ? "Pinged \(ip)" : "Couldn't ping")
        case "pager.master":
            if isMasterServer != on { toggleMasterMode() }
            return done(on ? "Master mode on" : "Master mode off")
        case "pager.forget":
            forgetAssignedProducer()
            return done("Forgot the producer")
        default:
            return nil
        }
    }
}
