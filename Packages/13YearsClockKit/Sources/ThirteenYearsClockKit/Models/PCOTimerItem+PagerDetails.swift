// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

extension PCOTimerItem {
    public static let pagerDetailsSeparator = " \u{00B7} "

    public func pagerDetailSegments(
        fields: [PagerItemField],
        startTime: Date? = nil,
        clockFormat: ClockFormat = .systemDefault,
        timeZone: TimeZone = .current
    ) -> [String] {
        guard !isHeader else { return [] }
        var segments: [String] = []
        for field in PagerItemField.ordered(fields) {
            switch field {
            case .key:
                if let key = details?.displayKey { segments.append(key) }
            case .bpm:
                if let bpm = runSheetBPMText { segments.append("\(bpm) BPM") }
            case .meter:
                if let meter = runSheetMeter { segments.append(meter) }
            case .arrangement:
                if let name = runSheetArrangementName { segments.append(name) }
            case .sequence:
                if let sequence = runSheetSequenceText { segments.append(sequence) }
            case .description:
                if let text = runSheetDescription {
                    let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                    if !flat.isEmpty { segments.append(flat) }
                }
            case .mediaType:
                if let mediaType = details?.media?.mediaType, !mediaType.isEmpty {
                    segments.append(mediaType.replacingOccurrences(of: "_", with: " ").capitalized)
                }
            case .servicePosition:
                switch details?.servicePosition ?? .during {
                case .pre: segments.append("Pre-service")
                case .post: segments.append("Post-service")
                case .during: break
                }
            case .startTime:
                if let startTime { segments.append("@ " + clockFormat.string(from: startTime, timeZone: timeZone)) }
            case .leader:
                if let names = PCOItemLeader.bylineNames(runSheetLeaders) { segments.append(names) }
            case .type:
                if let label = pagerTypeText { segments.append(label) }
            case .length:
                if let length = pagerLengthText { segments.append(length) }
            case .itemDetails:
                break
            }
        }
        return segments
    }

    public var pagerTypeText: String? {
        let trimmed = itemType.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.replacingOccurrences(of: "_", with: " ").capitalized
    }

    public var pagerLengthText: String? {
        guard lengthInSeconds > 0 else { return nil }
        let hours = lengthInSeconds / 3600
        let minutes = (lengthInSeconds % 3600) / 60
        let seconds = lengthInSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    public func pagerDetailsLine(
        fields: [PagerItemField],
        startTime: Date? = nil,
        clockFormat: ClockFormat = .systemDefault,
        timeZone: TimeZone = .current
    ) -> String? {
        let segments = pagerDetailSegments(fields: fields, startTime: startTime, clockFormat: clockFormat, timeZone: timeZone)
        return segments.isEmpty ? nil : segments.joined(separator: Self.pagerDetailsSeparator)
    }

    public static let maxItemDetailsCharacters = 64_000

    public func itemDetailsSource(includingDescription: Bool) -> String? {
        guard !isHeader else { return nil }
        if let html = details?.htmlDetails, !html.isEmpty {
            return String(html.prefix(Self.maxItemDetailsCharacters))
        }
        if includingDescription, let text = details?.description, !text.isEmpty {
            return String(text.prefix(Self.maxItemDetailsCharacters))
        }
        return nil
    }
}
