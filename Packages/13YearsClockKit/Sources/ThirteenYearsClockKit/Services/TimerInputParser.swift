// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum TimerInputParser {
    public enum Action: Equatable {
        case setAbsolute(seconds: Int)
        case adjustRelative(bySeconds: Int)
        case endAt(TimeOfDay)
    }

    public static func parseClock(_ raw: String) -> (hour12: Int, minute: Int)? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let hourText: String
        let minuteText: String
        if let colon = text.firstIndex(of: ":") {
            hourText = String(text[..<colon])
            minuteText = String(text[text.index(after: colon)...])
            guard !hourText.isEmpty, minuteText.count <= 2 else { return nil }
        } else {
            guard text.count <= 4 else { return nil }
            if text.count <= 2 {
                hourText = text
                minuteText = ""
            } else {
                hourText = String(text.dropLast(2))
                minuteText = String(text.suffix(2))
            }
        }
        guard hourText.allSatisfy(\.isASCIINumber), minuteText.allSatisfy(\.isASCIINumber),
              let hour = Int(hourText), (1...12).contains(hour) else { return nil }
        let minute = minuteText.isEmpty ? 0 : Int(minuteText) ?? -1
        guard (0..<60).contains(minute) else { return nil }
        return (hour, minute)
    }

    public static func parseEndAt(_ raw: String, isPM: Bool) -> Action? {
        guard let clock = parseClock(raw), let time = TimeOfDay(hour12: clock.hour12, minute: clock.minute, isPM: isPM) else { return nil }
        return .endAt(time)
    }

    public static func nearestUpcomingIsPM(_ raw: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let clock = parseClock(raw),
              let am = TimeOfDay(hour12: clock.hour12, minute: clock.minute, isPM: false),
              let pm = TimeOfDay(hour12: clock.hour12, minute: clock.minute, isPM: true) else { return false }
        func upcoming(_ time: TimeOfDay) -> Int {
            let delta = time.secondsUntil(now: now, calendar: calendar)
            return delta >= 0 ? delta : delta + 86_400
        }
        return upcoming(pm) < upcoming(am)
    }

    public static func parse(_ raw: String) -> Action? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var text = trimmed
        var isRelative = false
        var sign = 1
        if text.hasPrefix("+") {
            isRelative = true
            text.removeFirst()
        } else if text.hasPrefix("-") {
            isRelative = true
            sign = -1
            text.removeFirst()
        }
        text = text.trimmingCharacters(in: .whitespaces)

        guard let magnitude = parseMagnitude(text), magnitude <= TimerLimits.maxSeconds else { return nil }
        return isRelative ? .adjustRelative(bySeconds: sign * magnitude) : .setAbsolute(seconds: magnitude)
    }

    private static func parseMagnitude(_ text: String) -> Int? {
        guard !text.isEmpty else { return nil }

        if let combined = parseCombinedUnits(text.lowercased()) {
            return combined
        }

        if let separator = text.first(where: { $0 == ":" || $0 == "." }) {
            let parts = text.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let minutesText = String(parts[0])
            let secondsText = String(parts[1])
            guard !(minutesText.isEmpty && secondsText.isEmpty),
                  let minutes = Int(minutesText.isEmpty ? "0" : minutesText),
                  let seconds = Int(secondsText.isEmpty ? "0" : secondsText) else { return nil }
            return combine(max(0, minutes), 60, max(0, seconds))
        }

        guard text.allSatisfy(\.isNumber) else { return nil }
        let padded = text.count < 2 ? String(repeating: "0", count: 2 - text.count) + text : text
        let secondsPart = padded.suffix(2)
        let minutesPart = padded.dropLast(2)
        guard let minutes = minutesPart.isEmpty ? 0 : Int(minutesPart),
              let seconds = Int(secondsPart) else { return nil }
        return combine(minutes, 60, seconds)
    }

    private static func combine(_ units: Int, _ multiplier: Int, _ extra: Int) -> Int? {
        let (product, overflowed) = units.multipliedReportingOverflow(by: multiplier)
        guard !overflowed else { return nil }
        let (sum, sumOverflowed) = product.addingReportingOverflow(extra)
        return sumOverflowed ? nil : sum
    }

    private static func parseCombinedUnits(_ lowercasedText: String) -> Int? {
        var total = 0
        var digits = ""
        var matchedAny = false
        var seenUnits = Set<Character>()

        for char in lowercasedText {
            if char.isNumber {
                digits.append(char)
            } else if char == "h" || char == "m" || char == "s" {
                guard !digits.isEmpty, let value = Int(digits), seenUnits.insert(char).inserted else { return nil }
                let multiplier = char == "h" ? 3600 : (char == "m" ? 60 : 1)
                guard let part = combine(value, multiplier, 0) else { return nil }
                let (sum, overflowed) = total.addingReportingOverflow(part)
                guard !overflowed else { return nil }
                total = sum
                digits = ""
                matchedAny = true
            } else {
                return nil
            }
        }

        guard digits.isEmpty, matchedAny else { return nil }
        return max(0, total)
    }
}

private extension Character {
    var isASCIINumber: Bool { isASCII && isNumber }
}

public extension TimeOfDay {
    init?(hour12: Int, minute: Int, isPM: Bool) {
        guard (1...12).contains(hour12) else { return nil }
        self.init(hour: (hour12 % 12) + (isPM ? 12 : 0), minute: minute)
    }

    func secondsUntil(now: Date, calendar: Calendar = .current) -> Int {
        var target = date(on: now, calendar: calendar)
        if target.timeIntervalSince(now) < -12 * 3600 {
            target = calendar.date(byAdding: .day, value: 1, to: target) ?? target.addingTimeInterval(86_400)
        }
        return Int(target.timeIntervalSince(now).rounded())
    }

    var formattedMeridiem: String {
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", hour12, minute, hour < 12 ? "AM" : "PM")
    }
}
