// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum Meridiem: String, Sendable {
    case am, pm
}

public enum ClockFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case twelveHour, twentyFourHour

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .twelveHour: return "12-hour"
        case .twentyFourHour: return "24-hour"
        }
    }

    public static var systemDefault: ClockFormat {
        guard let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) else { return .twelveHour }
        return template.contains("a") ? .twelveHour : .twentyFourHour
    }

    public func string(hour: Int, minute: Int, second: Int? = nil) -> String {
        switch self {
        case .twentyFourHour:
            if let second { return String(format: "%02d:%02d:%02d", hour, minute, second) }
            return String(format: "%02d:%02d", hour, minute)
        case .twelveHour:
            let hour12 = hour % 12 == 0 ? 12 : hour % 12
            let suffix = hour < 12 ? "AM" : "PM"
            if let second { return String(format: "%d:%02d:%02d %@", hour12, minute, second, suffix) }
            return String(format: "%d:%02d %@", hour12, minute, suffix)
        }
    }

    public func string(_ time: TimeOfDay) -> String {
        string(hour: time.hour, minute: time.minute)
    }

    public func string(from date: Date, timeZone: TimeZone = .current, includesSeconds: Bool = false) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return string(hour: parts.hour ?? 0, minute: parts.minute ?? 0, second: includesSeconds ? (parts.second ?? 0) : nil)
    }

    #if !os(Linux)
    public var pickerLocale: Locale {
        var components = Locale.Components(locale: .current)
        components.hourCycle = self == .twelveHour ? .oneToTwelve : .zeroToTwentyThree
        return Locale(components: components)
    }
    #endif
}
