// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

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
        self = CueState(rawValue: raw) ?? .off
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

#if canImport(SwiftUI)
    public var color: Color {
        switch self {
        case .off:
            return AppPalette.cueOff
        case .standby:
            return AppPalette.cueStandby
        case .go:
            return AppPalette.cueGo
        }
    }

    public var textColor: Color {
        switch self {
        case .off:
            return AppPalette.cueLightText
        case .standby:
            return AppPalette.cueDarkText
        case .go:
            return AppPalette.cueLightText
        }
    }
#endif
}
