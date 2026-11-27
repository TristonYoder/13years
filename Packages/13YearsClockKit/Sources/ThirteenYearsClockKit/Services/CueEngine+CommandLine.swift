// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

struct CommandUndoSnapshot {
    var label: String
    var items: [PCOTimerItem]
    var activeIndex: Int
}

public struct CommandOutcome: Equatable, Sendable {
    public var message: String
    public var selectItemId: String?
}

extension CueEngine {
    public func commandLineContext(selectedItemId: String?) -> CommandLineContext {
        var types = ItemCommandParser.knownTypes
        for item in planItems where !types.contains(where: { $0.caseInsensitiveCompare(item.itemType) == .orderedSame }) {
            types.append(item.itemType)
        }
        return CommandLineContext(
            itemTypes: types,
            roles: roles.map(\.name),
            itemCount: planItems.count,
            hasSelection: selectedItemId.flatMap { id in planItems.contains { $0.id == id } } ?? false,
            documentActions: documentCommandHandler != nil,
            waypoints: waypoints.map(\.name),
            eventCount: eventTimes.count,
            rehearsalCount: manualRehearsalTimes.count,
            scheduleCount: serviceSchedules.count
        )
    }

    public func commandTargetIds(_ statement: CommandStatement, selectedItemId: String?) -> [String] {
        if let position = statement.position {
            let lower = max(position - 1, 0)
            let upper = min(lower + statement.count, planItems.count)
            guard lower < upper else { return [] }
            return planItems[lower..<upper].map(\.id)
        }
        if let selectedItemId, planItems.contains(where: { $0.id == selectedItemId }) { return [selectedItemId] }
        return []
    }

    public func commandConfirmationPrompt(_ statement: CommandStatement, selectedItemId: String?) -> String? {
        if statement.verb == .generic, statement.generic.key.hasPrefix("delete.") {
            let noun = statement.generic.key.dropFirst("delete.".count)
            return "Delete \(noun)? Press Enter again."
        }
        guard statement.verb == .delete else { return nil }
        let count = commandTargetIds(statement, selectedItemId: selectedItemId).count
        return count == 1 ? "Delete 1 cue? Press Enter again." : "Delete \(count) cues? Press Enter again."
    }

    @discardableResult
    public func runCommand(_ statement: CommandStatement, selectedItemId: String?) -> CommandOutcome? {
        if statement.verb == .action { return runAction(statement.action) }
        if statement.verb == .generic { return runGeneric(statement.generic) }
        guard !isRemoteMirror else { return nil }
        let targets = commandTargetIds(statement, selectedItemId: selectedItemId)
        if statement.verb.changesPlan, statement.verb != .edit || statement.changesAttributes {
            commandUndoStack.append(CommandUndoSnapshot(label: statement.verb.rawValue, items: planItems, activeIndex: activeItemIndex))
            if commandUndoStack.count > 20 { commandUndoStack.removeFirst() }
        }
        switch statement.verb {
        case .action, .generic: return nil
        case .skip, .unskip:
            targets.forEach { setItemSkipped(id: $0, skipped: statement.verb == .skip) }
            return CommandOutcome(message: summary(statement.verb == .skip ? "Skipped" : "Restored", targets.count), selectItemId: nil)
        case .store: return storeItems(statement)
        case .edit:
            if statement.changesAttributes {
                targets.forEach { applyAttributes(statement, to: $0) }
                return CommandOutcome(message: summary("Updated", targets.count), selectItemId: nil)
            }
            return CommandOutcome(message: "Selected", selectItemId: targets.first)
        case .label:
            targets.forEach { applyAttributes(statement, to: $0) }
            return CommandOutcome(message: summary("Renamed", targets.count), selectItemId: nil)
        case .move:
            guard let target = statement.target else { return nil }
            moveItems(ids: targets, toPosition: target)
            return CommandOutcome(message: summary("Moved", targets.count), selectItemId: targets.first)
        case .copy:
            guard let target = statement.target else { return nil }
            let copies = targets.compactMap { duplicateItem(id: $0) }
            moveItems(ids: copies, toPosition: target)
            return CommandOutcome(message: summary("Copied", copies.count), selectItemId: copies.first)
        case .delete:
            targets.forEach { removePlanItem(id: $0) }
            return CommandOutcome(message: summary("Deleted", targets.count), selectItemId: nil)
        case .standby:
            targets.forEach { standbyItem(id: $0) }
            return CommandOutcome(message: "Standby", selectItemId: nil)
        case .go:
            if let first = targets.first { goItem(id: first) }
            return CommandOutcome(message: "Go", selectItemId: nil)
        }
    }

