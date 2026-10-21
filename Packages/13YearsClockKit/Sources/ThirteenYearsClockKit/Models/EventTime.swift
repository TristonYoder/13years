// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct TimeOfDay: Codable, Equatable, Hashable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int

    public init?(hour: Int, minute: Int) {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    public init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.hour = parts.hour ?? 0
        self.minute = parts.minute ?? 0
    }

    public init?(string: String) {
        let parts = string.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        self.init(hour: hour, minute: minute)
    }

    public var string: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public func date(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    public var formatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date(on: Date()))
    }

    public func formatted(_ format: ClockFormat) -> String {
        format.string(self)
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = TimeOfDay(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected HH:mm, got \(raw)")
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

public enum EventDay: Codable, Equatable, Hashable, Sendable {
    case date(year: Int, month: Int, day: Int)
    case weekday(Int)

    public static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    public init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self = .date(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    public init?(string: String) {
        let lowered = string.lowercased()
        if let index = Self.weekdayNames.firstIndex(of: lowered) {
            self = .weekday(index + 1)
            return
        }
        let parts = string.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        self = .date(year: year, month: month, day: day)
    }

    public var string: String {
        switch self {
        case let .date(year, month, day): return String(format: "%04d-%02d-%02d", year, month, day)
        case let .weekday(weekday): return Self.weekdayNames[(weekday - 1) % 7]
        }
    }

    public func date(calendar: Calendar = .current) -> Date? {
        guard case let .date(year, month, day) = self else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    public func onOrAfter(_ now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .date:
            return date(calendar: calendar) ?? today
        case let .weekday(weekday):
            let current = calendar.component(.weekday, from: today)
            let ahead = (weekday - current + 7) % 7
            return calendar.date(byAdding: .day, value: ahead, to: today) ?? today
        }
    }

    public var formatted: String {
        let formatter = DateFormatter()
        switch self {
        case .date:
            formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
            return date().map(formatter.string(from:)) ?? string
        case let .weekday(weekday):
            return formatter.weekdaySymbols[(weekday - 1) % 7]
        }
    }

    var sortKey: Int {
        switch self {
        case let .date(year, month, day): return year * 10_000 + month * 100 + day
        case let .weekday(weekday): return weekday == 1 ? 7 : weekday - 1
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = EventDay(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected YYYY-MM-DD or a weekday name, got \(raw)")
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

public struct EventTime: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public var name: String?
    public var day: EventDay?
    public var startTime: TimeOfDay?
    public var pcoPlanTimeId: String?

    public init(id: String = UUID().uuidString, name: String? = nil, day: EventDay? = nil, startTime: TimeOfDay? = nil, pcoPlanTimeId: String? = nil) {
        self.id = id
        self.name = name.flatMap { $0.isEmpty ? nil : $0 }
        self.day = day
        self.startTime = startTime
        self.pcoPlanTimeId = pcoPlanTimeId
    }

    public var displayName: String {
        displayName(startTime: startTime?.formatted)
    }

    public func displayName(_ format: ClockFormat) -> String {
        displayName(startTime: startTime?.formatted(format))
    }

    private func displayName(startTime formattedStart: String?) -> String {
        let when = [day?.formatted, formattedStart].compactMap { $0 }.joined(separator: " ")
        switch (when.isEmpty ? nil : when, name) {
        case let (when?, name?): return "\(when) · \(name)"
        case let (when?, nil): return when
        case let (nil, name?): return name
        default: return "Untimed"
        }
    }

    public func startDate(onOrAfter now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let startTime else { return nil }
        let day = day?.onOrAfter(now, calendar: calendar) ?? calendar.startOfDay(for: now)
        return startTime.date(on: day, calendar: calendar)
    }

    public static func sorted(_ times: [EventTime]) -> [EventTime] {
        times.enumerated().sorted { lhs, rhs in
            let l = lhs.element, r = rhs.element
            let lDay = l.day?.sortKey ?? 0, rDay = r.day?.sortKey ?? 0
            if lDay != rDay { return lDay < rDay }
            switch (l.startTime, r.startTime) {
            case let (lt?, rt?) where lt != rt: return lt < rt
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.offset < rhs.offset
            }
        }
        .map(\.element)
    }
}
