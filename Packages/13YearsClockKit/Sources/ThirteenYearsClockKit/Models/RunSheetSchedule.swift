// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct RunSheetSchedule: Equatable, Sendable {
    public struct Actual: Equatable, Sendable {
        public let start: Date
        public let length: Int
        public let isComplete: Bool

        public init(start: Date, length: Int, isComplete: Bool) {
            self.start = start
            self.length = length
            self.isComplete = isComplete
        }
    }

    public struct Entry: Equatable, Sendable {
        public let itemId: String
        public let position: PCOServicePosition
        public let isHeader: Bool
        public let isExcluded: Bool
        public let isSkipped: Bool
        public let length: Int
        public let plannedStart: Date?
        public let projectedStart: Date?
        public let actualStart: Date?
        public let actualLength: Int?
        public let isActualComplete: Bool
        public let pcoActualStart: Date?
        public let pcoActualLength: Int?

        public var isOmitted: Bool { isExcluded || isSkipped }

        public var actualDeltaSeconds: Int? {
            guard isActualComplete, let actualLength else { return nil }
            return actualLength - length
        }

        public var driftSeconds: Int? {
            guard let plannedStart, let projectedStart else { return nil }
            return Int(projectedStart.timeIntervalSince(plannedStart).rounded())
        }
    }

    public static let driftThreshold = 60

    public let entries: [Entry]
    public let plannedLength: Int
    public let preLength: Int
    public let postLength: Int
    public let plannedEnd: Date?
    public let projectedEnd: Date?
    public let headerSubtotals: [String: Int]
    public let actualElapsedSeconds: Int
    public let actualDriftSeconds: Int?

    private let indexById: [String: Int]

    public var overUnderSeconds: Int? {
        guard let plannedEnd, let projectedEnd else { return nil }
        return Int(projectedEnd.timeIntervalSince(plannedEnd).rounded())
    }

    public func entry(forItemId id: String) -> Entry? {
        indexById[id].map { entries[$0] }
    }

    public static func position(of item: PCOTimerItem) -> PCOServicePosition {
        item.details?.servicePosition ?? .during
    }

    public static func positions(of items: [PCOTimerItem]) -> [PCOServicePosition] {
        var result = items.map(position(of:))
        var following: PCOServicePosition?
        for index in items.indices.reversed() {
            if items[index].isHeader {
                if let following { result[index] = following }
            } else {
                following = result[index]
            }
        }
        var preceding: PCOServicePosition?
        for index in items.indices {
            if items[index].isHeader {
                if !items[(index + 1)...].contains(where: { !$0.isHeader }), let preceding { result[index] = preceding }
            } else {
                preceding = result[index]
            }
        }
        return result
    }

    public static func effectiveLength(of item: PCOTimerItem, planTimeId: String?) -> Int {
        if item.isHeader { return 0 }
        let offset = item.details?.itemTime(forPlanTimeId: planTimeId)?.lengthOffset ?? 0
        return max(0, TimerLimits.saturatingAdd(item.lengthInSeconds, offset))
    }

    public init(
        items: [PCOTimerItem],
        startDate: Date?,
        planTimeId: String?,
        activeIndex: Int? = nil,
        activeElapsed: Int = 0,
        activeLength: Int? = nil,
        actuals: [String: Actual] = [:],
        skippedItemIds: Set<String> = [],
        now: Date = Date()
    ) {
        let count = items.count
        let positions = Self.positions(of: items)
        let lengths = items.map { Self.effectiveLength(of: $0, planTimeId: planTimeId) }
        let excluded = items.map { !$0.isHeader && ($0.details?.isExcluded(fromPlanTimeId: planTimeId) ?? false) }
        let skipped = items.map { !$0.isHeader && skippedItemIds.contains($0.id) }
        let omitted = (0..<count).map { excluded[$0] || skipped[$0] }
        let counted = (0..<count).map { !items[$0].isHeader && !omitted[$0] }

        func indices(_ position: PCOServicePosition) -> [Int] {
            (0..<count).filter { positions[$0] == position }
        }
        let pre = indices(.pre), during = indices(.during), post = indices(.post)
        let ordered = pre + during + post

        var planned = [Date?](repeating: nil, count: count)
        var plannedEnds = [Date?](repeating: nil, count: count)
        var duringEnd: Date?
        if let startDate {
            var cursor = startDate
            for i in during {
                guard !omitted[i] else { continue }
                planned[i] = cursor
                cursor = cursor.addingTimeInterval(TimeInterval(lengths[i]))
                plannedEnds[i] = cursor
            }
            duringEnd = cursor

            cursor = startDate
            for i in pre.reversed() {
                guard !omitted[i] else { continue }
                plannedEnds[i] = cursor
                cursor = cursor.addingTimeInterval(-TimeInterval(lengths[i]))
                planned[i] = cursor
            }

            cursor = duringEnd ?? startDate
            for i in post {
                guard !omitted[i] else { continue }
                planned[i] = cursor
                cursor = cursor.addingTimeInterval(TimeInterval(lengths[i]))
                plannedEnds[i] = cursor
            }
        }

        var projected = planned
        var projectedEnds = plannedEnds
        if startDate != nil {
            for i in 0..<count where !items[i].isHeader {
                guard let actual = actuals[items[i].id] else { continue }
                projected[i] = actual.start
                projectedEnds[i] = actual.start.addingTimeInterval(TimeInterval(actual.length))
            }
        }

        var chainPosition: Int?
        var chainStart: Date?
        var chainPrevious = PCOServicePosition.during
        if startDate != nil {
            if let activeIndex, items.indices.contains(activeIndex), !items[activeIndex].isHeader,
               let orderedPosition = ordered.firstIndex(of: activeIndex) {
                let activeStart = now.addingTimeInterval(-TimeInterval(max(0, activeElapsed)))
                let activeEnd = max(activeStart.addingTimeInterval(TimeInterval(activeLength ?? lengths[activeIndex])), now)
                projected[activeIndex] = activeStart
                projectedEnds[activeIndex] = activeEnd
                chainPosition = orderedPosition
                chainStart = activeEnd
                chainPrevious = positions[activeIndex]
            } else if let lastDone = ordered.lastIndex(where: { !items[$0].isHeader && actuals[items[$0].id]?.isComplete == true }),
                      let actual = actuals[items[ordered[lastDone]].id] {
                chainPosition = lastDone
                chainStart = max(actual.start.addingTimeInterval(TimeInterval(actual.length)), now)
                chainPrevious = positions[ordered[lastDone]]
            }
        }

        if let chainPosition, var cursor = chainStart {
            var previousPosition = chainPrevious
            for i in ordered[(chainPosition + 1)...] {
                if items[i].isHeader {
                    projected[i] = cursor
                    continue
                }
                guard !omitted[i] else { continue }
                var start = cursor
                if previousPosition == .pre, positions[i] != .pre, let plannedStart = planned[i] {
                    start = max(start, plannedStart)
                }
                projected[i] = start
                cursor = start.addingTimeInterval(TimeInterval(lengths[i]))
                projectedEnds[i] = cursor
                previousPosition = positions[i]
            }
        }

        let lastDuring = during.last { counted[$0] }
        var entries: [Entry] = []
        entries.reserveCapacity(count)
        var indexById: [String: Int] = [:]
        for i in 0..<count {
            let actual = items[i].isHeader ? nil : actuals[items[i].id]
            let pcoTime = items[i].isHeader ? nil : items[i].details?.itemTime(forPlanTimeId: planTimeId)
            entries.append(Entry(
                itemId: items[i].id,
                position: positions[i],
                isHeader: items[i].isHeader,
                isExcluded: excluded[i],
                isSkipped: skipped[i],
                length: lengths[i],
                plannedStart: planned[i],
                projectedStart: projected[i],
                actualStart: actual?.start,
                actualLength: actual?.length,
                isActualComplete: actual?.isComplete ?? false,
                pcoActualStart: pcoTime?.liveStartAt,
                pcoActualLength: pcoTime?.liveLengthSeconds ?? pcoTime?.length.flatMap { $0 > 0 ? $0 : nil }
            ))
            indexById[items[i].id] = i
        }

        var subtotals: [String: Int] = [:]
        for group in [pre, during, post] {
            var currentHeader: String?
            for i in group {
                if items[i].isHeader {
                    currentHeader = items[i].id
                    subtotals[items[i].id] = 0
                } else if let currentHeader, counted[i] {
                    subtotals[currentHeader, default: 0] += lengths[i]
                }
            }
        }

        var actualElapsed = 0
        var actualDrift = 0
        var hasCompleted = false
        for i in 0..<count where !items[i].isHeader {
            guard let actual = actuals[items[i].id] else { continue }
            actualElapsed += actual.length
            if actual.isComplete {
                hasCompleted = true
                actualDrift += actual.length - lengths[i]
            }
        }

        self.entries = entries
        self.indexById = indexById
        self.actualElapsedSeconds = actualElapsed
        self.actualDriftSeconds = hasCompleted ? actualDrift : nil
        self.headerSubtotals = subtotals
        self.plannedLength = during.reduce(0) { $0 + (counted[$1] ? lengths[$1] : 0) }
        self.preLength = pre.reduce(0) { $0 + (counted[$1] ? lengths[$1] : 0) }
        self.postLength = post.reduce(0) { $0 + (counted[$1] ? lengths[$1] : 0) }
        if startDate != nil {
            self.plannedEnd = duringEnd
            self.projectedEnd = lastDuring.flatMap { projectedEnds[$0] } ?? duringEnd
        } else {
            self.plannedEnd = nil
            self.projectedEnd = nil
        }
    }
}
