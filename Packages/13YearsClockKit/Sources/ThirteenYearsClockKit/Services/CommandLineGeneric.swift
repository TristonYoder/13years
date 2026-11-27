// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

extension CommandLine {
    enum GNumber { case event, rehearsal, schedule

        var noun: String {
            switch self {
            case .event: return "Event"
            case .rehearsal: return "Rehearsal"
            case .schedule: return "Schedule"
            }
        }
    }

    enum GArg: Equatable {
        case roleNames(multi: Bool)
        case waypointName
        case number(GNumber)
        case text
        case clockTime
        case timeOfDay
        case day
        case ip
        case choice(String, [String])
        case attributes
        case optionalRole

        var isOptional: Bool { self == .attributes || self == .optionalRole }
    }

    static let weekdayShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    static func nouns(for verb: CommandStatement.Verb) -> [Word] {
        switch verb {
        case .store: return [.role, .message, .waypoint, .event, .rehearsal]
        case .label: return [.role, .waypoint]
        case .delete: return [.role, .message, .waypoint, .event, .rehearsal, .schedule]
        case .standby: return [.role]
        case .go: return [.role, .waypoint, .event, .schedule]
        default: return []
        }
    }

    static func verbWord(_ statement: CommandStatement) -> Word? {
        switch statement.verb {
        case .store: return .store
        case .label: return .label
        case .delete: return .delete
        case .standby: return .standby
        case .go: return .go
        case .action:
            if statement.action == .next { return .next }
            if statement.action == .clearCues { return .clear }
            return nil
        default: return nil
        }
    }

    static func genericNoun(_ word: Word, verb: CommandStatement.Verb, action: CommandAction?) -> Bool {
        guard Word.genericNouns.contains(word) else { return false }
        var probe = CommandStatement()
        probe.verb = verb
        probe.action = action
        guard let verbWord = verbWord(probe) else { return false }
        return template(verb: verbWord, noun: word) != nil
    }

    static func template(verb: Word?, noun: Word) -> (key: String, args: [GArg])? {
        if verb == nil {
            switch noun {
            case .clock: return ("clock", [.clockTime])
            case .plan: return ("plan", [.choice("action", ["Title"])])
            case .set: return ("set", [.choice("setting", ["Format", "Threshold", "Follow", "Endtimes"])])
            case .pco: return ("pco", [.choice("action", ["Live", "Unlink", "Changes"])])
            case .pager: return ("pager", [.choice("action", ["Ping", "Master", "Forget"])])
            default: return nil
            }
        }
        guard let verb else { return nil }
        let key = "\(verb.rawValue).\(noun.rawValue)"
        switch (verb, noun) {
        case (.store, .role): return (key, [.text])
        case (.label, .role): return (key, [.roleNames(multi: false), .text])
        case (.delete, .role), (.standby, .role), (.go, .role), (.clear, .role): return (key, [.roleNames(multi: true)])
        case (.store, .message): return (key, [.text, .optionalRole])
        case (.delete, .message), (.clear, .message): return (key, [])
        case (.store, .waypoint): return (key, [.text])
        case (.label, .waypoint): return (key, [.waypointName, .text])
        case (.delete, .waypoint), (.go, .waypoint): return (key, [.waypointName])
        case (.go, .event), (.delete, .event): return (key, [.number(.event)])
        case (.next, .event): return (key, [])
        case (.store, .event), (.store, .rehearsal): return (key, [.attributes])
        case (.delete, .rehearsal): return (key, [.number(.rehearsal)])
        case (.go, .schedule), (.delete, .schedule): return (key, [.number(.schedule)])
        default: return nil
        }
    }

    static func parseTimeOfDay(_ raw: String) -> String? {
        var text = raw.lowercased()
        var isPM: Bool?
        if text.hasSuffix("am") { isPM = false; text.removeLast(2) } else if text.hasSuffix("pm") { isPM = true; text.removeLast(2) }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2, let hourValue = Int(parts[0]) else { return nil }
        var hour = hourValue
        let minute = parts.count == 2 ? Int(parts[1]) ?? -1 : 0
        if let isPM {
            guard (1...12).contains(hour) else { return nil }
            if hour == 12 { hour = 0 }
            if isPM { hour += 12 }
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }
}

extension CommandLine.Machine {
    typealias GArg = CommandLine.GArg

    var needsStoreMode: Bool {
        guard statement.verb == .store, let position = statement.position, statement.storeMode == nil else { return false }
        return position <= context.itemCount
    }

    var genericExpectsValue: Bool {
        guard let arg = genericArgs.first, !expectPlus else { return false }
        switch arg {
        case .number, .text, .clockTime, .timeOfDay, .ip: return true
        default: return false
        }
    }

