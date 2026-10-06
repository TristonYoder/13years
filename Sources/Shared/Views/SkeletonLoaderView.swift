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

    private func drawPager(in context: inout GraphicsContext, size: CGSize, shading: GraphicsContext.Shading) {
        func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat? = nil) {
            guard w > 0, h > 0 else { return }
            context.fill(
                Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: radius ?? min(h / 2, 6)),
                with: shading
            )
        }

        let w = size.width, h = size.height
        let margin = max(20, w * 0.055)

        bar(margin, h * 0.045, min(w * 0.34, 150), 30, radius: 8)
        let statusWidth = min(w * 0.30, 120)
        bar(w - margin - 8, h * 0.045 + 10, 8, 8, radius: 4)
        bar(w - margin - 18 - statusWidth, h * 0.045 + 11, statusWidth, 9)

        let stateHeight = min(h * 0.10, 64)
        let stateWidth = min(w - margin * 2, w * 0.68)
        bar((w - stateWidth) / 2, h * 0.36, stateWidth, stateHeight, radius: 10)
        bar((w - w * 0.36) / 2, h * 0.36 + stateHeight + 16, w * 0.36, 14)

        let timerHeight = min(h * 0.075, 48)
        let itemY = h * 0.66
        bar((w - w * 0.56) / 2, itemY, w * 0.56, 18)
        bar((w - w * 0.46) / 2, itemY + 30, w * 0.46, timerHeight, radius: 10)
        bar((w - w * 0.22) / 2, itemY + 42 + timerHeight, w * 0.22, 11)

        let noteY = itemY + 75 + timerHeight
        guard noteY + 56 < h else { return }
        context.fill(
            Path(roundedRect: CGRect(x: margin, y: noteY, width: w - margin * 2, height: 56), cornerRadius: 12),
            with: .color(ink.opacity(0.05))
        )
        bar(margin + 14, noteY + 13, min(w * 0.22, 90), 9)
        bar(margin + 14, noteY + 31, w - margin * 2 - 28 - w * 0.15, 12)
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

        let sidebarLabelWidths: [CGFloat] = [104, 84, 90, 72, 62]
        for (i, labelWidth) in sidebarLabelWidths.enumerated() {
            let y = Metrics.headerHeight + 14 + CGFloat(i) * Metrics.sidebarRowHeight
            bar(18, y + 8, 15, 15, radius: 4)
            bar(44, y + 11, labelWidth, 9)
        }

        let detailX = Metrics.sidebarWidth
        context.fill(
            Path(CGRect(x: detailX, y: Metrics.headerHeight, width: 1, height: size.height - Metrics.headerHeight)),
            with: .color(ink.opacity(0.10))
        )

        let contentX = detailX + 16
        let contentWidth = size.width - contentX - 16
        guard contentWidth > 40 else { return }

        bar(contentX, Metrics.headerHeight + 18, 18, 18, radius: 5)
        bar(contentX + 28, Metrics.headerHeight + 19, 168, 16, radius: 4)
        rule(Metrics.headerHeight + Metrics.sectionHeaderHeight, from: detailX, to: size.width)

        var y = Metrics.headerHeight + Metrics.sectionHeaderHeight + 20

        context.fill(
            Path(roundedRect: CGRect(x: contentX, y: y, width: contentWidth, height: 96), cornerRadius: 12),
            with: .color(ink.opacity(0.05))
        )
        bar(contentX + 16, y + 16, 124, 10)
        let statWidth = (contentWidth - 32 - 24 - 92) / 2
        bar(contentX + 16, y + 42, statWidth, 38, radius: 8)
        bar(contentX + 16 + statWidth + 12, y + 42, statWidth, 38, radius: 8)
        bar(contentX + contentWidth - 16 - 80, y + 52, 80, 20, radius: 5)
        y += 96 + 24

        bar(contentX, y, 140, 10)
        y += 26

        let columns = max(1, Int((contentWidth + Metrics.roleCardSpacing)
            / (Metrics.roleCardMinWidth + Metrics.roleCardSpacing)))
        let cardWidth = (contentWidth - CGFloat(columns - 1) * Metrics.roleCardSpacing) / CGFloat(columns)
        for index in 0 ..< (columns * 2) {
            let cx = contentX + CGFloat(index % columns) * (cardWidth + Metrics.roleCardSpacing)
            let cy = y + CGFloat(index / columns) * (Metrics.roleCardHeight + Metrics.roleCardSpacing)
            guard cy + Metrics.roleCardHeight < size.height else { break }
            context.fill(
                Path(roundedRect: CGRect(x: cx, y: cy, width: cardWidth, height: Metrics.roleCardHeight), cornerRadius: 10),
                with: .color(ink.opacity(0.05))
            )
            bar(cx + 12, cy + 14, 14, 14, radius: 7)
            bar(cx + 34, cy + 17, min(cardWidth - 60, 96), 9)
            let buttonWidth = (cardWidth - 24 - 8) / 2
            bar(cx + 12, cy + 46, buttonWidth, 24, radius: 6)
            bar(cx + 12 + buttonWidth + 8, cy + 46, buttonWidth, 24, radius: 6)
        }
        y += CGFloat(2) * (Metrics.roleCardHeight + Metrics.roleCardSpacing) + 12

        guard y + 60 < size.height else { return }
        bar(contentX, y, 112, 10)
        y += 24
        for row in 0 ..< 3 {
            let ry = y + CGFloat(row) * 22
            guard ry + 12 < size.height else { break }
            bar(contentX, ry, 72, 9)
            bar(contentX + 84, ry, min(contentWidth - 84, 260 - CGFloat(row) * 40), 9)
        }
    }
}
