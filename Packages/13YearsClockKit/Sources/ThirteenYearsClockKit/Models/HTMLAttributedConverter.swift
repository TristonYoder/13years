// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum HTMLUnderlineKey: AttributedStringKey {
    public typealias Value = Bool
    public static let name = "htmlUnderline"
}

public enum HTMLHeadingLevelKey: AttributedStringKey {
    public typealias Value = Int
    public static let name = "htmlHeadingLevel"
}

public enum HTMLAttributedConverter {
    public static func attributedString(fromHTML html: String) -> AttributedString {
        var builder = Builder()
        builder.run(html)
        return builder.finish()
    }

    public static func plainText(fromHTML html: String) -> String {
        String(attributedString(fromHTML: html).characters)
    }

    private static let skippedElements: Set<String> = ["script", "style", "iframe", "object", "noscript", "template"]
    private static let doubleBreakElements: Set<String> = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "ul", "ol", "pre", "table"]
    private static let singleBreakElements: Set<String> = ["div", "li", "tr", "section", "article", "header", "footer"]

    static let entities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "mdash": "\u{2014}", "ndash": "\u{2013}", "hellip": "\u{2026}", "lsquo": "\u{2018}", "rsquo": "\u{2019}",
        "ldquo": "\u{201C}", "rdquo": "\u{201D}", "copy": "\u{00A9}", "reg": "\u{00AE}", "bull": "\u{2022}",
        "middot": "\u{00B7}", "trade": "\u{2122}", "deg": "\u{00B0}", "laquo": "\u{00AB}", "raquo": "\u{00BB}",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            guard char == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                result.append(char)
                index = text.index(after: index)
                continue
            }
            let name = String(text[text.index(after: index)..<semicolon])
            var decoded: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if name.hasPrefix("#") {
                decoded = UInt32(name.dropFirst(1)).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                decoded = entities[name.lowercased()]
            }
            if let decoded {
                result += decoded
                index = text.index(after: semicolon)
            } else {
                result.append(char)
                index = text.index(after: index)
            }
        }
        return result
    }

    private struct Tag {
        var name: String
        var isClosing: Bool
        var isSelfClosing: Bool
        var attributes: [String: String]
    }

    private struct ListContext {
        var ordered: Bool
        var counter = 0
    }

    private struct Builder {
        var output = AttributedString()
        var bold = 0
        var italic = 0
        var underline = 0
        var links: [URL?] = []
        var headings: [Int] = []
        var lists: [ListContext] = []
        var quoteDepth = 0
        var preDepth = 0
        var pendingBreak = 0
        var forcedBreaks = 0
        var pendingMarker: String?
        var lineHasText = false

        mutating func run(_ html: String) {
            let hasMarkup = html.contains("<")
            var index = html.startIndex
            var text = ""
            func flush(_ builder: inout Builder) {
                guard !text.isEmpty else { return }
                builder.append(text: text, plain: !hasMarkup)
                text = ""
            }
            while index < html.endIndex {
                let char = html[index]
                guard char == "<" else {
                    text.append(char)
                    index = html.index(after: index)
                    continue
                }
                let rest = html[index...]
                if rest.hasPrefix("<!--") {
                    flush(&self)
                    if let end = rest.range(of: "-->") { index = end.upperBound } else { index = html.endIndex }
                    continue
                }
                let afterBracket = html.index(after: index)
                guard afterBracket < html.endIndex, html[afterBracket].isLetter || html[afterBracket] == "/" || html[afterBracket] == "!" else {
                    text.append(char)
                    index = afterBracket
                    continue
                }
                guard let (tag, next) = Self.parseTag(html, from: index) else {
                    text.append(char)
                    index = afterBracket
                    continue
                }
                flush(&self)
                index = next
                if !tag.isClosing, HTMLAttributedConverter.skippedElements.contains(tag.name), !tag.isSelfClosing {
                    let closing = "</\(tag.name)"
                    if let end = html.range(of: closing, options: .caseInsensitive, range: index..<html.endIndex),
                       let close = html.range(of: ">", range: end.upperBound..<html.endIndex) {
                        index = close.upperBound
                    } else {
                        index = html.endIndex
                    }
                    continue
                }
                handle(tag)
            }
            flush(&self)
        }

        static func parseTag(_ html: String, from start: String.Index) -> (Tag, String.Index)? {
            var index = html.index(after: start)
            var raw = ""
            var quote: Character?
            var closed = false
            while index < html.endIndex {
                let char = html[index]
                index = html.index(after: index)
                if let q = quote {
                    if char == q { quote = nil }
                    raw.append(char)
                } else if char == "\"" || char == "'" {
                    quote = char
                    raw.append(char)
                } else if char == ">" {
                    closed = true
                    break
                } else {
                    raw.append(char)
                }
            }
            guard closed else { return nil }
            var body = Substring(raw)
            let isClosing = body.hasPrefix("/")
            if isClosing { body = body.dropFirst() }
            let isSelfClosing = body.hasSuffix("/")
            if isSelfClosing { body = body.dropLast() }
            if body.hasPrefix("!") { return (Tag(name: "!", isClosing: false, isSelfClosing: true, attributes: [:]), index) }
            let name = String(body.prefix { !$0.isWhitespace && $0 != "/" }).lowercased()
            guard !name.isEmpty else { return nil }
            let attributes = parseAttributes(String(body.dropFirst(name.count)))
            return (Tag(name: name, isClosing: isClosing, isSelfClosing: isSelfClosing, attributes: attributes), index)
        }

        static func parseAttributes(_ text: String) -> [String: String] {
            var result: [String: String] = [:]
            var index = text.startIndex
            func skipSpaces() { while index < text.endIndex, text[index].isWhitespace || text[index] == "/" { index = text.index(after: index) } }
            while index < text.endIndex {
                skipSpaces()
                var name = ""
                while index < text.endIndex, !text[index].isWhitespace, text[index] != "=", text[index] != "/" {
                    name.append(text[index])
                    index = text.index(after: index)
                }
                skipSpaces()
                var value = ""
                if index < text.endIndex, text[index] == "=" {
                    index = text.index(after: index)
                    skipSpaces()
                    if index < text.endIndex, text[index] == "\"" || text[index] == "'" {
                        let q = text[index]
                        index = text.index(after: index)
                        while index < text.endIndex, text[index] != q {
                            value.append(text[index])
                            index = text.index(after: index)
                        }
                        if index < text.endIndex { index = text.index(after: index) }
                    } else {
                        while index < text.endIndex, !text[index].isWhitespace {
                            value.append(text[index])
                            index = text.index(after: index)
                        }
                    }
                }
                if !name.isEmpty { result[name.lowercased()] = HTMLAttributedConverter.decodeEntities(value) }
            }
            return result
        }

        mutating func handle(_ tag: Tag) {
            let name = tag.name
            if name == "br" {
                forcedBreaks += 1
                return
            }
            let opening = !tag.isClosing
            switch name {
            case "b", "strong": bold = max(0, bold + (opening ? 1 : -1))
            case "i", "em", "cite": italic = max(0, italic + (opening ? 1 : -1))
            case "u", "ins": underline = max(0, underline + (opening ? 1 : -1))
            case "a":
                if opening {
                    links.append(Self.safeLink(tag.attributes["href"]))
                } else if !links.isEmpty {
                    links.removeLast()
                }
            case "h1", "h2", "h3":
                if opening { headings.append(Int(name.dropFirst()) ?? 3) } else if !headings.isEmpty { headings.removeLast() }
                bold = max(0, bold + (opening ? 1 : -1))
            case "h4", "h5", "h6":
                bold = max(0, bold + (opening ? 1 : -1))
            case "blockquote":
                quoteDepth = max(0, quoteDepth + (opening ? 1 : -1))
                italic = max(0, italic + (opening ? 1 : -1))
            case "pre":
                preDepth = max(0, preDepth + (opening ? 1 : -1))
            case "ul", "ol":
                if opening {
                    pendingBreak = max(pendingBreak, lists.isEmpty ? 2 : 1)
                    lists.append(ListContext(ordered: name == "ol"))
                } else if !lists.isEmpty {
                    lists.removeLast()
                    pendingBreak = max(pendingBreak, lists.isEmpty ? 2 : 1)
                }
                return
            case "li":
                if opening, !lists.isEmpty {
                    lists[lists.count - 1].counter += 1
                    let context = lists[lists.count - 1]
                    pendingMarker = context.ordered ? "\(context.counter). " : "\u{2022} "
                }
            default: break
            }
            if HTMLAttributedConverter.doubleBreakElements.contains(name) {
                pendingBreak = max(pendingBreak, 2)
            } else if HTMLAttributedConverter.singleBreakElements.contains(name) {
                pendingBreak = max(pendingBreak, 1)
            }
            if name == "li", !opening { pendingMarker = nil }
        }

        static func safeLink(_ href: String?) -> URL? {
            guard let href, let url = URL(string: href.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil else { return nil }
            return url
        }

        var attributes: AttributeContainer {
            var container = AttributeContainer()
            var intent: InlinePresentationIntent = []
            if bold > 0 { intent.insert(.stronglyEmphasized) }
            if italic > 0 { intent.insert(.emphasized) }
            if !intent.isEmpty { container.inlinePresentationIntent = intent }
            if underline > 0 { container[HTMLUnderlineKey.self] = true }
            if let level = headings.last { container[HTMLHeadingLevelKey.self] = level }
            if let link = links.last(where: { $0 != nil }) ?? nil { container.link = link }
            return container
        }

        mutating func append(text raw: String, plain: Bool) {
            var text = HTMLAttributedConverter.decodeEntities(raw)
            if plain || preDepth > 0 {
                if plain { forcedBreaks = 0 }
            } else {
                text = Self.collapseWhitespace(text)
            }
            if plain {
                let lines = text.components(separatedBy: "\n")
                for (offset, line) in lines.enumerated() {
                    if offset > 0 { forcedBreaks += 1 }
                    if !line.isEmpty { emit(line, trim: false) }
                }
                return
            }
            emit(text, trim: preDepth == 0)
        }

        static func collapseWhitespace(_ text: String) -> String {
            var result = ""
            var lastSpace = false
            for char in text {
                if char.isWhitespace && char != "\u{00A0}" {
                    if !lastSpace { result.append(" ") }
                    lastSpace = true
                } else {
                    result.append(char)
                    lastSpace = false
                }
            }
            return result
        }

        mutating func emit(_ rawText: String, trim: Bool) {
            var text = rawText
            let lines = max(pendingBreak, forcedBreaks)
            let atStart = output.characters.isEmpty
            let startsLine = lines > 0 || atStart || !lineHasText
            if trim, startsLine || output.characters.last == " " || output.characters.last == "\n" {
                while text.first == " " { text.removeFirst() }
            }
            guard !text.isEmpty, !(trim && text.allSatisfy { $0 == " " } && startsLine) else { return }
            if lines > 0, !atStart {
                if output.characters.last == " " { output.characters.removeLast() }
                output.append(AttributedString(String(repeating: "\n", count: lines)))
                lineHasText = false
            }
            pendingBreak = 0
            forcedBreaks = 0
            if !lineHasText {
                var prefix = String(repeating: "    ", count: quoteDepth)
                if lists.count > 1 { prefix += String(repeating: "    ", count: lists.count - 1) }
                if let marker = pendingMarker {
                    prefix += marker
                    pendingMarker = nil
                } else if !lists.isEmpty, lines == 1 || lines == 0 {
                    prefix += "  "
                }
                if !prefix.isEmpty { output.append(AttributedString(prefix)) }
            }
            output.append(AttributedString(text, attributes: attributes))
            lineHasText = true
        }

        mutating func finish() -> AttributedString {
            while output.characters.last == " " || output.characters.last == "\n" { output.characters.removeLast() }
            return output
        }
    }
}