    var genericHint: String? {
        guard let arg = genericArgs.first, !expectPlus else { return nil }
        switch arg {
        case .number(let kind): return "Type a \(kind.noun.lowercased()) number"
        case .text: return "Type a name in quotes"
        case .clockTime: return "Type a time: +30, 5m, 4:30"
        case .timeOfDay: return "Type a time of day: 9:00, 18:30, 9:00am"
        case .ip: return "Type an IP address, like 10.0.0.5"
        default: return nil
        }
    }

    mutating func beginGeneric(verb: CommandLine.Word?, noun: CommandLine.Word) {
        guard let template = CommandLine.template(verb: verb, noun: noun) else {
            error = "\(noun.title) can't be used here"
            return
        }
        statement.verb = .generic
        statement.action = nil
        statement.generic.key = template.key
        genericArgs = template.args
        expect = .generic
    }

    mutating func popGenericArg() {
        if !genericArgs.isEmpty { genericArgs.removeFirst() }
    }

    mutating func consumeGeneric(_ token: CommandLine.Tok) {
        if expectPlus {
            if !token.quoted && token.text == "+" {
                addPiece("+", .resolved)
                expectPlus = false
                return
            }
            expectPlus = false
            popGenericArg()
        }
        guard let arg = genericArgs.first else {
            error = "Nothing more goes after this. Press Enter to run it."
            addPiece(token.quoted ? "\"\(token.text)\"" : token.text, .invalid)
            return
        }
        switch arg {
        case .roleNames(let multi): consumeNames(token, source: context.roles, noun: "role", multi: multi)
        case .waypointName: consumeNames(token, source: context.waypoints, noun: "waypoint", multi: false)
        case .number(let kind): consumeGenericNumber(token, kind)
        case .text: consumeGenericText(token)
        case .clockTime: consumeClock(token)
        case .timeOfDay: consumeTimeOfDay(token)
        case .day: consumeDay(token)
        case .ip: consumeIP(token)
        case .choice(let slot, let options): consumeChoice(token, slot: slot, options: options)
        case .attributes: consumeAttributeKeyword(token)
        case .optionalRole:
            let result = CommandLine.match(token.text, in: ["Role"])
            if !token.quoted, result.one != nil {
                addPiece("Role", .resolved)
                genericArgs[0] = .roleNames(multi: true)
            } else {
                error = "Not understood: \(token.text)"
                addPiece(token.text, .invalid)
            }
        }
    }

    mutating func consumeNames(_ token: CommandLine.Tok, source: [String], noun: String, multi: Bool) {
        let result = CommandLine.match(token.text, in: source)
        guard let one = result.one else {
            if result.many.count > 1 {
                ambiguity = result.many.joined(separator: ", ")
                addPiece(result.many.joined(separator: " / "), .ambiguous)
            } else {
                error = "No \(noun) called \u{201C}\(token.text)\u{201D}"
                addPiece(token.text, .invalid)
            }
            return
        }
        if !statement.generic.names.contains(one) { statement.generic.names.append(one) }
        addPiece(one, .resolved)
        if multi { expectPlus = true } else { popGenericArg() }
    }

    mutating func consumeGenericNumber(_ token: CommandLine.Tok, _ kind: CommandLine.GNumber) {
        guard !token.quoted, let value = Int(token.text), value >= 1 else {
            error = "\(kind.noun) needs a number"
            addPiece(token.text, .invalid)
            return
        }
        let count: Int
        switch kind {
        case .event: count = context.eventCount
        case .rehearsal: count = context.rehearsalCount
        case .schedule: count = context.scheduleCount
        }
        guard value <= count else {
            error = "There's no \(kind.noun) \(value). There are \(count)."
            addPiece(token.text, .invalid)
            return
        }
        statement.generic.number = value
        addPiece(token.text, .value)
        popGenericArg()
    }

    mutating func consumeGenericText(_ token: CommandLine.Tok) {
        guard token.quoted else {
            error = "Put the name in quotes, like \"Offering\""
            addPiece(token.text, .invalid)
            return
        }
        statement.generic.text = token.text
        addPiece("\"\(token.text)\"", .value)
        popGenericArg()
    }

    mutating func consumeClock(_ token: CommandLine.Tok) {
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
        statement.generic.clock = action
        addPiece(text, .value)
        popGenericArg()
    }

    mutating func consumeTimeOfDay(_ token: CommandLine.Tok) {
        guard !token.quoted, let value = CommandLine.parseTimeOfDay(token.text) else {
            error = "Couldn't read the time of day \u{201C}\(token.text)\u{201D}"
            addPiece(token.text, .invalid)
            return
        }
        statement.generic.timeOfDay = value
        addPiece(token.text, .value)
        popGenericArg()
    }

    mutating func consumeDay(_ token: CommandLine.Tok) {
        let result = CommandLine.match(token.text, in: CommandLine.weekdayShort)
        guard let one = result.one, let index = CommandLine.weekdayShort.firstIndex(of: one) else {
            error = "Day is Sun, Mon, Tue, Wed, Thu, Fri or Sat"
            addPiece(token.text, .invalid)
            return
        }
        statement.generic.day = EventDay.weekdayNames[index]
        addPiece(one, .resolved)
        popGenericArg()
    }

