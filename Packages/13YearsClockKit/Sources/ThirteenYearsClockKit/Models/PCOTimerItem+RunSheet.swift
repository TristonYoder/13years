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

public struct RunSheetNotePill: Equatable, Identifiable, Sendable {
    public var category: String
    public var text: String

    public init(category: String, text: String) {
        self.category = category
        self.text = text
    }

    public var id: String { category }

    public var symbolName: String { Self.symbolName(forCategory: category) }

    public static func symbolName(forCategory category: String) -> String {
        let lower = category.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        func has(_ keywords: [String]) -> Bool { keywords.contains { lower.contains($0) } }
        if has(["audio", "sound"]) { return "speaker.wave.2" }
        if has(["light"]) { return "lightbulb" }
        if has(["video", "camera", "imag"]) { return "video" }
        if has(["media", "slides", "resolume", "propresenter"]) { return "photo.on.rectangle" }
        if has(["stage", "backstage"]) { return "figure.stand" }
        if has(["director", "producer"]) { return "megaphone" }
        if lower.contains("timecode") || words.contains("tc") { return "timer" }
        return "note.text"
    }

    public static func pills(notes: [String: String], hiddenColumns: Set<String>) -> [RunSheetNotePill] {
        notes.keys.sorted().compactMap { category in
            guard let text = notes[category], !text.isEmpty,
                  !hiddenColumns.contains(RunSheetLayoutSettings.noteColumnId(category)) else { return nil }
            return RunSheetNotePill(category: category, text: text)
        }
    }
}

extension PCOTimerItem {
    public var runSheetLeaders: [PCOItemLeader] {
        details?.leaders ?? []
    }

    public var runSheetByline: String? {
        PCOItemLeader.byline(runSheetLeaders)
    }

    public func runSheetNotePills(layout: RunSheetLayoutSettings) -> [RunSheetNotePill] {
        RunSheetNotePill.pills(notes: notes, hiddenColumns: layout.hiddenSet)
    }
}
