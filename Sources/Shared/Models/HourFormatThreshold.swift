// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum HourFormatThreshold: String, CaseIterable, Codable, Identifiable, Sendable {
    case over60Minutes
    case over90Minutes
    case never

    public var id: String { rawValue }

    public var thresholdSeconds: Int? {
        switch self {
        case .over60Minutes: return 60 * 60
        case .over90Minutes: return 90 * 60
        case .never: return nil
        }
    }

    public var label: String {
        switch self {
        case .over60Minutes: return "Over 60 min"
        case .over90Minutes: return "Over 90 min"
        case .never: return "Never"
        }
    }
}

public enum TimeFormatting {
    public static func string(forSeconds totalSeconds: Int, threshold: HourFormatThreshold) -> String {
        let absSeconds = abs(totalSeconds)
        let core: String
        if let cutoff = threshold.thresholdSeconds, absSeconds >= cutoff {
            let hours = absSeconds / 3600
            let minutes = (absSeconds % 3600) / 60
            let seconds = absSeconds % 60
            core = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            core = String(format: "%02d:%02d", absSeconds / 60, absSeconds % 60)
        }
        return totalSeconds < 0 ? "+\(core)" : core
    }
}
