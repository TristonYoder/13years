// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct CommandLineContext: Equatable, Sendable {
    public var itemTypes: [String]
    public var roles: [String]
    public var itemCount: Int
    public var hasSelection: Bool
    public var views: [String]
    public var documentActions: Bool

    public init(
        itemTypes: [String] = ItemCommandParser.knownTypes,
        roles: [String] = [],
        itemCount: Int = 0,
        hasSelection: Bool = false,
        views: [String] = AppMode.sidebarCases.map(\.displayName),
        documentActions: Bool = false
    ) {
        self.itemTypes = itemTypes
        self.roles = roles
        self.itemCount = itemCount
        self.hasSelection = hasSelection
        self.views = views
        self.documentActions = documentActions
    }
}

public enum CommandAction: Equatable, Sendable {
    case view(AppMode)
    case play, pause, next, back, reset
    case save, open, connect, disconnect, flash
}

public struct CommandStatement: Equatable, Sendable {
    public enum Verb: String, Sendable { case store, label, move, copy, delete, standby, go, edit, action }

    public var verb: Verb = .edit
    public var position: Int?
    public var count = 1
    public var title: String?
    public var type: String?
    public var length: TimerInputParser.Action?
    public var trigger: ItemTrigger?
    public var roles: [String] = []
    public var target: Int?
    public var action: CommandAction?

    public init() {}

    public var hasItemClause: Bool { position != nil }

    public var changesAttributes: Bool {
        title != nil || type != nil || length != nil || trigger != nil || !roles.isEmpty
    }

    public func resolvedLength(base: Int) -> Int {
        switch length {
        case .setAbsolute(let seconds): return TimerLimits.clampLength(seconds)
        case .adjustRelative(let delta): return TimerLimits.clampLength(base + delta)
        case .endAt, nil: return base
        }
    }
}

public enum CommandLineStatus: Equatable, Sendable {
    case empty
    case incomplete(String)
    case ready
    case ambiguous(String)
    case invalid(String)

    public var isReady: Bool { self == .ready }
}

public struct CommandLinePiece: Equatable, Sendable {
    public enum Kind: Sendable { case resolved, value, prediction, ambiguous, invalid }

    public var text: String
    public var kind: Kind
}

public struct CommandLineSuggestion: Equatable, Identifiable, Sendable {
    public var word: String
    public var summary: String
    public var example: String
    public var id: String { word }

    var insertion: String { word.contains(" ") ? "\"\(word)\"" : word }
}

public struct CommandLineAnalysis: Equatable, Sendable {
    public var raw: String
    public var pieces: [CommandLinePiece]
    public var suggestions: [CommandLineSuggestion]
    public var ghost: String
    public var status: CommandLineStatus
    public var statement: CommandStatement?
    public var hint: String?
    var partialStart: Int?

    public func completed(with suggestion: CommandLineSuggestion) -> String {
        let prefix = partialStart.map { String(raw.prefix($0)) } ?? raw
        let separator = partialStart == nil && !prefix.isEmpty && !(prefix.last?.isWhitespace ?? true) ? " " : ""
        return prefix + separator + suggestion.insertion + " "
    }
}

public enum CommandLine {
    public static func startsWithNumber(_ raw: String) -> Bool {
        guard let first = raw.first(where: { !$0.isWhitespace }) else { return false }
        return first.isASCII && first.isNumber
    }

    public static func analyze(_ raw: String, context: CommandLineContext) -> CommandLineAnalysis {
        var (tokens, hasPartial) = tokenize(raw)
        var partial: Tok?
        if hasPartial, let last = tokens.popLast() { partial = last }
        hasPartial = partial != nil

        var machine = Machine(context: context)
        for token in tokens { machine.consume(token) }

        var pieces = machine.pieces
        var suggestions = partial?.quoted == true ? [] : machine.suggestions(prefix: partial?.text)
        var ghost = ""
        if let partial {
            if let top = suggestions.first, !partial.quoted, top.word.lowercased().hasPrefix(partial.text.lowercased()), top.word.count > partial.text.count {
                ghost = String(top.word.dropFirst(partial.text.count))
            }
            pieces.append(machine.partialPiece(partial, top: suggestions.first))
        }
        if machine.expectsValue { suggestions = [] }

        let status = machine.status(hasPartial: hasPartial, isEmpty: tokens.isEmpty && !hasPartial)
        let statement: CommandStatement? = status.isReady ? machine.statement : nil
        return CommandLineAnalysis(
            raw: raw,
            pieces: pieces,
            suggestions: suggestions,
            ghost: ghost,
            status: status,
            statement: statement,
            hint: machine.hint,
            partialStart: partial?.start
        )
    }

