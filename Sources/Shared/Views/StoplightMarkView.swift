// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import CoreText
import SwiftUI

public struct StoplightMarkView: View {
    private let palette: Palette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(palette: Palette) {
        self.palette = palette
    }

    public var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas(rendersAsynchronously: false) { context, size in
                draw(in: &context, size: size, time: reduceMotion ? 0 : Self.phase(at: timeline.date))
            }
        }
        .accessibilityLabel("13 Years")
        .aspectRatio(Geometry.content.width / Geometry.content.height, contentMode: .fit)
    }

    public struct Palette: Equatable, Sendable {
        public var ink: Color
        public var red: Color
        public var yellow: Color
        public var green: Color

        public static let dark = Palette(
            ink: Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF3 / 255),
            red: Color(red: 0xFF / 255, green: 0x52 / 255, blue: 0x52 / 255),
            yellow: Color(red: 0xFF / 255, green: 0xEB / 255, blue: 0x3B / 255),
            green: Color(red: 0x66 / 255, green: 0xBB / 255, blue: 0x6A / 255)
        )

        public static let light = Palette(
            ink: Color(red: 0x33 / 255, green: 0x33 / 255, blue: 0x33 / 255),
            red: Color(red: 0xDC / 255, green: 0x14 / 255, blue: 0x3C / 255),
            yellow: Color(red: 0xFF / 255, green: 0xD7 / 255, blue: 0x00 / 255),
            green: Color(red: 0x22 / 255, green: 0x8B / 255, blue: 0x22 / 255)
        )

        public static func matching(_ scheme: ColorScheme) -> Palette {
            scheme == .dark ? .dark : .light
        }
    }

    private enum Geometry {
        static let housing = CGRect(x: 20, y: 15, width: 60, height: 170)

        static let lampX: CGFloat = 50
        static let lampRadius: CGFloat = 18
        static let lampY: [CGFloat] = [50, 100, 150]

        static let threeFontSize: CGFloat = 220
        static let threeStrokeWidth: CGFloat = 12

        static let threeBaseline = CGPoint(x: 90, y: 176.56)

        static let content = CGRect(x: 2, y: 15, width: 218.96, height: 170.64)

        static let cycle: TimeInterval = 6
    }

    private struct Lamp {
        let color: KeyPath<Palette, Color>
        let baseY: CGFloat
        let track: [(p: Double, x: CGFloat, y: CGFloat)]
    }

    private static let lamps: [Lamp] = [
        Lamp(color: \.red, baseY: Geometry.lampY[0], track: [
            (0.00, 0, 0), (0.16, 0, 50), (0.33, 0, 100), (0.41, -30, 50),
            (0.50, 0, 0), (0.66, 0, 50), (0.83, 0, 100), (0.91, 30, 50),
            (1.00, 0, 0),
        ]),
        Lamp(color: \.yellow, baseY: Geometry.lampY[1], track: [
            (0.00, 0, 0), (0.16, 0, 50), (0.24, -30, -25), (0.33, 0, -50),
            (0.50, 0, 0), (0.66, 0, 50), (0.74, 30, -25), (0.83, 0, -50),
            (1.00, 0, 0),
        ]),
        Lamp(color: \.green, baseY: Geometry.lampY[2], track: [
            (0.00, 0, 0), (0.08, -30, -50), (0.16, 0, -100), (0.33, 0, -50),
            (0.50, 0, 0), (0.58, 30, -50), (0.66, 0, -100), (0.83, 0, -50),
            (1.00, 0, 0),
        ]),
    ]

    private static func phase(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        return t.truncatingRemainder(dividingBy: Geometry.cycle) / Geometry.cycle
    }

    private static func easeInOut(_ t: Double) -> Double {
        guard t > 0, t < 1 else { return min(max(t, 0), 1) }
        let (x1, x2) = (0.42, 0.58)
        func bezier(_ a: Double, _ b: Double, _ u: Double) -> Double {
            let v = 1 - u
            return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u
        }
        var lo = 0.0, hi = 1.0, u = t
        for _ in 0 ..< 24 {
            u = (lo + hi) / 2
            if bezier(x1, x2, u) < t { lo = u } else { hi = u }
        }
        return bezier(0, 1, u)
    }

    private static func offset(for lamp: Lamp, at phase: Double) -> CGPoint {
        guard let next = lamp.track.firstIndex(where: { $0.p >= phase }), next > 0 else {
            return CGPoint(x: lamp.track[0].x, y: lamp.track[0].y)
        }
        let from = lamp.track[next - 1], to = lamp.track[next]
        let span = to.p - from.p
        let eased = easeInOut(span > 0 ? (phase - from.p) / span : 1)
        return CGPoint(
            x: from.x + (to.x - from.x) * eased,
            y: from.y + (to.y - from.y) * eased
        )
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time phase: Double) {
        let scale = min(
            size.width / Geometry.content.width,
            size.height / Geometry.content.height
        )
        context.translateBy(
            x: (size.width - Geometry.content.width * scale) / 2,
            y: (size.height - Geometry.content.height * scale) / 2
        )
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -Geometry.content.minX, y: -Geometry.content.minY)

        let ink = GraphicsContext.Shading.color(palette.ink)

        context.fill(Self.threePath, with: ink)
        context.stroke(
            Self.threePath,
            with: ink,
            style: StrokeStyle(lineWidth: Geometry.threeStrokeWidth, lineJoin: .miter, miterLimit: 4)
        )
        context.fill(Path(Geometry.housing), with: ink)

        let placed = Self.lamps
            .map { (lamp: $0, offset: Self.offset(for: $0, at: phase)) }
            .sorted { abs($0.offset.x) < abs($1.offset.x) }

        for item in placed {
            let center = CGPoint(
                x: Geometry.lampX + item.offset.x,
                y: item.lamp.baseY + item.offset.y
            )
            let rect = CGRect(
                x: center.x - Geometry.lampRadius,
                y: center.y - Geometry.lampRadius,
                width: Geometry.lampRadius * 2,
                height: Geometry.lampRadius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(palette[keyPath: item.lamp.color]))
        }
    }

    private static let threePath: Path = {
        AppFonts.registerIfNeeded()

        let font = CTFontCreateWithName(
            AppFonts.spaceGroteskPostScriptName as CFString,
            Geometry.threeFontSize,
            nil
        )

        let resolved = CTFontCopyPostScriptName(font) as String
        if resolved != AppFonts.spaceGroteskPostScriptName {
            AppLog.cue.error("StoplightMarkView: Space Grotesk unavailable, fell back to \(resolved, privacy: .public) — check AppFonts registration")
        }

        var character: UniChar = 0x33
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
              let outline = CTFontCreatePathForGlyph(font, glyph, nil)
        else {
            AppLog.cue.error("StoplightMarkView: could not build a glyph path for \"3\"")
            return Path()
        }

        var transform = CGAffineTransform(
            translationX: Geometry.threeBaseline.x,
            y: Geometry.threeBaseline.y
        ).scaledBy(x: 1, y: -1)

        return Path(outline.copy(using: &transform) ?? outline)
    }()
}

#Preview("Dark") {
    StoplightMarkView(palette: .dark)
        .frame(width: 420)
        .padding(60)
        .background(Color(red: 0x10 / 255, green: 0x10 / 255, blue: 0x14 / 255))
}

#Preview("Light") {
    StoplightMarkView(palette: .light)
        .frame(width: 420)
        .padding(60)
        .background(Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF3 / 255))
}
