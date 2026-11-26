// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

/// An attention-grabbing animation for the countdown text. None is standard.
public enum TimerEffect: String, Codable, CaseIterable, Sendable {
    case none
    case pulse
    case blink
    case flicker
    case glitch
}

/// One step of a timer color scale. A `remaining` stop takes over once the time left falls to `value`
/// (seconds, or percent of the item's length); an `overtime` stop takes over once the item is `value` over.
public struct TimerColorStop: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Unit: String, Codable, CaseIterable, Sendable {
        case seconds
        case percent
    }

    public enum Phase: String, Codable, CaseIterable, Sendable {
        case remaining
        case overtime
    }

    public var id: String
    public var phase: Phase
    public var value: Int
    public var unit: Unit
    /// Six hex digits, RRGGBB, no leading #.
    public var colorHex: String
    public var effect: TimerEffect

    public init(id: String = UUID().uuidString, phase: Phase = .remaining, value: Int, unit: Unit, colorHex: String, effect: TimerEffect = .none) {
        self.id = id
        self.phase = phase
        self.value = max(0, value)
        self.unit = unit
        self.colorHex = colorHex
        self.effect = effect
    }

    private enum CodingKeys: String, CodingKey { case id, phase, value, unit, colorHex, effect }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        phase = (try? container.decodeIfPresent(Phase.self, forKey: .phase)) ?? .remaining
        value = max(0, try container.decode(Int.self, forKey: .value))
        unit = try container.decode(Unit.self, forKey: .unit)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        effect = (try? container.decodeIfPresent(TimerEffect.self, forKey: .effect)) ?? .none
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if phase != .remaining { try container.encode(phase, forKey: .phase) }
        try container.encode(value, forKey: .value)
        try container.encode(unit, forKey: .unit)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(effect, forKey: .effect)
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
    public var overtimeEffect: TimerEffect

    public init(onTimeHex: String? = nil, stops: [TimerColorStop] = [], overtimeHex: String = "CC1717", overtimeEffect: TimerEffect = .none) {
        self.onTimeHex = onTimeHex
        self.stops = stops
        self.overtimeHex = overtimeHex
        self.overtimeEffect = overtimeEffect
    }

    private enum CodingKeys: String, CodingKey { case onTimeHex, stops, overtimeHex, overtimeEffect }

    /// Missing fields take their defaults, so `{}` is the standard scale.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A missing field takes the standard value, so `{}` is the standard scale and an explicit empty list stays empty.
        onTimeHex = try container.decodeIfPresent(String.self, forKey: .onTimeHex)
        stops = try container.decodeIfPresent([TimerColorStop].self, forKey: .stops) ?? Self.standard.stops
        overtimeHex = try container.decodeIfPresent(String.self, forKey: .overtimeHex) ?? Self.standard.overtimeHex
        // A stored scale predating effects has none; only a missing overtime color means "the standard scale".
        let fallbackEffect: TimerEffect = container.contains(.overtimeHex) ? .none : Self.standard.overtimeEffect
        overtimeEffect = (try? container.decodeIfPresent(TimerEffect.self, forKey: .overtimeEffect)) ?? fallbackEffect
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(onTimeHex, forKey: .onTimeHex)
        try container.encode(stops, forKey: .stops)
        try container.encode(overtimeHex, forKey: .overtimeHex)
        try container.encode(overtimeEffect, forKey: .overtimeEffect)
    }

    /// The default: normal text, yellow at 10% left, then red from zero, flickering, and a deeper pulsing
    /// level three seconds over. Ids are fixed so an untouched scale compares equal to this one.
    public static let standard = TimerColorScale(
        onTimeHex: nil,
        stops: [
            TimerColorStop(id: "standard-warning", phase: .remaining, value: 10, unit: .percent, colorHex: "FFD60A", effect: .none),
            TimerColorStop(id: "standard-overtime-deep", phase: .overtime, value: 3, unit: .seconds, colorHex: "CC1717", effect: .pulse)
        ],
        overtimeHex: "CC1717",
        overtimeEffect: .flicker
    )

    public var isStandard: Bool { self == .standard }

    /// The look for the time left on an item: a color (nil for the normal text color) and an effect.
    /// Of the lead-up stops reached, the one closest to zero wins; of the overtime stops, the deepest.
    public func style(remainingSeconds: Int, lengthSeconds: Int) -> (colorHex: String?, effect: TimerEffect) {
        if remainingSeconds < 0 {
            // Past zero: the deepest overtime level reached wins, else the base overtime color.
            let over = Double(-remainingSeconds)
            let deepest = stops
                .filter { $0.phase == .overtime }
                .map { (stop: $0, threshold: $0.thresholdSeconds(lengthSeconds: lengthSeconds)) }
                .filter { over >= $0.threshold }
                .max(by: { $0.threshold < $1.threshold })
            if let deepest { return (deepest.stop.colorHex, deepest.stop.effect) }
            return (overtimeHex, overtimeEffect)
        }
        let reached = stops
            .filter { $0.phase == .remaining }
            .map { (stop: $0, threshold: $0.thresholdSeconds(lengthSeconds: lengthSeconds)) }
            .filter { Double(remainingSeconds) <= $0.threshold }
        if let nearest = reached.min(by: { $0.threshold < $1.threshold }) { return (nearest.stop.colorHex, nearest.stop.effect) }
        return (onTimeHex, .none)
    }

    public func colorHex(remainingSeconds: Int, lengthSeconds: Int) -> String? {
        style(remainingSeconds: remainingSeconds, lengthSeconds: lengthSeconds).colorHex
    }

    public static func isValidHex(_ hex: String) -> Bool {
        hex.count == 6 && hex.allSatisfy(\.isHexDigit)
    }
}
