// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum ServiceFlowImporter {
    public static func parse(_ text: String) -> [PCOTimerItem] {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, line in
                let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                let title = parts[0].isEmpty ? "Untitled Item \(index + 1)" : parts[0]
                let itemType = (parts.count > 1 && !parts[1].isEmpty) ? parts[1] : "Item"
                let lengthInSeconds = (parts.count > 2 && !parts[2].isEmpty) ? parseDuration(parts[2]) : 300
                return PCOTimerItem(title: title, itemType: itemType, sequence: index + 1, lengthInSeconds: lengthInSeconds)
            }
    }

    static func parseDuration(_ raw: String) -> Int {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(":") {
            let components = trimmed.split(separator: ":").compactMap { Int($0) }
            switch components.count {
            case 2: return components[0] * 60 + components[1]
            case 3: return components[0] * 3600 + components[1] * 60 + components[2]
            default: return 300
            }
        }
        if let minutes = Int(trimmed) {
            return max(0, minutes) * 60
        }
        return 300
    }
}
