// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct RunSheetSchedule: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let itemId: String
        public let position: PCOServicePosition
        public let isHeader: Bool
        public let isExcluded: Bool
        public let length: Int
        public let plannedStart: Date?
        public let projectedStart: Date?

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

    public static func effectiveLength(of item: PCOTimerItem, planTimeId: String?) -> Int {
        if item.isHeader { return 0 }
        return item.details?.itemTime(forPlanTimeId: planTimeId)?.length ?? item.lengthInSeconds
    }

    public init(
        items: [PCOTimerItem],
        startDate: Date?,
        planTimeId: String?,
        activeIndex: Int? = nil,
        activeElapsed: Int = 0,
        activeLength: Int? = nil,
        now: Date = Date()
    ) {
        let count = items.count
        let positions = items.map(Self.position(of:))
        let lengths = items.map { Self.effectiveLength(of: $0, planTimeId: planTimeId) }
        let excluded = items.map { !$0.isHeader && ($0.details?.isExcluded(fromPlanTimeId: planTimeId) ?? false) }
        let counted = (0..<count).map { !items[$0].isHeader && !excluded[$0] }

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
                guard !excluded[i] else { continue }
                planned[i] = cursor
                cursor = cursor.addingTimeInterval(TimeInterval(lengths[i]))
                plannedEnds[i] = cursor
            }
            duringEnd = cursor

            cursor = startDate
            for i in pre.reversed() {
                guard !excluded[i] else { continue }
                plannedEnds[i] = cursor
                cursor = cursor.addingTimeInterval(-TimeInterval(lengths[i]))
                planned[i] = cursor
            }

            cursor = duringEnd ?? startDate
            for i in post {
                guard !excluded[i] else { continue }
                planned[i] = cursor
                cursor = cursor.addingTimeInterval(TimeInterval(lengths[i]))
                plannedEnds[i] = cursor
            }
        }

        var projected = planned
        var projectedEnds = plannedEnds
        if startDate != nil,
           let activeIndex, items.indices.contains(activeIndex), !items[activeIndex].isHeader,
           let orderedPosition = ordered.firstIndex(of: activeIndex) {
            let activeStart = now.addingTimeInterval(-TimeInterval(max(0, activeElapsed)))
            let activeEnd = max(activeStart.addingTimeInterval(TimeInterval(activeLength ?? lengths[activeIndex])), now)
            projected[activeIndex] = activeStart
            projectedEnds[activeIndex] = activeEnd

            var cursor = activeEnd
            var previousPosition = positions[activeIndex]
            for i in ordered[(orderedPosition + 1)...] {
                if items[i].isHeader {
                    projected[i] = cursor
                    continue
                }
                guard !excluded[i] else { continue }
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
            entries.append(Entry(
                itemId: items[i].id,
                position: positions[i],
                isHeader: items[i].isHeader,
                isExcluded: excluded[i],
                length: lengths[i],
                plannedStart: planned[i],
                projectedStart: projected[i]
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

        self.entries = entries
        self.indexById = indexById
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
