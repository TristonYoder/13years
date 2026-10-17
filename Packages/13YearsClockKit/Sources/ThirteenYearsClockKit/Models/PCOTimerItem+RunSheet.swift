// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum RunSheetItemKind: String, Sendable {
    case header
    case song
    case media
    case item
}

extension PCOTimerItem {
    public var runSheetKind: RunSheetItemKind {
        if isHeader { return .header }
        if itemType.caseInsensitiveCompare("song") == .orderedSame || details?.song != nil { return .song }
        if itemType.caseInsensitiveCompare("media") == .orderedSame || details?.media != nil { return .media }
        return .item
    }

    public var runSheetTypeLabel: String {
        switch runSheetKind {
        case .media:
            if let mediaType = details?.media?.mediaType, !mediaType.isEmpty {
                return mediaType.replacingOccurrences(of: "_", with: " ").capitalized
            }
            return "Media"
        case .song: return "Song"
        case .header: return "Header"
        case .item: return itemType.isEmpty ? "Item" : itemType.capitalized
        }
    }

    public var runSheetBPMText: String? {
        guard let bpm = details?.arrangement?.bpm, bpm > 0 else { return nil }
        return bpm == bpm.rounded() ? String(Int(bpm)) : String(format: "%.1f", bpm)
    }

    public var runSheetMeter: String? {
        details?.arrangement?.meter.flatMap { $0.isEmpty ? nil : $0 }
    }

    public var runSheetArrangementName: String? {
        details?.arrangement?.name.flatMap { $0.isEmpty ? nil : $0 }
    }

    public var runSheetSequenceText: String? {
        let sequence = details?.effectiveSequenceShort ?? []
        return sequence.isEmpty ? nil : sequence.joined(separator: " ")
    }

    public var runSheetDescription: String? {
        details?.description.flatMap { $0.isEmpty ? nil : $0 }
    }

    public var runSheetAuthor: String? {
        details?.song?.author.flatMap { $0.isEmpty ? nil : $0 }
    }
}