    private func runAction(_ action: CommandAction?) -> CommandOutcome? {
        guard let action else { return nil }
        switch action {
        case .view(let mode):
            appMode = mode
            return CommandOutcome(message: mode.displayName, selectItemId: nil)
        case .play:
            if activeTimerItem?.isRunning != true { toggleTimerRunning() }
            return CommandOutcome(message: "Playing", selectItemId: nil)
        case .pause:
            if activeTimerItem?.isRunning == true { toggleTimerRunning() }
            return CommandOutcome(message: "Paused", selectItemId: nil)
        case .next:
            nextPlanItem()
            return CommandOutcome(message: "Next", selectItemId: nil)
        case .back:
            previousPlanItem()
            return CommandOutcome(message: "Back", selectItemId: nil)
        case .reset:
            resetTimer()
            return CommandOutcome(message: "Reset", selectItemId: nil)
        case .undo:
            return undoLastCommand()
        case .clearCues:
            clearAllCues()
            return CommandOutcome(message: "Cleared all cues", selectItemId: nil)
        case .save, .open, .connect, .disconnect, .flash:
            guard let documentCommandHandler else { return nil }
            documentCommandHandler(action)
            return CommandOutcome(message: "Done", selectItemId: nil)
        }
    }

    private func undoLastCommand() -> CommandOutcome {
        guard !isRemoteMirror, let snapshot = commandUndoStack.popLast() else {
            return CommandOutcome(message: "Nothing to undo", selectItemId: nil)
        }
        ensurePCOBaseline()
        let previousLengths = Dictionary(planItems.map { ($0.id, $0.lengthInSeconds) }, uniquingKeysWith: { first, _ in first })
        let current = activeTimerItem
        planItems = snapshot.items
        if let current, let index = planItems.firstIndex(where: { $0.id == current.id }) {
            var restored = current
            restored.title = planItems[index].title
            restored.itemType = planItems[index].itemType
            restored.lengthInSeconds = planItems[index].lengthInSeconds
            restored.trigger = planItems[index].trigger
            restored.cueRoleIds = planItems[index].cueRoleIds
            activeItemIndex = index
            activeTimerItem = restored
        } else if planItems.indices.contains(snapshot.activeIndex) {
            var restored = planItems[snapshot.activeIndex]
            restored.isRunning = false
            activeItemIndex = snapshot.activeIndex
            activeTimerItem = restored
        }
        broadcastTimerUpdate()
        pushPlanOrderToPCO()
        for item in planItems where previousLengths[item.id] != item.lengthInSeconds {
            pushItemLengthToPCO(id: item.id)
        }
        return CommandOutcome(message: "Undid \(snapshot.label)", selectItemId: nil)
    }

    private func summary(_ verb: String, _ count: Int) -> String {
        "\(verb) \(count) \(count == 1 ? "cue" : "cues")"
    }

