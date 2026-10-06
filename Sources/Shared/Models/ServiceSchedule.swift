// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct ServiceSchedule: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var startsAt: Date
    public var goLiveOffsetSeconds: Int
    public var pcoServiceTypeId: String?
    public var pcoPlanId: String?
    public var recurrence: Recurrence
    public var isEnabled: Bool
    public var lastFiredAt: Date?

    public enum Recurrence: String, Codable, CaseIterable, Sendable {
        case once
        case weekly
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        startsAt: Date,
        goLiveOffsetSeconds: Int = 30 * 60,
        pcoServiceTypeId: String? = nil,
        pcoPlanId: String? = nil,
        recurrence: Recurrence = .once,
        isEnabled: Bool = true,
        lastFiredAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.startsAt = startsAt
        self.goLiveOffsetSeconds = goLiveOffsetSeconds
        self.pcoServiceTypeId = pcoServiceTypeId
        self.pcoPlanId = pcoPlanId
        self.recurrence = recurrence
        self.isEnabled = isEnabled
        self.lastFiredAt = lastFiredAt
    }

    public var goLiveAt: Date {
        startsAt.addingTimeInterval(-Double(goLiveOffsetSeconds))
    }

    public var goLiveOffsetMinutes: Int {
        get { goLiveOffsetSeconds / 60 }
        set { goLiveOffsetSeconds = newValue * 60 }
    }

    public static let lateFireGrace: TimeInterval = 60 * 60

    public func shouldFire(at now: Date) -> Bool {
        guard isEnabled else { return false }
        guard now >= goLiveAt else { return false }
        let windowEnd = startsAt.addingTimeInterval(Self.lateFireGrace)
        guard now < windowEnd else { return false }
        if let lastFiredAt, lastFiredAt >= goLiveAt { return false }
        return true
    }

    public func nextOccurrence(after now: Date) -> Date? {
        guard recurrence == .weekly else { return nil }
        let calendar = Calendar.current
        var candidate = startsAt
        while candidate <= now {
            guard let stepped = calendar.date(byAdding: .day, value: 7, to: candidate) else { return nil }
            candidate = stepped
        }
        return candidate
    }
}
