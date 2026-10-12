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
            case 2: return clamped(components[0], 60, components[1], 1, 0)
            case 3: return clamped(components[0], 3600, components[1], 60, components[2])
            default: return 300
            }
        }
        if let minutes = Int(trimmed) {
            return clamped(max(0, minutes), 60, 0, 1, 0)
        }
        return 300
    }

    private static func clamped(_ a: Int, _ am: Int, _ b: Int, _ bm: Int, _ c: Int) -> Int {
        guard a >= 0, b >= 0, c >= 0 else { return 0 }
        let (ap, ao) = a.multipliedReportingOverflow(by: am)
        let (bp, bo) = b.multipliedReportingOverflow(by: bm)
        guard !ao, !bo else { return TimerLimits.maxSeconds }
        let (s1, o1) = ap.addingReportingOverflow(bp)
        guard !o1 else { return TimerLimits.maxSeconds }
        let (s2, o2) = s1.addingReportingOverflow(c)
        guard !o2 else { return TimerLimits.maxSeconds }
        return TimerLimits.clampLength(s2)
    }
}
