// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct ChordChart: Equatable, Sendable {
    public enum Format: Equatable, Sendable {
        case chordPro
        case plain
        case lyricsOnly
    }

    public struct Chord: Equatable, Sendable {
        public var column: Int
        public var name: String

        public init(column: Int, name: String) {
            self.column = column
            self.name = name
        }
    }

    public struct Line: Equatable, Sendable {
        public var text: String
        public var chords: [Chord]

        public init(text: String, chords: [Chord] = []) {
            self.text = text
            self.chords = chords
        }

        public var isBlank: Bool { chords.isEmpty && text.trimmingCharacters(in: .whitespaces).isEmpty }
        public var hasLyrics: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }

        public var chordRow: String {
            var row = ""
            for chord in chords.sorted(by: { $0.column < $1.column }) {
                let target = max(chord.column, row.isEmpty ? 0 : row.count + 1)
                row += String(repeating: " ", count: target - row.count) + chord.name
            }
            return row
        }
    }

    public struct Section: Equatable, Sendable {
        public var title: String?
        public var lines: [Line]

        public init(title: String?, lines: [Line]) {
            self.title = title
            self.lines = lines
        }

        public var lyricLines: [Line] {
            var result: [Line] = []
            for line in lines where line.hasLyrics || line.isBlank {
                if line.isBlank, result.last?.isBlank ?? true { continue }
                result.append(line)
            }
            while result.last?.isBlank == true { result.removeLast() }
            return result
        }
    }

    public var sections: [Section]
    public var format: Format
    public var metadata: [String: String]

    public init(sections: [Section] = [], format: Format = .lyricsOnly, metadata: [String: String] = [:]) {
        self.sections = sections
        self.format = format
        self.metadata = metadata
    }

    public var isEmpty: Bool { sections.allSatisfy { $0.lines.isEmpty } }
    public var hasChords: Bool { sections.contains { $0.lines.contains { !$0.chords.isEmpty } } }
}

public enum ChordChartParser {
    private static let chordPattern = try! NSRegularExpression(
        pattern: "^(?:N\\.?C\\.?|[A-G][#b\u{266F}\u{266D}]?(?:maj|min|dim|aug|sus|add|m|M|\\+|\u{00B0}|\u{00F8}|-|\\d|[#b\u{266F}\u{266D}]|\\(|\\)|,)*(?:/[A-G][#b\u{266F}\u{266D}]?)?)$"
    )
    private static let numberPattern = try! NSRegularExpression(
        pattern: "^[1-7][#b\u{266F}\u{266D}]?(?:maj|min|dim|aug|sus|add|m|M|\\+|-|\\d|[#b])*(?:/[1-7][#b\u{266F}\u{266D}]?)?$"
    )
    private static let headingPattern = try! NSRegularExpression(
        pattern: "^(?:verse|chorus|pre[- ]?chorus|bridge|intro|outro|tag|ending|instrumental|interlude|turnaround|turn|refrain|coda|vamp|hook|solo|break|post[- ]?chorus)(?:\\s*\\d+[a-z]?)?(?:\\s*\\([^)]*\\))?(?:\\s*[xX]\\d+)?$",
        options: [.caseInsensitive]
    )

    public static func isChord(_ token: String) -> Bool {
        matches(chordPattern, token)
    }

    static func isInlineChord(_ token: String) -> Bool {
        matches(chordPattern, token) || matches(numberPattern, token)
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    public static func parse(_ text: String) -> ChordChart {
        var builder = Builder()
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            builder.consume(String(rawLine).replacingOccurrences(of: "\t", with: "    "))
        }
        return builder.finish()
    }

    static func headingTitle(_ trimmed: String) -> String? {
        var candidate = trimmed
        if candidate.hasPrefix("["), candidate.hasSuffix("]"), candidate.dropFirst().dropLast().allSatisfy({ $0 != "[" && $0 != "]" }) {
            let inner = String(candidate.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if isInlineChord(inner) { return nil }
            candidate = inner
        }
        while candidate.hasPrefix("#") { candidate.removeFirst() }
        candidate = candidate.trimmingCharacters(in: .whitespaces)
        if candidate.hasSuffix(":") { candidate.removeLast() }
        candidate = candidate.trimmingCharacters(in: .whitespaces)
        guard !candidate.isEmpty, matches(headingPattern, candidate) else { return nil }
        return candidate
    }

    static func parseInline(_ line: String) -> (text: String, chords: [ChordChart.Chord]) {
        var text = ""
        var count = 0
        var chords: [ChordChart.Chord] = []
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "[",
               let close = characters[(index + 1)...].prefix(14).firstIndex(of: "]") {
                let inner = String(characters[(index + 1)..<close]).trimmingCharacters(in: .whitespaces)
                if isInlineChord(inner) {
                    chords.append(ChordChart.Chord(column: count, name: inner))
                    index = close + 1
                    continue
                }
            }
            text.append(character)
            count += 1
            index += 1
        }
        return (text, chords)
    }

