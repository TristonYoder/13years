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

public enum HTMLForegroundColorKey: AttributedStringKey {
    public typealias Value = String
    public static let name = "htmlForegroundColor"
}

public enum HTMLBackgroundColorKey: AttributedStringKey {
    public typealias Value = String
    public static let name = "htmlBackgroundColor"
}

public enum HTMLStrikethroughKey: AttributedStringKey {
    public typealias Value = Bool
    public static let name = "htmlStrikethrough"
}

public enum HTMLFontScaleKey: AttributedStringKey {
    public typealias Value = Double
    public static let name = "htmlFontScale"
}

public enum HTMLMonospaceKey: AttributedStringKey {
    public typealias Value = Bool
    public static let name = "htmlMonospace"
}

public enum HTMLBaselineKey: AttributedStringKey {
    public typealias Value = Int
    public static let name = "htmlBaseline"
}

public struct HTMLColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public var hex: String {
        func byte(_ value: Double) -> String { String(format: "%02X", Int((min(max(value, 0), 1) * 255).rounded())) }
        return "#" + byte(red) + byte(green) + byte(blue) + byte(alpha)
    }

    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public static func contrast(_ a: HTMLColor, _ b: HTMLColor) -> Double {
        let (hi, lo) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (hi + 0.05) / (lo + 0.05)
    }

    static let named: [String: String] = [
        "black": "000000", "white": "FFFFFF", "red": "FF0000", "green": "008000", "blue": "0000FF",
        "yellow": "FFFF00", "orange": "FFA500", "purple": "800080", "gray": "808080", "grey": "808080",
        "silver": "C0C0C0", "maroon": "800000", "olive": "808000", "lime": "00FF00", "aqua": "00FFFF",
        "cyan": "00FFFF", "teal": "008080", "navy": "000080", "fuchsia": "FF00FF", "magenta": "FF00FF",
        "pink": "FFC0CB", "brown": "A52A2A", "gold": "FFD700", "darkred": "8B0000", "darkgreen": "006400",
        "darkblue": "00008B", "lightgray": "D3D3D3", "lightgrey": "D3D3D3", "darkgray": "A9A9A9", "darkgrey": "A9A9A9",
        "indigo": "4B0082", "violet": "EE82EE", "coral": "FF7F50", "tomato": "FF6347", "crimson": "DC143C",
    ]

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init?(css raw: String) {
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("#") {
            var digits = String(text.dropFirst())
            if digits.count == 3 || digits.count == 4 { digits = digits.map { "\($0)\($0)" }.joined() }
            guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
            let hasAlpha = digits.count == 8
            let shift: UInt64 = hasAlpha ? 8 : 0
            self.init(
                red: Double((value >> (16 + shift)) & 0xFF) / 255,
                green: Double((value >> (8 + shift)) & 0xFF) / 255,
                blue: Double((value >> shift) & 0xFF) / 255,
                alpha: hasAlpha ? Double(value & 0xFF) / 255 : 1
            )
        } else if text.hasPrefix("rgb") {
            guard let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")"), open < close else { return nil }
            let parts = text[text.index(after: open)..<close]
                .replacingOccurrences(of: "/", with: ",")
                .split(whereSeparator: { $0 == "," || $0 == " " })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard parts.count >= 3 else { return nil }
            func channel(_ part: String) -> Double? {
                if part.hasSuffix("%") { return Double(part.dropLast()).map { $0 / 100 } }
                return Double(part).map { $0 / 255 }
            }
            func alphaValue(_ part: String) -> Double? {
                if part.hasSuffix("%") { return Double(part.dropLast()).map { $0 / 100 } }
                return Double(part)
            }
            guard let r = channel(parts[0]), let g = channel(parts[1]), let b = channel(parts[2]) else { return nil }
            self.init(red: r, green: g, blue: b, alpha: parts.count > 3 ? (alphaValue(parts[3]) ?? 1) : 1)
        } else if let hex = Self.named[text] {
            self.init(css: "#" + hex)
        } else {
            return nil
        }
    }
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
    private static let doubleBreakElements: Set<String> = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "ul", "ol", "pre", "table", "hr"]
    private static let voidElements: Set<String> = ["br", "hr", "img", "input", "meta", "link", "col", "wbr"]
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

    private struct StyleFrame {
        var tag: String
        var color: String?
        var background: String?
        var bold: Bool?
        var italic: Bool?
        var underline: Bool?
        var strike: Bool?
        var scale: Double?
        var mono: Bool?
        var baseline: Int?

        var isEmpty: Bool {
            color == nil && background == nil && bold == nil && italic == nil && underline == nil
                && strike == nil && scale == nil && mono == nil && baseline == nil
        }
    }

    static func fontScale(css value: String) -> Double? {
        let text = value.trimmingCharacters(in: .whitespaces).lowercased()
        let keywords: [String: Double] = [
            "xx-small": 0.6, "x-small": 0.75, "small": 0.85, "medium": 1, "large": 1.2, "x-large": 1.5, "xx-large": 2,
            "smaller": 0.85, "larger": 1.2,
        ]
        if let keyword = keywords[text] { return keyword }
        func number(_ suffix: String) -> Double? { text.hasSuffix(suffix) ? Double(text.dropLast(suffix.count)) : nil }
        let scale: Double?
        if let px = number("px") { scale = px / 13 }
        else if let pt = number("pt") { scale = pt * 4 / 3 / 13 }
        else if let rem = number("rem") { scale = rem * 16 / 13 }
        else if let em = number("em") { scale = em }
        else if let percent = number("%") { scale = percent / 100 }
        else { scale = nil }
        return scale.map { min(max($0, 0.5), 3) }
    }

    private static func frame(for tag: Tag) -> StyleFrame {
        var frame = StyleFrame(tag: tag.name)
        switch tag.name {
        case "s", "strike", "del": frame.strike = true
        case "mark": frame.background = HTMLColor(red: 1, green: 0.96, blue: 0.62).hex
        case "code", "kbd", "samp", "tt": frame.mono = true
        case "sub": frame.baseline = -1; frame.scale = 0.8
        case "sup": frame.baseline = 1; frame.scale = 0.8
        case "small": frame.scale = 0.85
        case "big": frame.scale = 1.2
        case "th": frame.bold = true
        case "font":
            if let color = tag.attributes["color"].flatMap(HTMLColor.init(css:)) { frame.color = color.hex }
            if let size = tag.attributes["size"].flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) {
                let sizes: [Int: Double] = [1: 0.7, 2: 0.85, 3: 1, 4: 1.15, 5: 1.3, 6: 1.6, 7: 2]
                frame.scale = sizes[min(max(size, 1), 7)]
            }
            if let face = tag.attributes["face"]?.lowercased(), face.contains("mono") || face.contains("courier") { frame.mono = true }
        default: break
        }
        if let style = tag.attributes["style"] { apply(css: style, to: &frame) }
        return frame
    }

    private static func apply(css: String, to frame: inout StyleFrame) {
        for declaration in css.split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let property = parts[0].lowercased()
            let value = parts[1].replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespaces)
            let lower = value.lowercased()
            switch property {
            case "color":
                if let color = HTMLColor(css: value) { frame.color = color.hex }
            case "background-color", "background":
                if let color = HTMLColor(css: value), color.alpha > 0 { frame.background = color.hex }
            case "font-weight":
                if lower == "bold" || lower == "bolder" || (Int(lower) ?? 0) >= 600 { frame.bold = true }
                else if lower == "normal" || lower == "lighter" || (Int(lower).map { $0 < 600 } ?? false) { frame.bold = false }
            case "font-style":
                frame.italic = lower.contains("italic") || lower.contains("oblique")
            case "text-decoration", "text-decoration-line":
                if lower.contains("underline") { frame.underline = true }
                if lower.contains("line-through") { frame.strike = true }
                if lower == "none" { frame.underline = false; frame.strike = false }
            case "font-size":
                if let scale = fontScale(css: value) { frame.scale = scale }
            case "font-family":
                if lower.contains("mono") || lower.contains("courier") || lower.contains("consolas") { frame.mono = true }
            case "vertical-align":
                if lower == "super" { frame.baseline = 1; frame.scale = frame.scale ?? 0.8 }
                if lower == "sub" { frame.baseline = -1; frame.scale = frame.scale ?? 0.8 }
            default: break
            }
        }
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
        var styles: [StyleFrame] = []

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
            if name == "hr" {
                pendingBreak = max(pendingBreak, 2)
                var rule = StyleFrame(tag: "hr")
                rule.color = HTMLColor(red: 0.6, green: 0.6, blue: 0.6).hex
                styles.append(rule)
                emit(String(repeating: "\u{2500}", count: 24), trim: false)
                styles.removeLast()
                pendingBreak = max(pendingBreak, 2)
                return
            }
            let opening = !tag.isClosing
            if opening, !tag.isSelfClosing, !HTMLAttributedConverter.voidElements.contains(name) {
                let frame = HTMLAttributedConverter.frame(for: tag)
                if !frame.isEmpty { styles.append(frame) }
            } else if tag.isClosing, let index = styles.lastIndex(where: { $0.tag == name }) {
                styles.remove(at: index)
            }
            if tag.isClosing, name == "td" || name == "th" {
                if lineHasText { output.append(AttributedString("   ")) }
            }
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
                if opening { headings.append(Int(name.dropFirst()) ?? 4) } else if !headings.isEmpty { headings.removeLast() }
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
            var isBold = bold > 0
            var isItalic = italic > 0
            var isUnderlined = underline > 0
            var isStruck = false
            var color: String?
            var background: String?
            var scale = 1.0
            var mono = false
            var baseline: Int?
            for frame in styles {
                if let value = frame.bold { isBold = value }
                if let value = frame.italic { isItalic = value }
                if let value = frame.underline { isUnderlined = value }
                if let value = frame.strike { isStruck = value }
                if let value = frame.color { color = value }
                if let value = frame.background { background = value }
                if let value = frame.scale { scale *= value }
                if frame.mono == true { mono = true }
                if let value = frame.baseline { baseline = value }
            }
            #if !os(Linux)
            var intent: InlinePresentationIntent = []
            if isBold { intent.insert(.stronglyEmphasized) }
            if isItalic { intent.insert(.emphasized) }
            if !intent.isEmpty { container.inlinePresentationIntent = intent }
            #endif
            if isUnderlined { container[HTMLUnderlineKey.self] = true }
            if isStruck { container[HTMLStrikethroughKey.self] = true }
            if let color { container[HTMLForegroundColorKey.self] = color }
            if let background { container[HTMLBackgroundColorKey.self] = background }
            if abs(scale - 1) > 0.01 { container[HTMLFontScaleKey.self] = scale }
            if mono { container[HTMLMonospaceKey.self] = true }
            if let baseline { container[HTMLBaselineKey.self] = baseline }
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
