// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

/// One step of a timer color scale: once the time remaining falls to `value` (seconds, or percent of the
/// item's length), the timer takes `colorHex`.
public struct TimerColorStop: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Unit: String, Codable, CaseIterable, Sendable {
        case seconds
        case percent
    }

    public var id: String
    public var value: Int
    public var unit: Unit
    /// Six hex digits, RRGGBB, no leading #.
    public var colorHex: String

    public init(id: String = UUID().uuidString, value: Int, unit: Unit, colorHex: String) {
        self.id = id
        self.value = max(0, value)
        self.unit = unit
        self.colorHex = colorHex
    }

    /// The remaining time, in seconds, at which this stop takes over for an item of the given length.
    public func thresholdSeconds(lengthSeconds: Int) -> Double {
        switch unit {
        case .seconds: return Double(value)
        case .percent: return Double(lengthSeconds) * Double(min(value, 100)) / 100
        }
    }
}

/// Colors for the countdown as it runs down: an optional color while there is plenty of time, stops that
/// take over as time runs out, and a color once the item goes over. Used for the producer readout, the
/// progress bar and (when customized) the text on pagers. An item or waypoint can carry its own scale.
public struct TimerColorScale: Codable, Equatable, Hashable, Sendable {
    /// nil keeps the normal text color while there is plenty of time.
    public var onTimeHex: String?
    public var stops: [TimerColorStop]
    public var overtimeHex: String

    public init(onTimeHex: String? = nil, stops: [TimerColorStop] = [], overtimeHex: String = "CC1717") {
        self.onTimeHex = onTimeHex
        self.stops = stops
        self.overtimeHex = overtimeHex
    }

    private enum CodingKeys: String, CodingKey { case onTimeHex, stops, overtimeHex }

    /// Missing fields take their defaults, so `{}` is the standard scale.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        onTimeHex = try container.decodeIfPresent(String.self, forKey: .onTimeHex)
        stops = try container.decodeIfPresent([TimerColorStop].self, forKey: .stops) ?? []
        overtimeHex = try container.decodeIfPresent(String.self, forKey: .overtimeHex) ?? "CC1717"
    }

    /// Normal text until the item goes over, then red. Matches how the readout behaved before scales existed.
    public static let standard = TimerColorScale()

    public var isStandard: Bool { self == .standard }

    /// The color for the time left on an item, or nil for the normal text color.
    /// Of the stops whose threshold has been reached, the one closest to zero wins.
    public func colorHex(remainingSeconds: Int, lengthSeconds: Int) -> String? {
        if remainingSeconds < 0 { return overtimeHex }
        let reached = stops
            .map { (stop: $0, threshold: $0.thresholdSeconds(lengthSeconds: lengthSeconds)) }
            .filter { Double(remainingSeconds) <= $0.threshold }
        if let nearest = reached.min(by: { $0.threshold < $1.threshold }) { return nearest.stop.colorHex }
        return onTimeHex
    }

    public static func isValidHex(_ hex: String) -> Bool {
        hex.count == 6 && hex.allSatisfy(\.isHexDigit)
    }
}
