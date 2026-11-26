// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct ItemCommand: Equatable, Sendable {
    public var position: Int?
    public var count = 1
    public var title: String?
    public var type: String?
    public var length: TimerInputParser.Action?
    public var trigger: ItemTrigger?
    public var isActual: Bool?
    public var servicePosition: PCOServicePosition?

    public init() {}

    public func resolvedLength(base: Int) -> Int {
        switch length {
        case .setAbsolute(let seconds): return TimerLimits.clampLength(seconds)
        case .adjustRelative(let delta): return TimerLimits.clampLength(base + delta)
        case .endAt, nil: return base
        }
    }
}

public enum ItemCommandParser {
    public struct Result: Equatable, Sendable {
        public var command: ItemCommand
        public var errors: [String]

        public var isValid: Bool { errors.isEmpty }
    }

    public static let maxCount = 50
    public static let knownTypes = ["Item", "Song", "Header", "Media"]

    private enum Keyword: CaseIterable {
        case store, item, thru, label, time, type, trigger, follow, go

        var word: String {
            switch self {
            case .store: return "store"
            case .item: return "item"
            case .thru: return "thru"
            case .label: return "label"
            case .time: return "time"
            case .type: return "type"
            case .trigger: return "trigger"
            case .follow: return "follow"
            case .go: return "go"
            }
        }
    }

    private struct Token {
        var text: String
        var isQuoted: Bool
    }

    public static func parse(_ raw: String) -> Result {
        let tokens = tokenize(raw)
        var command = ItemCommand()
        var errors: [String] = []
        var titleWords: [String] = []
        var explicitTitle: String?
        var index = 0

        func peek() -> Token? { index < tokens.count ? tokens[index] : nil }

        func isBoundary(_ token: Token) -> Bool {
            !token.isQuoted && (keyword(token.text) != nil || token.text.hasPrefix("/") || token.text == "@")
        }

        func integer(_ token: Token?) -> Int? {
            guard let token, !token.isQuoted, token.text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(token.text)
        }

        while index < tokens.count {
            let token = tokens[index]
            index += 1
            if token.isQuoted {
                explicitTitle = token.text
                continue
            }
            if token.text == "@" {
                parseTime(tokens, &index, &command, &errors)
                continue
            }
            if token.text.hasPrefix("/") {
                parseOption(String(token.text.dropFirst()), &command, &errors)
                continue
            }
            switch keyword(token.text) {
            case .store:
                break
            case .item:
                guard let position = integer(peek()), position >= 1 else {
                    errors.append("Item needs a position, like Item 4")
                    break
                }
                index += 1
                command.position = position
                if let next = peek(), !next.isQuoted, keyword(next.text) == .thru {
                    index += 1
                    guard let last = integer(peek()), last >= position else {
                        errors.append("Thru needs an end position of \(position) or more")
                        break
                    }
                    index += 1
                    command.count = last - position + 1
                    if command.count > maxCount { errors.append("Thru can add at most \(maxCount) items at once") }
                }
            case .label:
                var words: [String] = []
                if let next = peek(), next.isQuoted {
                    index += 1
                    explicitTitle = next.text
                    break
                }
                while let next = peek(), !isBoundary(next) {
                    words.append(next.text)
                    index += 1
                }
                if words.isEmpty { errors.append("Label needs a name, like Label \"Offering\"") } else { explicitTitle = words.joined(separator: " ") }
            case .time:
                parseTime(tokens, &index, &command, &errors)
            case .type:
                guard let next = peek() else {
                    errors.append("Type needs a name, like Type Song")
                    break
                }
                index += 1
                command.type = canonicalType(next.text)
            case .trigger:
                guard let next = peek(), !next.isQuoted, let value = keyword(next.text), value == .follow || value == .go else {
                    errors.append("Trigger is Follow or Go")
                    break
                }
                index += 1
                command.trigger = value == .follow ? .follow : .go
            case .follow:
                command.trigger = .follow
            case .go:
                command.trigger = .go
            case .thru:
                errors.append("Thru goes after an item, like Item 4 Thru 6")
            case nil:
                titleWords.append(token.text)
            }
        }

        let joined = titleWords.joined(separator: " ")
        command.title = explicitTitle ?? (joined.isEmpty ? nil : joined)
        return Result(command: command, errors: errors)
    }

    private static func parseTime(_ tokens: [Token], _ index: inout Int, _ command: inout ItemCommand, _ errors: inout [String]) {
        guard index < tokens.count, !tokens[index].isQuoted else {
            errors.append("Time needs a value, like Time 4:30")
            return
        }
        var text = tokens[index].text
        index += 1
        if (text == "+" || text == "-"), index < tokens.count, !tokens[index].isQuoted {
            text += tokens[index].text
            index += 1
        }
        guard let action = TimerInputParser.parse(text) else {
            errors.append("Couldn't read the time \u{201C}\(text)\u{201D}")
            return
        }
        command.length = action
    }

    private static func parseOption(_ name: String, _ command: inout ItemCommand, _ errors: inout [String]) {
        let lowered = name.lowercased()
        func matches(_ word: String) -> Bool { lowered.count >= 3 && word.hasPrefix(lowered) }
        if matches("actual") {
            command.isActual = true
        } else if lowered == "pre" || matches("before") {
            command.servicePosition = .pre
        } else if lowered == "post" || matches("after") {
            command.servicePosition = .post
        } else {
            errors.append("Unknown option /\(name)")
        }
    }

    private static func keyword(_ text: String) -> Keyword? {
        let lowered = text.lowercased()
        if lowered == "at" { return .time }
        if let exact = Keyword.allCases.first(where: { $0.word == lowered }) { return exact }
        guard lowered.count >= 3 else { return nil }
        let candidates = Keyword.allCases.filter { $0.word.hasPrefix(lowered) }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private static func canonicalType(_ text: String) -> String {
        let lowered = text.lowercased()
        if let known = knownTypes.first(where: { $0.lowercased() == lowered }) { return known }
        let prefixed = knownTypes.filter { lowered.count >= 2 && $0.lowercased().hasPrefix(lowered) }
        return prefixed.count == 1 ? prefixed[0] : text
    }

    private static func tokenize(_ raw: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var inQuotes = false
        func flush() {
            guard !current.isEmpty else { return }
            if current.hasPrefix("@"), current.count > 1 {
                tokens.append(Token(text: "@", isQuoted: false))
                tokens.append(Token(text: String(current.dropFirst()), isQuoted: false))
            } else {
                tokens.append(Token(text: current, isQuoted: false))
            }
            current = ""
        }
        for char in raw {
            if char == "\"" {
                if inQuotes {
                    tokens.append(Token(text: current, isQuoted: true))
                    current = ""
                } else {
                    flush()
                }
                inQuotes.toggle()
            } else if char.isWhitespace && !inQuotes {
                flush()
            } else {
                current.append(char)
            }
        }
        if inQuotes {
            tokens.append(Token(text: current, isQuoted: true))
        } else {
            flush()
        }
        return tokens.filter { $0.isQuoted ? true : !$0.text.isEmpty }
    }
}