    mutating func consumeIP(_ token: CommandLine.Tok) {
        let parts = token.text.split(separator: ".", omittingEmptySubsequences: false)
        guard !token.quoted, parts.count == 4, parts.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }) else {
            error = "Couldn't read the address \u{201C}\(token.text)\u{201D}"
            addPiece(token.text, .invalid)
            return
        }
        statement.generic.ip = token.text
        addPiece(token.text, .value)
        popGenericArg()
    }

    mutating func consumeChoice(_ token: CommandLine.Tok, slot: String, options: [String]) {
        let result = CommandLine.match(token.text, in: options)
        guard let one = result.one else {
            if result.many.count > 1 {
                ambiguity = result.many.joined(separator: ", ")
                addPiece(result.many.joined(separator: " / "), .ambiguous)
            } else {
                error = "Not understood: \(token.text)"
                addPiece(token.text, .invalid)
            }
            return
        }
        statement.generic.choices.append(one)
        addPiece(one, .resolved)
        popGenericArg()
        let base = statement.generic.key
        let value = one.lowercased()
        switch (base, slot) {
        case ("plan", "action"):
            statement.generic.key = "plan.title"
            genericArgs = [.text]
        case ("set", "setting"):
            statement.generic.key = "set.\(value)"
            switch value {
            case "format": genericArgs = [.choice("value", ["12h", "24h"])]
            case "threshold": genericArgs = [.choice("value", ["60m", "90m", "Never"])]
            default: genericArgs = [.choice("value", ["On", "Off"])]
            }
        case ("pco", "action"):
            statement.generic.key = "pco.\(value)"
            switch value {
            case "live": genericArgs = [.choice("value", ["On", "Off"])]
            case "changes": genericArgs = [.choice("value", ["Accept", "Dismiss"])]
            default: genericArgs = []
            }
        case ("pager", "action"):
            statement.generic.key = "pager.\(value)"
            switch value {
            case "ping": genericArgs = [.ip]
            case "master": genericArgs = [.choice("value", ["On", "Off"])]
            default: genericArgs = []
            }
        default:
            break
        }
    }

    mutating func consumeAttributeKeyword(_ token: CommandLine.Tok) {
        let options = ["Label", "Day", "Time"].filter { !genericUsed.contains($0) }
        let result = CommandLine.match(token.text, in: options)
        guard !token.quoted, let one = result.one else {
            if result.many.count > 1 {
                ambiguity = result.many.joined(separator: ", ")
                addPiece(result.many.joined(separator: " / "), .ambiguous)
            } else {
                error = "Not understood: \(token.text)"
                addPiece(token.text, .invalid)
            }
            return
        }
        genericUsed.insert(one)
        addPiece(one, .resolved)
        switch one {
        case "Label": genericArgs.insert(.text, at: 0)
        case "Day": genericArgs.insert(.day, at: 0)
        default: genericArgs.insert(.timeOfDay, at: 0)
        }
    }

    func genericSuggestions() -> [CommandLineSuggestion] {
        func words(_ items: [String], _ summary: String) -> [CommandLineSuggestion] {
            items.map { CommandLineSuggestion(word: $0, summary: summary, example: "") }
        }
        var list = genericArgs
        if expectPlus { list.removeFirst() }
        guard let arg = list.first else { return [] }
        switch arg {
        case .roleNames: return words(context.roles.filter { !statement.generic.names.contains($0) }, "Pager role")
        case .waypointName: return words(context.waypoints, "Waypoint")
        case .choice(_, let options): return words(options, "")
        case .day: return words(CommandLine.weekdayShort, "Day of the week")
        case .attributes: return words(["Label", "Day", "Time"].filter { !genericUsed.contains($0) }, "")
        case .optionalRole: return words(["Role"], "Send to a role")
        default: return []
        }
    }

    func genericStatus() -> CommandLineStatus {
        let remaining = expectPlus ? Array(genericArgs.dropFirst()) : genericArgs
        if let blocking = remaining.first(where: { !$0.isOptional }) {
            switch blocking {
            case .number(let kind): return .incomplete("\(kind.noun) needs a number")
            case .text: return .incomplete("Needs a name in quotes")
            case .roleNames: return .incomplete("Needs a role")
            case .waypointName: return .incomplete("Needs a waypoint")
            case .clockTime: return .incomplete("Type a time: +30, 5m, 4:30")
            case .timeOfDay: return .incomplete("Needs a time of day, like 9:00")
            case .day: return .incomplete("Needs a day, like Sun")
            case .ip: return .incomplete("Needs an IP address")
            case .choice(_, let options): return .incomplete("Choose \(options.joined(separator: ", "))")
            default: break
            }
        }
        return .ready
    }
}