    struct Tok {
        var text: String
        var quoted: Bool
        var start: Int
    }

    static func tokenize(_ raw: String) -> (tokens: [Tok], hasPartial: Bool) {
        var tokens: [Tok] = []
        var current = ""
        var start = 0
        var inQuotes = false
        var offset = 0
        func flush() {
            guard !current.isEmpty else { return }
            if current.hasPrefix("@"), current.count > 1 {
                tokens.append(Tok(text: "at", quoted: false, start: start))
                tokens.append(Tok(text: String(current.dropFirst()), quoted: false, start: start))
            } else if current == "@" {
                tokens.append(Tok(text: "at", quoted: false, start: start))
            } else {
                tokens.append(Tok(text: current, quoted: false, start: start))
            }
            current = ""
        }
        for char in raw {
            if char == "\"" {
                if inQuotes {
                    tokens.append(Tok(text: current, quoted: true, start: start))
                    current = ""
                    inQuotes = false
                } else {
                    flush()
                    inQuotes = true
                    start = offset
                }
            } else if char.isWhitespace && !inQuotes {
                flush()
            } else {
                if current.isEmpty && !inQuotes { start = offset }
                current.append(char)
            }
            offset += 1
        }
        var hasPartial = false
        if inQuotes {
            tokens.append(Tok(text: current, quoted: true, start: start))
            hasPartial = true
        } else if !current.isEmpty {
            flush()
            hasPartial = true
        }
        return (tokens, hasPartial)
    }

    enum Word: String, CaseIterable {
        case store, label, move, copy, delete, standby, go, item, thru, time, at, type, trigger, role
        case view, play, pause, next, back, reset, save, open, connect, disconnect, flash

        var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

        var summary: String {
            switch self {
            case .store: return "Create items"
            case .label: return "Name an item"
            case .move: return "Reorder items"
            case .copy: return "Duplicate items"
            case .delete: return "Remove items"
            case .standby: return "Call standby roles"
            case .go: return "Go now"
            case .item: return "Pick items by number"
            case .thru: return "Range end"
            case .time: return "Set length"
            case .at: return "Position or time"
            case .type: return "Set item type"
            case .trigger: return "Follow or Go"
            case .role: return "Cue roles"
            case .view: return "Switch tab"
            case .play: return "Start the timer"
            case .pause: return "Pause the timer"
            case .next: return "Next item"
            case .back: return "Previous item"
            case .reset: return "Reset the timer"
            case .save: return "Save the document"
            case .open: return "Open a document"
            case .connect: return "Connect to a producer"
            case .disconnect: return "Disconnect"
            case .flash: return "Flash a pager"
            }
        }

        var example: String {
            switch self {
            case .store: return "Store \"Offering\" Time 5m"
            case .label: return "Label Item 3 \"Offering\""
            case .move: return "Move Item 5 At 2"
            case .copy: return "Copy Item 2 At 7"
            case .delete: return "Delete Item 4 Thru 6"
            case .standby: return "Standby Item 3"
            case .go: return "Go Item 3"
            case .item: return "Item 4 Thru 6"
            case .thru: return "Item 4 Thru 6"
            case .time: return "Item 4 Time 5m"
            case .at: return "Move Item 5 At 2"
            case .type: return "Item 4 Type Song"
            case .trigger: return "Item 4 Trigger Follow"
            case .role: return "Item 4 Role Band + Host"
            case .view: return "View Run Sheet"
            case .play: return "Play"
            case .pause: return "Pause"
            case .next: return "Next"
            case .back: return "Back"
            case .reset: return "Reset"
            case .save: return "Save"
            case .open: return "Open"
            case .connect: return "Connect"
            case .disconnect: return "Disconnect"
            case .flash: return "Flash"
            }
        }

        static let verbs: [Word] = [.store, .label, .move, .copy, .delete, .standby, .go]
        static let actions: [Word] = [.view, .play, .pause, .next, .back, .reset, .save, .open, .connect, .disconnect, .flash]
        static let documentWords: Set<Word> = [.save, .open, .connect, .disconnect, .flash]
    }

    enum Expect: Equatable {
        case keywords([Word])
        case number(Word)
        case time
        case text
        case typeName
        case roleName
        case roleMore
        case trigger
        case viewName
    }

    struct Match {
        var one: String?
        var many: [String] = []
    }

    static func match(_ text: String, in options: [String]) -> Match {
        let lowered = text.lowercased()
        if let exact = options.first(where: { $0.lowercased() == lowered }) { return Match(one: exact) }
        let prefixed = options.filter { $0.lowercased().hasPrefix(lowered) }
        if prefixed.count == 1 { return Match(one: prefixed[0]) }
        return Match(many: prefixed)
    }

