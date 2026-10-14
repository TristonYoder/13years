// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct ProducerClockInfo: Equatable, Sendable {
    public var offsetMs: Double?
    public var utcOffsetSeconds: Int?

    public init(offsetMs: Double? = nil, utcOffsetSeconds: Int? = nil) {
        self.offsetMs = offsetMs
        self.utcOffsetSeconds = utcOffsetSeconds
    }

    public static let local = ProducerClockInfo()

    public var timeZone: TimeZone {
        ProducerClock.timeZone(utcOffsetSeconds: utcOffsetSeconds)
    }

    public var offsetBucket: Int {
        offsetMs.map { Int($0.rounded()) } ?? Int.min
    }
}

public enum ProducerClock {
    public static func producerDate(localNow: Date, offsetMs: Double?) -> Date {
        localNow.addingTimeInterval((offsetMs ?? 0) / 1000)
    }

    public static func msUntilNextProducerSecond(localNow: Date, offsetMs: Double?) -> Int {
        let producerMs = ((localNow.timeIntervalSince1970 * 1000 + (offsetMs ?? 0)) * 100).rounded() / 100
        let intoSecond = producerMs - (producerMs / 1000).rounded(.down) * 1000
        return max(1, Int((1000 - intoSecond).rounded(.up)))
    }

    public static func nextFlipDate(after localNow: Date, offsetMs: Double?) -> Date {
        localNow.addingTimeInterval(Double(msUntilNextProducerSecond(localNow: localNow, offsetMs: offsetMs)) / 1000)
    }

    public static func currentFlipDate(at localNow: Date, offsetMs: Double?) -> Date {
        let producerMs = ((localNow.timeIntervalSince1970 * 1000 + (offsetMs ?? 0)) * 100).rounded() / 100
        let intoSecond = producerMs - (producerMs / 1000).rounded(.down) * 1000
        return localNow.addingTimeInterval(-intoSecond / 1000)
    }

    public static func displayStyle(_ info: ProducerClockInfo) -> Date.FormatStyle {
        var style = Date.FormatStyle().hour().minute().second()
        style.timeZone = info.timeZone
        return style
    }

    public static func flipDates(from localStart: Date, offsetMs: Double?, count: Int) -> [Date] {
        var result: [Date] = []
        var cursor = localStart
        while result.count < count {
            let next = nextFlipDate(after: cursor, offsetMs: offsetMs)
            result.append(next)
            cursor = next
        }
        return result
    }

    public static func timeZone(utcOffsetSeconds: Int?) -> TimeZone {
        guard let seconds = utcOffsetSeconds, let zone = TimeZone(secondsFromGMT: seconds) else { return .current }
        return zone
    }

    public static func formatted(localNow: Date, info: ProducerClockInfo) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = info.timeZone
        let date = producerDate(localNow: localNow, offsetMs: info.offsetMs)
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }
}
