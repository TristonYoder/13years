// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS) || os(iOS) || os(tvOS)
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension HTMLColor {
    init?(_ color: Color) {
        #if os(macOS)
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(
            red: Double(converted.redComponent),
            green: Double(converted.greenComponent),
            blue: Double(converted.blueComponent),
            alpha: Double(converted.alphaComponent)
        )
        #else
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        self.init(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha))
        #endif
    }
}

struct HTMLRichText: View {
    let html: String
    let baseSize: CGFloat
    let ground: HTMLColor
    var isSelectable = true

    @State private var rendered: AttributedString

    static let minimumContrast = 2.5

    init(html: String, baseSize: CGFloat, ground: HTMLColor, isSelectable: Bool = true) {
        self.html = html
        self.baseSize = baseSize
        self.ground = ground
        self.isSelectable = isSelectable
        _rendered = State(initialValue: HTMLAttributedConverter.attributedString(fromHTML: html))
    }

    var body: some View {
        content
            .font(.system(size: baseSize))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: html) { rendered = HTMLAttributedConverter.attributedString(fromHTML: html) }
    }

    @ViewBuilder
    private var content: some View {
        #if os(tvOS)
        Text(Self.styled(rendered, baseSize: baseSize, ground: ground))
        #else
        if isSelectable {
            Text(Self.styled(rendered, baseSize: baseSize, ground: ground)).textSelection(.enabled)
        } else {
            Text(Self.styled(rendered, baseSize: baseSize, ground: ground))
        }
        #endif
    }

    private static func color(_ value: HTMLColor) -> Color {
        Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }

    static func styled(_ source: AttributedString, baseSize size: CGFloat, ground pageColor: HTMLColor) -> AttributedString {
        var text = source
        for run in text.runs {
            let range = run.range
            let background = run[HTMLBackgroundColorKey.self].flatMap(HTMLColor.init(css:))
            if let background {
                text[range].backgroundColor = color(background)
            }
            let ground = background.map { $0.alpha >= 0.5 ? $0 : pageColor } ?? pageColor
            if let foreground = run[HTMLForegroundColorKey.self].flatMap(HTMLColor.init(css:)),
               HTMLColor.contrast(foreground, ground) >= minimumContrast {
                text[range].foregroundColor = color(foreground)
            } else if background != nil {
                text[range].foregroundColor = ground.luminance > 0.4 ? .black : .white
            }
            if run[HTMLUnderlineKey.self] == true {
                text[range].underlineStyle = .single
            }
            if run[HTMLStrikethroughKey.self] == true {
                text[range].strikethroughStyle = .single
            }
            var runSize = size * CGFloat(run[HTMLFontScaleKey.self] ?? 1)
            var weight: Font.Weight?
            if let level = run[HTMLHeadingLevelKey.self] {
                let factors: [Int: CGFloat] = [1: 1.5, 2: 1.3, 3: 1.15, 4: 1.05, 5: 1, 6: 0.9]
                runSize *= factors[level] ?? 1
                weight = .bold
            }
            if let baseline = run[HTMLBaselineKey.self] {
                text[range].baselineOffset = CGFloat(baseline) * runSize * 0.35
            }
            let intent = run.inlinePresentationIntent ?? []
            let resolvedWeight = weight ?? (intent.contains(.stronglyEmphasized) ? .bold : nil)
            let needsFont = runSize != size || weight != nil || run[HTMLMonospaceKey.self] == true
            if needsFont {
                var font: Font = run[HTMLMonospaceKey.self] == true
                    ? .system(size: runSize, design: .monospaced)
                    : .system(size: runSize)
                if let resolvedWeight { font = font.weight(resolvedWeight) }
                if intent.contains(.emphasized) { font = font.italic() }
                text[range].font = font
            }
        }
        return text
    }
}
#endif