    struct Machine {
        let context: CommandLineContext
        var statement = CommandStatement()
        var pieces: [CommandLinePiece] = []
        var expect: Expect = .keywords([])
        var used: Set<Word> = []
        var started = false
        var error: String?
        var ambiguity: String?
        var pendingSign: String?
        var triggerWord = false

        init(context: CommandLineContext) {
            self.context = context
            expect = .keywords(startWords)
        }

        var actionWords: [Word] { Word.actions.filter { !Word.documentWords.contains($0) || context.documentActions } }
        var startWords: [Word] { Word.verbs + [.item, .time, .type, .trigger, .role] + actionWords }

        var expectsValue: Bool {
            switch expect {
            case .number, .time, .text: return true
            default: return false
            }
        }

        var hint: String? {
            switch expect {
            case .number(let word):
                switch word {
                case .item: return "Type an item number"
                case .thru: return "Type the last item number"
                default: return "Type a position"
                }
            case .time: return "Type a time: 5m, 4:30, +30, 1h30m"
            case .text: return "Type a name in quotes"
            default: return nil
            }
        }

        func clauseWords() -> [Word] {
            let hasItem = statement.hasItemClause
            switch statement.verb {
            case .action:
                return []
            case .store, .edit:
                var words: [Word] = []
                if !hasItem { words.append(.item) }
                if statement.title == nil { words.append(.label) }
                words += [.time, .type, .trigger, .role]
                return words.filter { !used.contains($0) }
            case .label, .delete, .standby, .go:
                return hasItem ? [] : [.item]
            case .move, .copy:
                if !hasItem { return [.item] }
                return statement.target == nil ? [.at] : []
            }
        }

        mutating func addPiece(_ text: String, _ kind: CommandLinePiece.Kind) {
            pieces.append(CommandLinePiece(text: text, kind: kind))
        }

        mutating func consume(_ token: Tok) {
            if error != nil || ambiguity != nil {
                addPiece(token.quoted ? "\"\(token.text)\"" : token.text, .value)
                return
            }
            switch expect {
            case .keywords(let words): consumeKeyword(token, words)
            case .number(let word): consumeNumber(token, word)
            case .time: consumeTime(token)
            case .text: consumeText(token)
            case .typeName: consumeType(token)
            case .roleName: consumeRole(token)
            case .roleMore:
                if !token.quoted && token.text == "+" {
                    addPiece("+", .resolved)
                    expect = .roleName
                } else {
                    expect = .keywords(clauseWords())
                    consumeKeyword(token, clauseWords())
                }
            case .trigger: consumeTrigger(token)
            case .viewName: consumeView(token)
            }
        }

        mutating func consumeKeyword(_ token: Tok, _ words: [Word]) {
            if token.quoted {
                let allowsTitle = [.store, .edit, .label].contains(statement.verb) && statement.title == nil
                if allowsTitle {
                    statement.title = token.text
                    addPiece("\"\(token.text)\"", .value)
                } else {
                    error = "Unexpected text \u{201C}\(token.text)\u{201D}"
                    addPiece("\"\(token.text)\"", .invalid)
                }
                return
            }
            var options = words.map(\.title)
            if !started || statement.verb == .store || statement.verb == .edit { options += words.contains(.time) ? [Word.at.title] : [] }
            let result = CommandLine.match(token.text, in: options)
            if let one = result.one, let word = Word(rawValue: one.lowercased()) {
                apply(word)
            } else if result.many.count > 1 {
                ambiguity = result.many.joined(separator: ", ")
                addPiece(result.many.joined(separator: " / "), .ambiguous)
            } else {
                error = words.isEmpty ? "Nothing more goes after this. Press Enter to run it." : "Not understood: \(token.text)"
                addPiece(token.text, .invalid)
            }
        }