    static func plainChords(_ line: String) -> [ChordChart.Chord]? {
        var chords: [ChordChart.Chord] = []
        var column = 0
        var token = ""
        var tokenStart = 0
        for character in line {
            if character == " " {
                if !token.isEmpty {
                    chords.append(ChordChart.Chord(column: tokenStart, name: token))
                    token = ""
                }
            } else {
                if token.isEmpty { tokenStart = column }
                token.append(character)
            }
            column += 1
        }
        if !token.isEmpty { chords.append(ChordChart.Chord(column: tokenStart, name: token)) }
        guard !chords.isEmpty, chords.allSatisfy({ isChord($0.name) }) else { return nil }
        return chords
    }

    private struct Builder {
        var sections: [ChordChart.Section] = []
        var title: String?
        var lines: [ChordChart.Line] = []
        var pending: [ChordChart.Chord]?
        var metadata: [String: String] = [:]
        var sawInline = false
        var sawPlain = false

        mutating func consume(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("{"), trimmed.hasSuffix("}"), directive(String(trimmed.dropFirst().dropLast())) {
                return
            }

            if trimmed.isEmpty {
                flushPending()
                lines.append(ChordChart.Line(text: ""))
                return
            }

            if let heading = ChordChartParser.headingTitle(trimmed) {
                flushPending()
                startSection(heading)
                return
            }

            if trimmed.contains("[") {
                let parsed = ChordChartParser.parseInline(raw)
                if !parsed.chords.isEmpty {
                    flushPending()
                    sawInline = true
                    lines.append(ChordChart.Line(text: Self.trimTrailing(parsed.text), chords: parsed.chords))
                    return
                }
            }

            if let chords = ChordChartParser.plainChords(raw) {
                flushPending()
                sawPlain = true
                pending = chords
                return
            }

            lines.append(ChordChart.Line(text: Self.trimTrailing(raw), chords: pending ?? []))
            pending = nil
        }

        mutating func directive(_ body: String) -> Bool {
            let parts = body.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let name = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            switch name {
            case "title", "t": metadata["title"] = value
            case "subtitle", "st": metadata["subtitle"] = value
            case "artist", "composer", "author": metadata["artist"] = value
            case "key": metadata["key"] = value
            case "tempo": metadata["tempo"] = value
            case "time": metadata["time"] = value
            case "capo": metadata["capo"] = value
            case "comment", "c", "comment_italic", "ci", "comment_box", "cb":
                flushPending()
                if !value.isEmpty { startSection(value) }
            case "start_of_chorus", "soc", "start_of_verse", "sov", "start_of_bridge", "sob":
                flushPending()
                let fallback = name.contains("chorus") || name == "soc" ? "Chorus" : (name.contains("verse") || name == "sov" ? "Verse" : "Bridge")
                startSection(value.isEmpty ? fallback : value)
            default:
                guard name.hasPrefix("end_of") || name.hasPrefix("eo") || name.hasPrefix("start_of") || name.hasPrefix("so")
                    || Self.knownIgnored.contains(name) else { return false }
            }
            return true
        }

        static let knownIgnored: Set<String> = [
            "new_song", "ns", "define", "textsize", "textfont", "chordsize", "chordfont", "columns", "col",
            "column_break", "new_page", "np", "new_physical_page", "npp", "meta", "image",
        ]

        mutating func flushPending() {
            guard let chords = pending else { return }
            lines.append(ChordChart.Line(text: "", chords: chords))
            pending = nil
        }

        mutating func startSection(_ newTitle: String) {
            closeSection()
            title = newTitle
        }

        mutating func closeSection() {
            flushPending()
            while lines.first?.isBlank == true { lines.removeFirst() }
            while lines.last?.isBlank == true { lines.removeLast() }
            if title != nil || !lines.isEmpty {
                sections.append(ChordChart.Section(title: title, lines: lines))
            }
            title = nil
            lines = []
        }

        mutating func finish() -> ChordChart {
            closeSection()
            let format: ChordChart.Format = sawInline ? .chordPro : (sawPlain ? .plain : .lyricsOnly)
            return ChordChart(sections: sections, format: format, metadata: metadata)
        }

        static func trimTrailing(_ text: String) -> String {
            var result = text
            while result.last == " " { result.removeLast() }
            return result
        }
    }
}
