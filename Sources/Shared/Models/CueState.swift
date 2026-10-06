// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
import SwiftUI

public enum CueState: String, Codable, CaseIterable, Sendable {
    case off = "OFF"
    case standby = "STANDBY"
    case go = "GO"

    private static let retiredRawValues: [String: CueState] = [
        "FLASH_STANDBY": .standby,
        "FLASH_GO": .go,
    ]

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self).uppercased()
        if let retired = Self.retiredRawValues[raw] {
            self = retired
            return
        }
        guard let parsed = CueState(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unknown CueState raw value \"\(raw)\""
            )
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var displayName: String {
        switch self {
        case .off: return "Clear"
        case .standby: return "Standby"
        case .go: return "Go!"
        }
    }

    public var isStandby: Bool { self == .standby }

    public var isGo: Bool { self == .go }

    public var color: Color {
        switch self {
        case .off:
            return Color(red: 0.08, green: 0.10, blue: 0.15)
        case .standby:
            return Color(red: 0.96, green: 0.72, blue: 0.15)
        case .go:
            return Color(red: 0.15, green: 0.78, blue: 0.35)
        }
    }

    public var textColor: Color {
        switch self {
        case .off:
            return Color.white
        case .standby:
            return Color(red: 0.1, green: 0.1, blue: 0.1)
        case .go:
            return Color.white
        }
    }
}