        mutating func apply(_ word: Word) {
            let atStart = !started
            started = true
            if atStart {
                if Word.actions.contains(word) {
                    statement.verb = .action
                } else {
                    statement.verb = Word.verbs.contains(word) ? CommandStatement.Verb.from(word) : .edit
                }
            }
            addPiece(word.title, .resolved)
            if atStart && Word.actions.contains(word) {
                switch word {
                case .view: expect = .viewName
                case .play: statement.action = .play
                case .pause: statement.action = .pause
                case .next: statement.action = .next
                case .back: statement.action = .back
                case .reset: statement.action = .reset
                case .save: statement.action = .save
                case .open: statement.action = .open
                case .connect: statement.action = .connect
                case .disconnect: statement.action = .disconnect
                default: statement.action = .flash
                }
                if word != .view { expect = .keywords([]) }
                return
            }
            if atStart && Word.verbs.contains(word) {
                expect = .keywords(clauseWords())
                return
            }
            switch word {
            case .item:
                used.insert(.item)
                expect = .number(.item)
            case .thru:
                expect = .number(.thru)
            case .at:
                if statement.verb == .move || statement.verb == .copy {
                    expect = .number(.at)
                } else {
                    pieces[pieces.count - 1].text = Word.time.title
                    used.insert(.time)
                    expect = .time
                }
            case .time:
                used.insert(.time)
                expect = .time
            case .type:
                used.insert(.type)
                expect = .typeName
            case .role:
                used.insert(.role)
                expect = .roleName
            case .trigger:
                used.insert(.trigger)
                expect = .trigger
            case .label:
                used.insert(.label)
                expect = .text
            default:
                expect = .keywords(clauseWords())
            }
        }

        mutating func consumeNumber(_ token: Tok, _ word: Word) {
            guard !token.quoted, token.text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(token.text), value >= 1 else {
                error = "\(word.title) needs a number"
                addPiece(token.text, .invalid)
                return
            }
            addPiece(token.text, .value)
            switch word {
            case .item:
                statement.position = value
                expect = .keywords([.thru] + clauseWords())
            case .thru:
                guard let first = statement.position, value >= first else {
                    error = "Thru needs an end of \(statement.position ?? 1) or more"
                    return
                }
                statement.count = value - first + 1
                if statement.count > ItemCommandParser.maxCount { error = "That's more than \(ItemCommandParser.maxCount) items at once" }
                expect = .keywords(clauseWords())
            default:
                statement.target = value
                expect = .keywords(clauseWords())
            }
        }

        mutating func consumeTime(_ token: Tok) {
            if !token.quoted, pendingSign == nil, token.text == "+" || token.text == "-" {
                pendingSign = token.text
                addPiece(token.text, .value)
                return
            }
            let text = (pendingSign ?? "") + token.text
            if pendingSign != nil { pieces.removeLast() }
            pendingSign = nil
            guard !token.quoted, let action = TimerInputParser.parse(text) else {
                error = "Couldn't read the time \u{201C}\(text)\u{201D}"
                addPiece(text, .invalid)
                return
            }
            statement.length = action
            addPiece(text, .value)
            expect = .keywords(clauseWords())
        }

        mutating func consumeText(_ token: Tok) {
            guard token.quoted else {
                error = "Put the name in quotes, like \"Offering\""
                addPiece(token.text, .invalid)
                return
            }
            statement.title = token.text
            addPiece("\"\(token.text)\"", .value)
            expect = .keywords(clauseWords())
        }

        mutating func consumeType(_ token: Tok) {
            let result = CommandLine.match(token.text, in: context.itemTypes)
            if let one = result.one {
                statement.type = one
                addPiece(one, .resolved)
            } else if result.many.count > 1 {
                ambiguity = result.many.joined(separator: ", ")
                addPiece(result.many.joined(separator: " / "), .ambiguous)
                return
            } else {
                statement.type = token.text
                addPiece(token.text, .value)
            }
            expect = .keywords(clauseWords())
        }

        mutating func consumeRole(_ token: Tok) {
            let result = CommandLine.match(token.text, in: context.roles)
            if let one = result.one {
                if !statement.roles.contains(one) { statement.roles.append(one) }
                addPiece(one, .resolved)
                expect = .roleMore
            } else if result.many.count > 1 {
                ambiguity = result.many.joined(separator: ", ")
                addPiece(result.many.joined(separator: " / "), .ambiguous)
            } else {
                error = "No role called \u{201C}\(token.text)\u{201D}"
                addPiece(token.text, .invalid)
            }
        }

        mutating func consumeView(_ token: Tok) {
            let result = CommandLine.match(token.text, in: context.views)
            guard let one = result.one, let mode = AppMode.sidebarCases.first(where: { $0.displayName == one }) else {
                if result.many.count > 1 {
                    ambiguity = result.many.joined(separator: ", ")
                    addPiece(result.many.joined(separator: " / "), .ambiguous)
                } else {
                    error = "No tab called \u{201C}\(token.text)\u{201D}"
                    addPiece(token.text, .invalid)
                }
                return
            }
            statement.action = .view(mode)
            addPiece(one, .resolved)
            expect = .keywords([])
        }

