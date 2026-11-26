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
    /// An event or rehearsal time to make current when this goes live.
    public var target: TimeTarget?
    /// Start the first item when this goes live, so a pre-show countdown fires by itself.
    public var startsFirstItem: Bool

    public struct TimeTarget: Codable, Equatable, Hashable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case event
            case rehearsal
        }

        public var kind: Kind
        public var id: String

        public init(kind: Kind, id: String) {
            self.kind = kind
            self.id = id
        }
    }

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
        lastFiredAt: Date? = nil,
        target: TimeTarget? = nil,
        startsFirstItem: Bool = false
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
        self.target = target
        self.startsFirstItem = startsFirstItem
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, startsAt, goLiveOffsetSeconds, pcoServiceTypeId, pcoPlanId, recurrence, isEnabled, lastFiredAt, target, startsFirstItem
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startsAt = try container.decode(Date.self, forKey: .startsAt)
        goLiveOffsetSeconds = try container.decode(Int.self, forKey: .goLiveOffsetSeconds)
        pcoServiceTypeId = try container.decodeIfPresent(String.self, forKey: .pcoServiceTypeId)
        pcoPlanId = try container.decodeIfPresent(String.self, forKey: .pcoPlanId)
        recurrence = try container.decode(Recurrence.self, forKey: .recurrence)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        lastFiredAt = try container.decodeIfPresent(Date.self, forKey: .lastFiredAt)
        target = try? container.decodeIfPresent(TimeTarget.self, forKey: .target)
        startsFirstItem = (try? container.decodeIfPresent(Bool.self, forKey: .startsFirstItem)) ?? false
    }

    public var goLiveAt: Date {
        startsAt.addingTimeInterval(-Double(goLiveOffsetSeconds))
    }

    public var goLiveOffsetMinutes: Int {
        get { goLiveOffsetSeconds / 60 }
        set { goLiveOffsetSeconds = TimerLimits.clampDelta(TimerLimits.seconds(fromMinutes: newValue) ?? (newValue < 0 ? -TimerLimits.maxSeconds : TimerLimits.maxSeconds)) }
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

    public func nextOccurrence(after now: Date, calendar: Calendar = .current) -> Date? {
        guard recurrence == .weekly else { return nil }
        var candidate = startsAt
        while candidate <= now {
            guard let stepped = calendar.date(byAdding: .day, value: 7, to: candidate) else { return nil }
            candidate = stepped
        }
        return candidate
    }
}