    private func storeItems(_ statement: CommandStatement) -> CommandOutcome {
        if statement.storeMode == .replace {
            commandTargetIds(statement, selectedItemId: nil).forEach { removePlanItem(id: $0) }
        }
        let countBefore = planItems.count
        var created: [String] = []
        for _ in 0..<max(1, statement.count) {
            let length = statement.resolvedLength(base: 5 * 60)
            let type = statement.type ?? ItemCommandParser.knownTypes[0]
            guard let id = addPlanItem(title: statement.title ?? "New item", itemType: type, lengthInSeconds: length) else { continue }
            setItemTrigger(id: id, statement.trigger)
            setItemCueRoles(id: id, roleIds(for: statement.roles))
            applyWaypoints(statement, to: id)
            created.append(id)
        }
        if let position = statement.position, !created.isEmpty {
            let target = min(max(position - 1, 0), countBefore)
            if target < countBefore {
                movePlanItems(fromOffsets: IndexSet(countBefore..<(countBefore + created.count)), toOffset: target)
            }
        }
        return CommandOutcome(message: summary("Stored", created.count), selectItemId: created.first)
    }

    private func applyAttributes(_ statement: CommandStatement, to id: String) {
        guard let item = planItems.first(where: { $0.id == id }) else { return }
        if statement.title != nil || statement.type != nil || statement.length != nil {
            updatePlanItem(
                id: id,
                title: statement.title ?? item.title,
                itemType: statement.type ?? item.itemType,
                lengthInSeconds: statement.resolvedLength(base: item.lengthInSeconds)
            )
        }
        if let trigger = statement.trigger { setItemTrigger(id: id, trigger) }
        if !statement.roles.isEmpty { setItemCueRoles(id: id, roleIds(for: statement.roles)) }
        applyWaypoints(statement, to: id)
    }

    private func applyWaypoints(_ statement: CommandStatement, to id: String) {
        if statement.clearsWaypoints {
            setWaypointIds([], forItemId: id)
            return
        }
        guard !statement.waypoints.isEmpty else { return }
        var ids: [String] = []
        for name in statement.waypoints {
            if let existing = waypoint(matching: name) {
                ids.append(existing.id)
            } else if let created = addWaypoint(name: name) {
                ids.append(created.id)
            }
        }
        setWaypointIds(ids, forItemId: id)
    }

    private func roleIds(for names: [String]) -> [String] {
        names.compactMap { name in roles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id }
    }

    private func duplicateItem(id: String) -> String? {
        guard let item = planItems.first(where: { $0.id == id }) else { return nil }
        guard let newId = addPlanItem(title: item.title, itemType: item.itemType, lengthInSeconds: item.lengthInSeconds, isDurationActual: item.isDurationActual) else { return nil }
        updatePlanItem(
            id: newId,
            title: item.title,
            itemType: item.itemType,
            lengthInSeconds: item.lengthInSeconds,
            notes: item.notes,
            description: item.details?.description,
            servicePosition: item.details?.servicePosition
        )
        setItemTrigger(id: newId, item.trigger)
        setItemCueRoles(id: newId, item.cueRoleIds)
        return newId
    }

    private func moveItems(ids: [String], toPosition position: Int) {
        let indices = ids.compactMap { id in planItems.firstIndex { $0.id == id } }.sorted()
        guard let first = indices.first, !indices.isEmpty else { return }
        let finalStart = min(max(position - 1, 0), planItems.count - indices.count)
        guard finalStart != first else { return }
        let offset = finalStart > first ? finalStart + indices.count : finalStart
        movePlanItems(fromOffsets: IndexSet(indices), toOffset: offset)
    }
}

extension CommandStatement.Verb {
    var changesPlan: Bool {
        switch self {
        case .store, .label, .move, .copy, .delete, .edit: return true
        case .standby, .go, .skip, .unskip, .action, .generic: return false
        }
    }
}

extension CueEngine {
    public var lanProblemDescription: String? {
        guard !isLANConnected, !isRemoteMirror else { return nil }
        guard isMasterServer else { return "Not connected to the producer on this network. Retrying in the background." }
        if server.isPortInUse {
            return "Pagers can't connect: port \(LANUnicastServer.port) is blocked. This clears on its own once the port is free."
        }
        return "Pagers can't connect: this Mac isn't reachable on the network. Retrying in the background."
    }
}
