// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct PCOPlanChange: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case added
        case removed
        case retitled
        case retyped
        case length
        case notes
        case reordered
    }

    public var kind: Kind
    public var itemId: String?
    public var title: String
    public var detail: String?

    public init(kind: Kind, itemId: String? = nil, title: String, detail: String? = nil) {
        self.kind = kind
        self.itemId = itemId
        self.title = title
        self.detail = detail
    }

    public var summary: String {
        switch kind {
        case .added: return "Added “\(title)”"
        case .removed: return "Removed “\(title)”"
        case .retitled: return "Renamed \(detail ?? "“\(title)”")"
        case .retyped: return "“\(title)” is now \(detail ?? "a different type")"
        case .length: return "“\(title)” length \(detail ?? "changed")"
        case .notes: return "“\(title)” notes changed\(detail.map { ": \($0)" } ?? "")"
        case .reordered: return "Items reordered"
        }
    }
}

public struct PCOPendingChanges: Codable, Equatable, Sendable {
    public var revision: String
    public var serviceTypeId: String
    public var planId: String
    public var detectedAt: Date
    public var changes: [PCOPlanChange]

    public init(revision: String, serviceTypeId: String, planId: String, detectedAt: Date, changes: [PCOPlanChange]) {
        self.revision = revision
        self.serviceTypeId = serviceTypeId
        self.planId = planId
        self.detectedAt = detectedAt
        self.changes = changes
    }

    public var headline: String {
        changes.count == 1 ? "Planning Center has 1 change" : "Planning Center has \(changes.count) changes"
    }
}

public enum PCOPlanDiff {
    public static func revision(of items: [PCOTimerItem]) -> String {
        let canonical = items.map { item in
            let notes = item.notes.keys.sorted().map { "\($0)=\(item.notes[$0] ?? "")" }.joined(separator: SyncHash.unitSeparator)
            return [item.id, item.title, item.itemType, String(item.lengthInSeconds), notes].joined(separator: SyncHash.unitSeparator)
        }
        return SyncHash.fnv1a64(canonical.joined(separator: SyncHash.recordSeparator))
    }

    public static func changes(from baseline: [PCOTimerItem], to remote: [PCOTimerItem]) -> [PCOPlanChange] {
        let baselineById = Dictionary(baseline.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteIds = Set(remote.map(\.id))
        var changes: [PCOPlanChange] = []

        for item in remote {
            guard let old = baselineById[item.id] else {
                changes.append(PCOPlanChange(kind: .added, itemId: item.id, title: item.title))
                continue
            }
            if old.title != item.title {
                changes.append(PCOPlanChange(kind: .retitled, itemId: item.id, title: item.title, detail: "“\(old.title)” to “\(item.title)”"))
            }
            if old.itemType != item.itemType {
                changes.append(PCOPlanChange(kind: .retyped, itemId: item.id, title: item.title, detail: item.itemType))
            }
            if old.lengthInSeconds != item.lengthInSeconds {
                changes.append(PCOPlanChange(kind: .length, itemId: item.id, title: item.title, detail: "\(clock(old.lengthInSeconds)) to \(clock(item.lengthInSeconds))"))
            }
            let changedCategories = Set(old.notes.keys).union(item.notes.keys)
                .filter { (old.notes[$0] ?? "") != (item.notes[$0] ?? "") }
                .sorted()
            if !changedCategories.isEmpty {
                changes.append(PCOPlanChange(kind: .notes, itemId: item.id, title: item.title, detail: changedCategories.joined(separator: ", ")))
            }
        }

        for item in baseline where !remoteIds.contains(item.id) {
            changes.append(PCOPlanChange(kind: .removed, itemId: item.id, title: item.title))
        }

        if isReordered(from: baseline, to: remote) {
            changes.append(PCOPlanChange(kind: .reordered, title: "Run sheet"))
        }
        return changes
    }

    public static func isReordered(from baseline: [PCOTimerItem], to remote: [PCOTimerItem]) -> Bool {
        let shared = Set(baseline.map(\.id)).intersection(remote.map(\.id))
        return baseline.map(\.id).filter(shared.contains) != remote.map(\.id).filter(shared.contains)
    }

    public static func merge(remote: [PCOTimerItem], baseline: [PCOTimerItem], into local: [PCOTimerItem], keeping keptId: String?) -> [PCOTimerItem] {
        let baselineById = Dictionary(baseline.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteById = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var merged: [PCOTimerItem] = []
        for item in local {
            guard let theirs = remoteById[item.id] else {
                if baselineById[item.id] == nil || item.id == keptId { merged.append(item) }
                continue
            }
            merged.append(applying(theirs, over: baselineById[item.id], to: item))
        }

        if isReordered(from: baseline, to: remote) {
            let remoteOrder = remote.map(\.id).filter { id in merged.contains { $0.id == id } }
            let slots = merged.indices.filter { remoteById[merged[$0].id] != nil }
            let byId = Dictionary(merged.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for (slot, id) in zip(slots, remoteOrder) {
                if let item = byId[id] { merged[slot] = item }
            }
        }

        let localIds = Set(local.map(\.id))
        for (remoteIndex, item) in remote.enumerated() where baselineById[item.id] == nil && !localIds.contains(item.id) {
            let predecessor = remote[..<remoteIndex].last { candidate in merged.contains { $0.id == candidate.id } }
            let insertAt = predecessor.flatMap { previous in merged.firstIndex { $0.id == previous.id } }.map { $0 + 1 }
                ?? merged.firstIndex { remoteById[$0.id] != nil }
                ?? merged.count
            merged.insert(item, at: insertAt)
        }
        return merged
    }

    public static func applying(_ theirs: PCOTimerItem, over base: PCOTimerItem?, to mine: PCOTimerItem) -> PCOTimerItem {
        var item = mine
        if theirs.title != base?.title { item.title = theirs.title }
        if theirs.itemType != base?.itemType { item.itemType = theirs.itemType }
        if theirs.lengthInSeconds != base?.lengthInSeconds { item.lengthInSeconds = theirs.lengthInSeconds }
        for category in Set(theirs.notes.keys).union(base.map { Array($0.notes.keys) } ?? []) {
            let remoteValue = theirs.notes[category]
            guard (remoteValue ?? "") != (base?.notes[category] ?? "") else { continue }
            item.notes[category] = remoteValue
        }
        for (category, noteId) in theirs.noteIds { item.noteIds[category] = noteId }
        if theirs.details != base?.details { item.details = theirs.details }
        item.pcoServiceTypeId = theirs.pcoServiceTypeId ?? item.pcoServiceTypeId
        item.pcoPlanId = theirs.pcoPlanId ?? item.pcoPlanId
        return item
    }

    public static func reorderSequence(local localIds: [String], baseline baselineIds: [String]) -> [String] {
        let known = Set(baselineIds)
        var sequence = localIds.filter(known.contains)
        var placed = Set(sequence)
        for (index, id) in baselineIds.enumerated() where !placed.contains(id) {
            let predecessor = baselineIds[..<index].last(where: placed.contains)
            let insertAt = predecessor.flatMap { sequence.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            sequence.insert(id, at: insertAt)
            placed.insert(id)
        }
        return sequence
    }

    private static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