        mutating func consumeTrigger(_ token: Tok) {
            let result = CommandLine.match(token.text, in: ["Follow", "Go"])
            guard let one = result.one else {
                error = "Trigger is Follow or Go"
                addPiece(token.text, .invalid)
                return
            }
            statement.trigger = one == "Follow" ? .follow : .go
            addPiece(one, .resolved)
            expect = .keywords(clauseWords())
        }

        func suggestions(prefix: String?) -> [CommandLineSuggestion] {
            guard error == nil, ambiguity == nil else { return [] }
            var all: [CommandLineSuggestion] = []
            switch expect {
            case .keywords(let words):
                let shown = started ? words : Word.verbs + [.item] + actionWords
                all = shown.map { CommandLineSuggestion(word: $0.title, summary: $0.summary, example: $0.example) }
            case .typeName:
                all = context.itemTypes.map { CommandLineSuggestion(word: $0, summary: "Item type", example: "Type \($0)") }
            case .roleName:
                all = context.roles.filter { !statement.roles.contains($0) }.map { CommandLineSuggestion(word: $0, summary: "Cue role", example: "Role \($0)") }
            case .roleMore:
                all = clauseWords().map { CommandLineSuggestion(word: $0.title, summary: $0.summary, example: $0.example) }
            case .trigger:
                all = [
                    CommandLineSuggestion(word: "Follow", summary: "Starts when the item before it ends", example: "Trigger Follow"),
                    CommandLineSuggestion(word: "Go", summary: "Waits for a manual Go", example: "Trigger Go")
                ]
            case .viewName:
                all = context.views.map { CommandLineSuggestion(word: $0, summary: "Tab", example: "View \($0)") }
            case .number, .time, .text:
                return []
            }
            guard let prefix, !prefix.isEmpty else { return all }
            return all.filter { $0.word.lowercased().hasPrefix(prefix.lowercased()) }
        }

        func partialPiece(_ token: Tok, top: CommandLineSuggestion?) -> CommandLinePiece {
            if token.quoted { return CommandLinePiece(text: "\"\(token.text)", kind: .value) }
            if error != nil || ambiguity != nil { return CommandLinePiece(text: token.text, kind: .value) }
            if expectsValue { return CommandLinePiece(text: token.text, kind: .value) }
            if let top { return CommandLinePiece(text: top.word, kind: .prediction) }
            if case .typeName = expect { return CommandLinePiece(text: token.text, kind: .value) }
            return CommandLinePiece(text: token.text, kind: .invalid)
        }

        func status(hasPartial: Bool, isEmpty: Bool) -> CommandLineStatus {
            if isEmpty { return .empty }
            if let ambiguity { return .ambiguous("Ambiguous: \(ambiguity). Add a letter.") }
            if let error { return .invalid(error) }
            if hasPartial { return .incomplete("Finish the word, or press Tab to accept") }
            switch expect {
            case .number, .time, .text: return .incomplete(hint ?? "Needs a value")
            case .typeName: return .incomplete("Type needs a name, like Type Song")
            case .roleName: return .incomplete("Role needs a name")
            case .trigger: return .incomplete("Trigger is Follow or Go")
            case .viewName: return .incomplete("View needs a tab, like View Run Sheet")
            default: break
            }
            let verb = statement.verb
            let needsTarget = !statement.hasItemClause && !context.hasSelection
            switch verb {
            case .store, .action:
                break
            case .label:
                if statement.title == nil { return .incomplete("Label needs a name, like \"Offering\"") }
                if needsTarget { return .incomplete("Pick an item, like Item 3, or select a row") }
            case .move, .copy:
                if needsTarget { return .incomplete("Pick an item, like Item 3, or select a row") }
                if statement.target == nil { return .incomplete("Add At and a position, like At 2") }
            case .delete, .standby, .go:
                if needsTarget { return .incomplete("Pick an item, like Item 3, or select a row") }
            case .edit:
                if statement.changesAttributes && needsTarget { return .incomplete("Pick an item, like Item 3, or select a row") }
            }
            if verb != .store, statement.hasItemClause, let first = statement.position {
                let last = first + statement.count - 1
                if first > context.itemCount { return .invalid("There's no Item \(first). The run sheet has \(context.itemCount).") }
                if last > context.itemCount { return .invalid("There's no Item \(last). The run sheet has \(context.itemCount).") }
            }
            return .ready
        }
    }
}

extension CommandStatement.Verb {
    fileprivate static func from(_ word: CommandLine.Word) -> CommandStatement.Verb {
        switch word {
        case .store: return .store
        case .label: return .label
        case .move: return .move
        case .copy: return .copy
        case .delete: return .delete
        case .standby: return .standby
        case .go: return .go
        default: return .edit
        }
    }
}
