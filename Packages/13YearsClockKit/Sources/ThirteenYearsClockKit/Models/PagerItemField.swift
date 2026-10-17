// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum PagerItemField: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case key
    case bpm
    case meter
    case arrangement
    case sequence
    case description
    case mediaType
    case servicePosition
    case startTime

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .key: return "Key"
        case .bpm: return "BPM"
        case .meter: return "Meter"
        case .arrangement: return "Arrangement"
        case .sequence: return "Sequence"
        case .description: return "Description"
        case .mediaType: return "Media type"
        case .servicePosition: return "Pre/post-service"
        case .startTime: return "Start time"
        }
    }

    public static func normalized(_ fields: [PagerItemField]) -> [PagerItemField] {
        let wanted = Set(fields)
        return allCases.filter { wanted.contains($0) }
    }

    public static func decodeTolerant(_ raw: [String]) -> [PagerItemField] {
        normalized(raw.compactMap(PagerItemField.init(rawValue:)))
    }
}
