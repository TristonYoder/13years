// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct PagerPresentationState: Equatable, Sendable {
    public var roles: [RoleCue]
    public var planItems: [PCOTimerItem]
    public var activeItemIndex: Int
    public var activeTimerItem: PCOTimerItem?
    public var recentMessages: [InterTeamMessage]
    public var selectedRoleId: String
    public var isProducerLive: Bool
    public var isLANConnected: Bool
    public var connectedMasterName: String?
    public var hourFormatThreshold: HourFormatThreshold
    public var clockFormat: ClockFormat
    public var receivedNextItem: PCOTimerItem?
    public var producerClockOffsetMs: Double?
    public var producerUTCOffsetSeconds: Int?
    public var nextItemStartDate: Date?

    public init(
        roles: [RoleCue],
        planItems: [PCOTimerItem],
        activeItemIndex: Int,
        activeTimerItem: PCOTimerItem?,
        recentMessages: [InterTeamMessage],
        selectedRoleId: String,
        isProducerLive: Bool,
        isLANConnected: Bool,
        connectedMasterName: String?,
        hourFormatThreshold: HourFormatThreshold,
        clockFormat: ClockFormat,
        receivedNextItem: PCOTimerItem? = nil,
        producerClockOffsetMs: Double? = nil,
        producerUTCOffsetSeconds: Int? = nil,
        nextItemStartDate: Date? = nil
    ) {
        self.roles = roles
        self.planItems = planItems
        self.activeItemIndex = activeItemIndex
        self.activeTimerItem = activeTimerItem
        self.recentMessages = recentMessages
        self.selectedRoleId = selectedRoleId
        self.isProducerLive = isProducerLive
        self.isLANConnected = isLANConnected
        self.connectedMasterName = connectedMasterName
        self.hourFormatThreshold = hourFormatThreshold
        self.clockFormat = clockFormat
        self.receivedNextItem = receivedNextItem
        self.producerClockOffsetMs = producerClockOffsetMs
        self.producerUTCOffsetSeconds = producerUTCOffsetSeconds
        self.nextItemStartDate = nextItemStartDate
    }

    public static func cueWordText(for state: CueState) -> String {
        state == .off ? "" : state.displayName.uppercased()
    }

    public var activeRole: RoleCue? {
        roles.first(where: { $0.id == selectedRoleId }) ?? roles.first
    }

    public var currentState: CueState {
        activeRole?.state ?? .off
    }

    public var assignedNoteCategories: [String] {
        activeRole?.assignedNoteCategories ?? []
    }

    public var currentNotes: [(category: String, text: String)] {
        assignedNoteCategories.compactMap { category in
            guard let note = activeTimerItem?.notes[category], !note.isEmpty else { return nil }
            return (category, note)
        }
    }

    public var nextItem: PCOTimerItem? {
        guard !planItems.isEmpty else { return receivedNextItem }
        guard planItems.indices.contains(activeItemIndex) else { return nil }
        return planItems[(activeItemIndex + 1)...].first { !$0.isHeader }
    }

    public var nextNotes: [(category: String, text: String)] {
        assignedNoteCategories.compactMap { category in
            guard let note = nextItem?.notes[category], !note.isEmpty else { return nil }
            return (category, note)
        }
    }

    public var pagerFields: [PagerItemField] {
        PagerItemField.normalized(activeRole?.pagerFields ?? [])
    }

    private func producerNow(_ now: Date) -> Date {
        ProducerClock.producerDate(localNow: now, offsetMs: producerClockOffsetMs)
    }

    private var detailsTimeZone: TimeZone {
        ProducerClock.timeZone(utcOffsetSeconds: producerUTCOffsetSeconds)
    }

    public func currentStartDate(now: Date = Date()) -> Date? {
        guard let item = activeTimerItem, !item.isHeader, item.isRunning || item.elapsedSeconds > 0 else { return nil }
        return producerNow(now).addingTimeInterval(-TimeInterval(item.elapsedSeconds))
    }

    public func nextStartDate(now: Date = Date()) -> Date? {
        guard nextItem != nil else { return nil }
        var candidates: [Date] = []
        if let nextItemStartDate { candidates.append(nextItemStartDate) }
        if let active = activeTimerItem, !active.isHeader, active.isRunning {
            candidates.append(producerNow(now).addingTimeInterval(TimeInterval(max(0, active.remainingSeconds))))
        }
        return candidates.max()
    }

    public func currentDetailsLine(now: Date = Date()) -> String? {
        guard let item = activeTimerItem, !pagerFields.isEmpty else { return nil }
        return item.pagerDetailsLine(
            fields: pagerFields,
            startTime: pagerFields.contains(.startTime) ? currentStartDate(now: now) : nil,
            clockFormat: clockFormat,
            timeZone: detailsTimeZone
        )
    }

    public func nextDetailsLine(now: Date = Date()) -> String? {
        guard let item = nextItem, !pagerFields.isEmpty else { return nil }
        return item.pagerDetailsLine(
            fields: pagerFields,
            startTime: pagerFields.contains(.startTime) ? nextStartDate(now: now) : nil,
            clockFormat: clockFormat,
            timeZone: detailsTimeZone
        )
    }

    public var latestRelevantMessage: InterTeamMessage? {
        let incoming = recentMessages.first {
            ($0.targetRoleId == nil || $0.targetRoleId == selectedRoleId) && $0.senderRoleId == nil
        }
        guard let incoming else { return nil }
        let ownReply = recentMessages.first { $0.senderRoleId == selectedRoleId }
        if let ownReply, ownReply.timestamp >= incoming.timestamp { return nil }
        return incoming
    }
}