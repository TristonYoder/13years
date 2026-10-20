// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct SkeletonLoaderView: View {
    public enum Layout {
        case producer
        case pager
    }

    private let ink: Color
    private let layout: Layout

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PagerLayoutChoice.storageKey) private var layoutRaw: String = PagerLayoutChoice.defaultChoice.rawValue

    public init(ink: Color, layout: Layout = .producer) {
        self.ink = ink
        self.layout = layout
    }

    private static let sweepPeriod: TimeInterval = 1.6

    public var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas(rendersAsynchronously: false) { context, size in
                draw(in: &context, size: size, phase: reduceMotion ? 0.5 : Self.phase(at: timeline.date))
            }
        }
        .accessibilityHidden(true)
    }

    private static func phase(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        return t.truncatingRemainder(dividingBy: sweepPeriod) / sweepPeriod
    }

    private enum Metrics {
        static let headerHeight: CGFloat = 136
        static let sidebarWidth: CGFloat = 210
        static let sidebarRowHeight: CGFloat = 32
        static let sectionHeaderHeight: CGFloat = 54
        static let roleCardMinWidth: CGFloat = 240
        static let roleCardSpacing: CGFloat = 12
        static let roleCardHeight: CGFloat = 84
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, phase: Double) {
        let band = max(size.width * 0.55, 320)
        let travel = size.width + band * 2
        let center = -band + travel * phase
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                .init(color: ink.opacity(0.06), location: 0.00),
                .init(color: ink.opacity(0.068), location: 0.22),
                .init(color: ink.opacity(0.105), location: 0.38),
                .init(color: ink.opacity(0.140), location: 0.50),
                .init(color: ink.opacity(0.105), location: 0.62),
                .init(color: ink.opacity(0.068), location: 0.78),
                .init(color: ink.opacity(0.06), location: 1.00),
            ]),
            startPoint: CGPoint(x: center - band / 2, y: 0),
            endPoint: CGPoint(x: center + band / 2, y: 0)
        )

        switch layout {
        case .producer: drawProducer(in: &context, size: size, shading: shading)
        case .pager: drawPager(in: &context, size: size, shading: shading)
        }
    }

    private enum PagerVariant {
        case portrait
        case landscape
        case lowerThird
    }

    private func pagerVariant(for size: CGSize) -> PagerVariant {
        #if os(tvOS)
        return .landscape
        #else
        switch PagerLayoutChoice.resolve(layoutRaw).layout(for: size) {
        case .lowerThird: return .lowerThird
        case .landscape: return .landscape
        case .portrait: return .portrait
        }
        #endif
    }

    private func drawPager(in context: inout GraphicsContext, size: CGSize, shading: GraphicsContext.Shading) {
        func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat? = nil) {
            guard w > 0, h > 0 else { return }
            context.fill(
                Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: radius ?? min(h / 2, 6)),
                with: shading
            )
        }

        func card(_ rect: CGRect, radius: CGFloat) {
            guard rect.width > 0, rect.height > 0 else { return }
            context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(ink.opacity(0.05)))
        }

        func chrome(_ sizes: PagerChromeSizes, x: CGFloat, y: CGFloat, width: CGFloat) {
            bar(x, y + sizes.timeFont * 0.1, sizes.slotWidth * 0.78, sizes.timeFont * 0.78, radius: sizes.timeFont * 0.2)
            bar(x, y + sizes.timeFont * 1.05, sizes.slotWidth * 0.32, sizes.timeCaptionFont * 0.8)
            let roleWidth = min(sizes.roleFont * 6, width * 0.25)
            bar(x + width - roleWidth, y + sizes.roleFont * 0.2, roleWidth, sizes.roleFont * 0.8)
            let icon = PagerChromeSizes.iconRowHeight * 0.62
            let iconY = y + sizes.roleFont * 1.6 + sizes.margin * 0.2 + (PagerChromeSizes.iconRowHeight - icon) / 2
            for i in 0 ..< 2 {
                bar(x + width - icon - CGFloat(i) * (icon + sizes.margin * 0.6), iconY, icon, icon, radius: icon / 2)
            }
        }

        let w = size.width, h = size.height

        switch pagerVariant(for: size) {
        case .portrait:
            let m = PortraitMetrics(size: size)
            let left = m.inset, inner = w - 2 * m.inset
            chrome(m.chrome, x: left, y: m.inset, width: inner)

            let bottomHeight = min(m.nextCardMaxHeight * 0.7, max(0, h * 0.2))
            let bottomTop = m.bottomEdge - bottomHeight
            card(CGRect(x: left, y: bottomTop, width: inner, height: bottomHeight), radius: m.cornerRadius)
            bar(left + m.cardPadding, bottomTop + m.cardPadding, inner * 0.38, m.nextTitleFontSize * 0.8)
            bar(left + inner - m.cardPadding - inner * 0.16, bottomTop + m.cardPadding, inner * 0.16, m.nextTitleFontSize * 0.8)
            bar(left + m.cardPadding, bottomTop + m.cardPadding * 2 + m.nextTitleFontSize, inner * 0.7, m.noteFontSize * 0.75)

            let centreY = m.currentCardCentreY(bottomStackHeight: bottomHeight)
            let countdownHeight = m.countdownFontSize * 0.74
            let noteHeight = m.noteFontSize * 0.75
            let total = m.titleFontSize + countdownHeight + m.tagFontSize + noteHeight * 2 + m.margin * 2.4
            var y = centreY - total / 2
            bar(w * 0.2, y, w * 0.6, m.titleFontSize * 0.75, radius: m.cornerRadius * 0.4)
            y += m.titleFontSize + m.margin * 0.3
            bar(w * 0.14, y, w * 0.72, countdownHeight, radius: m.cornerRadius)
            y += countdownHeight + m.margin * 0.3
            bar(w * 0.4, y, w * 0.2, m.tagFontSize * 0.75)
            y += m.tagFontSize + m.margin * 0.7
            bar(left, y, inner * 0.8, noteHeight)
            y += noteHeight + m.margin * 0.4
            bar(left, y, inner * 0.55, noteHeight)

        case .landscape:
            let m = LandscapeMetrics(size: size)
            let left = m.frameThickness + m.margin
            let inner = w - 2 * left
            chrome(m.chrome, x: left, y: left, width: inner)

            let countdownHeight = m.countdownFontSize * 0.74
            let total = m.titleFontSize + countdownHeight + m.tagFontSize + m.margin * 0.6
            var y = h / 2 - total / 2
            bar(w * 0.33, y, w * 0.34, m.titleFontSize * 0.75, radius: m.cornerRadius * 0.4)
            y += m.titleFontSize + m.margin * 0.2
            bar(w * 0.24, y, w * 0.52, countdownHeight, radius: m.cornerRadius)
            y += countdownHeight + m.margin * 0.2
            bar(w * 0.45, y, w * 0.1, m.tagFontSize * 0.75)

            let cardHeight = m.cardMaxHeight * 0.8
            let cardTop = m.bottomRowBottom - cardHeight
            guard cardTop > y + m.tagFontSize else { return }
            for i in 0 ..< 2 {
                let cx = left + CGFloat(i) * (m.cardWidth + m.margin)
                card(CGRect(x: cx, y: cardTop, width: m.cardWidth, height: cardHeight), radius: m.cornerRadius)
                bar(cx + m.cardPadding, cardTop + m.cardPadding, m.cardWidth * 0.3, m.captionFontSize * 0.8)
                bar(cx + m.cardPadding, cardTop + m.cardPadding * 1.6 + m.captionFontSize, m.cardWidth * 0.75, m.noteFontSize * 0.75)
                bar(cx + m.cardPadding, cardTop + m.cardPadding * 1.6 + m.captionFontSize + m.noteFontSize * 1.2, m.cardWidth * 0.5, m.noteFontSize * 0.75)
            }

        case .lowerThird:
            let m = LowerThirdMetrics(size: size)
            let left = m.inset, right = w - m.inset
            let capHeight = m.fontSize * 0.74
            let blockHeight = capHeight + m.tagFontSize * 1.3 + m.tagFontSize
            let top = h / 2 - blockHeight / 2
            let clockWidth = min(m.fontSize * 4.4, (right - left) * 0.3)
            bar(left, top, clockWidth, capHeight, radius: m.cornerRadius)
            bar(left, top + capHeight + m.tagFontSize * 0.5, clockWidth * 0.4, m.tagFontSize * 0.8)

            let countdownWidth = min(m.fontSize * 2.8, (right - left) * 0.2)
            bar(right - countdownWidth, top, countdownWidth, capHeight, radius: m.cornerRadius)
            bar(right - countdownWidth * 0.55, top + capHeight + m.tagFontSize * 0.5, countdownWidth * 0.55, m.tagFontSize * 0.8)

            let pillX = left + clockWidth + m.gap + m.fontSize * 0.4
            let pillWidth = right - countdownWidth - m.gap - m.fontSize * 0.4 - pillX
            let pillHeight = m.fontSize * 0.6 * 0.74 + m.fontSize * 0.24
            card(CGRect(x: pillX, y: h / 2 - pillHeight / 2, width: pillWidth, height: pillHeight), radius: m.cornerRadius)
            bar(pillX + pillWidth * 0.2, h / 2 - m.fontSize * 0.2, pillWidth * 0.6, m.fontSize * 0.4)
        }
    }

    private func drawProducer(in context: inout GraphicsContext, size: CGSize, shading: GraphicsContext.Shading) {
        func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat? = nil) {
            guard w > 0, h > 0 else { return }
            context.fill(
                Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: radius ?? min(h / 2, 6)),
                with: shading
            )
        }

        func rule(_ y: CGFloat, from x0: CGFloat, to x1: CGFloat) {
            context.fill(
                Path(CGRect(x: x0, y: y, width: x1 - x0, height: 1)),
                with: .color(ink.opacity(0.10))
            )
        }

        bar(16, 16, 210, 8)
        bar(16, 30, 158, 8)
        bar(size.width / 2 - 55, 50, 110, 8)
        bar(size.width / 2 - 95, 64, 190, 14)
        bar(24, 92, 68, 8)
        bar(24, 106, 120, 20, radius: 5)
        bar(size.width - 24 - 160, 96, 160, 24, radius: 6)

        rule(Metrics.headerHeight, from: 0, to: size.width)

        #if os(macOS)
        let usesTabs = false
        #else
        let usesTabs = size.height > size.width || size.width < 640
        #endif

        let tabBarHeight: CGFloat = usesTabs ? 56 : 0
        let detailX: CGFloat = usesTabs ? 0 : Metrics.sidebarWidth
        let bodyBottom = size.height - tabBarHeight

        if usesTabs {
            rule(bodyBottom, from: 0, to: size.width)
            let tabWidth = size.width / 4
            for i in 0 ..< 4 {
                let cx = tabWidth * (CGFloat(i) + 0.5)
                bar(cx - 9, bodyBottom + 10, 18, 18, radius: 5)
                bar(cx - 20, bodyBottom + 34, 40, 7)
            }
        } else {
            let sidebarLabelWidths: [CGFloat] = [64, 96, 84, 72]
            for (i, labelWidth) in sidebarLabelWidths.enumerated() {
                let y = Metrics.headerHeight + 14 + CGFloat(i) * Metrics.sidebarRowHeight
                bar(18, y + 8, 15, 15, radius: 4)
                bar(44, y + 11, labelWidth, 9)
            }
            context.fill(
                Path(CGRect(x: detailX, y: Metrics.headerHeight, width: 1, height: size.height - Metrics.headerHeight)),
                with: .color(ink.opacity(0.10))
            )
        }

        let previewPaneWidth: CGFloat = 380
        let showsPreview = size.width - detailX - previewPaneWidth >= 420
        let gridRight = size.width - (showsPreview ? previewPaneWidth : 0)

        let contentX = detailX + 16
        let contentWidth = gridRight - contentX - 16
        guard contentWidth > 40 else { return }

        bar(contentX, Metrics.headerHeight + 18, 18, 18, radius: 5)
        bar(contentX + 28, Metrics.headerHeight + 19, 100, 16, radius: 4)
        bar(size.width - (showsPreview ? previewPaneWidth : 0) - 16 - 96, Metrics.headerHeight + 15, 96, 24, radius: 6)
        bar(size.width - (showsPreview ? previewPaneWidth : 0) - 16 - 96 - 12 - 120, Metrics.headerHeight + 15, 120, 24, radius: 6)
        rule(Metrics.headerHeight + Metrics.sectionHeaderHeight, from: detailX, to: size.width)

        if showsPreview {
            let paneLeft = size.width - previewPaneWidth
            let phoneHeight = min(660, bodyBottom - Metrics.headerHeight - Metrics.sectionHeaderHeight - 48)
            if phoneHeight > 120 {
                let phoneWidth = phoneHeight * 320 / 660
                let phone = CGRect(
                    x: paneLeft + (previewPaneWidth - phoneWidth) / 2,
                    y: Metrics.headerHeight + Metrics.sectionHeaderHeight + 24,
                    width: phoneWidth,
                    height: phoneHeight
                )
                context.fill(Path(roundedRect: phone, cornerRadius: 44 * phoneHeight / 660), with: .color(ink.opacity(0.05)))
                context.stroke(
                    Path(roundedRect: phone, cornerRadius: 44 * phoneHeight / 660),
                    with: .color(ink.opacity(0.14)),
                    lineWidth: 5
                )
                bar(phone.minX + phoneWidth * 0.15, phone.minY + phoneHeight * 0.3, phoneWidth * 0.7, phoneHeight * 0.1, radius: 8)
                bar(phone.minX + phoneWidth * 0.3, phone.minY + phoneHeight * 0.45, phoneWidth * 0.4, phoneHeight * 0.04)
            }
        }

        var y = Metrics.headerHeight + Metrics.sectionHeaderHeight + 20

        bar(contentX, y, 70, 14)
        bar(contentX + contentWidth - 64, y - 2, 64, 18, radius: 5)
        y += 34

        let columns = max(1, Int((contentWidth + Metrics.roleCardSpacing)
            / (Metrics.roleCardMinWidth + Metrics.roleCardSpacing)))
        let cardWidth = (contentWidth - CGFloat(columns - 1) * Metrics.roleCardSpacing) / CGFloat(columns)
        let rows = max(2, Int((bodyBottom - y) / (Metrics.roleCardHeight + Metrics.roleCardSpacing)))
        for index in 0 ..< (columns * rows) {
            let cx = contentX + CGFloat(index % columns) * (cardWidth + Metrics.roleCardSpacing)
            let cy = y + CGFloat(index / columns) * (Metrics.roleCardHeight + Metrics.roleCardSpacing)
            guard cy + Metrics.roleCardHeight < bodyBottom else { break }
            context.fill(
                Path(roundedRect: CGRect(x: cx, y: cy, width: cardWidth, height: Metrics.roleCardHeight), cornerRadius: 10),
                with: .color(ink.opacity(0.05))
            )
            bar(cx + 12, cy + 14, 16, 16, radius: 8)
            bar(cx + 38, cy + 14, min(cardWidth - 120, 96), 10)
            bar(cx + 38, cy + 30, min(cardWidth - 140, 60), 7)
            bar(cx + cardWidth - 12 - 22, cy + 14, 22, 22, radius: 6)
            bar(cx + cardWidth - 12 - 22 - 8 - 22, cy + 14, 22, 22, radius: 6)
            let offWidth: CGFloat = 40
            let buttonWidth = (cardWidth - 24 - 16 - offWidth) / 2
            bar(cx + 12, cy + 50, buttonWidth, 22, radius: 6)
            bar(cx + 12 + buttonWidth + 8, cy + 50, buttonWidth, 22, radius: 6)
            bar(cx + cardWidth - 12 - offWidth, cy + 50, offWidth, 22, radius: 6)
        }
    }
}
