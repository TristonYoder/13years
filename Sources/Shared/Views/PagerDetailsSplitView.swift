// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS) || os(iOS) || os(tvOS)
import SwiftUI

public enum PagerDetailsSplit {
    public static let storageKey = "pagerDetailsSplit"
    public static let defaultFraction: Double = 2.0 / 3.0
    public static let range: ClosedRange<Double> = 0.4...0.8
    public static let dividerWidth: CGFloat = 22
    public static let minimumAspect: CGFloat = 1.15
    public static let nudge: Double = 0.05

    public static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return defaultFraction }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    public static func isSplitLayout(_ size: CGSize) -> Bool {
        size.height > 0 && size.width / size.height >= minimumAspect
    }

    public static func usableWidth(in size: CGSize) -> CGFloat {
        max(2, size.width - dividerWidth)
    }

    public static func pagerSize(in size: CGSize, fraction: Double) -> CGSize {
        CGSize(width: usableWidth(in: size) * clamp(fraction), height: size.height)
    }

    public static func detailsSize(in size: CGSize, fraction: Double) -> CGSize {
        CGSize(width: usableWidth(in: size) * (1 - clamp(fraction)), height: size.height)
    }

    public static func fraction(forDividerCenterX x: CGFloat, in size: CGSize) -> Double {
        clamp(Double((x - dividerWidth / 2) / usableWidth(in: size)))
    }
}

public struct PagerDetailsMetrics: Equatable, Sendable {
    public let size: CGSize

    public init(size: CGSize) {
        self.size = size
    }

    public var shorterSide: CGFloat { max(1, min(size.width, size.height)) }

    private func legible(_ value: CGFloat) -> CGFloat {
        #if os(tvOS)
        max(28, value)
        #else
        value
        #endif
    }

    public var bodyFontSize: CGFloat { legible(max(14, 0.03 * shorterSide)) }
    public var captionFontSize: CGFloat { legible(max(11, 0.02 * shorterSide)) }
    public var margin: CGFloat { 0.03 * shorterSide }
    public var cornerRadius: CGFloat { 0.02 * shorterSide }
    public var padding: CGFloat { margin * 0.8 }
}

struct PagerItemDetailsPanel: View {
    let html: String
    let itemId: String
    let metrics: PagerDetailsMetrics

    private var ground: HTMLColor {
        HTMLColor(AppPalette.pagerPanel) ?? HTMLColor(red: 0, green: 0, blue: 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.margin * 0.4) {
            Text("ITEM DETAILS")
                .font(.system(size: metrics.captionFontSize, weight: .heavy))
                .tracking(2)
                .foregroundColor(AppPalette.pagerClock.opacity(0.5))
            ScrollView {
                HTMLRichText(html: html, baseSize: metrics.bodyFontSize, ground: ground, isSelectable: false)
                    .foregroundColor(AppPalette.pagerClock)
            }
            .id(itemId)
            #if os(tvOS)
            .focusable()
            #endif
        }
        .padding(metrics.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppPalette.pagerPanel)
        .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
    }
}

struct PagerDetailsSplitView<Pager: View>: View {
    let size: CGSize
    let html: String
    let itemId: String
    let detailsVisible: Bool
    @Binding var fraction: Double
    let pager: (CGSize) -> Pager

    #if !os(tvOS)
    @State private var isHoveringDivider = false
    #endif

    private var metrics: PagerDetailsMetrics { PagerDetailsMetrics(size: size) }
    private var effectiveFraction: Double {
        #if os(tvOS)
        PagerDetailsSplit.defaultFraction
        #else
        PagerDetailsSplit.clamp(fraction)
        #endif
    }

    var body: some View {
        let pagerSize = PagerDetailsSplit.pagerSize(in: size, fraction: effectiveFraction)
        let detailsSize = PagerDetailsSplit.detailsSize(in: size, fraction: effectiveFraction)
        HStack(spacing: 0) {
            pager(pagerSize)
                .frame(width: pagerSize.width, height: size.height)
                .clipped()
            divider
            PagerItemDetailsPanel(html: html, itemId: itemId, metrics: metrics)
                .frame(width: detailsSize.width, height: size.height - 2 * metrics.margin)
                .padding(.vertical, metrics.margin)
                .padding(.trailing, metrics.margin * 0.5)
                .frame(height: size.height)
                .opacity(detailsVisible ? 1 : 0)
        }
        .frame(width: size.width, height: size.height)
        .background(AppPalette.pagerGround.ignoresSafeArea())
        .coordinateSpace(name: Self.space)
    }

    private static var space: String { "pagerDetailsSplit" }

    @ViewBuilder
    private var divider: some View {
        #if os(tvOS)
        Color.clear.frame(width: PagerDetailsSplit.dividerWidth, height: size.height)
        #else
        Color.clear
            .frame(width: PagerDetailsSplit.dividerWidth, height: size.height)
            .overlay {
                Capsule()
                    .fill(AppPalette.glassMedium)
                    .frame(width: 4, height: max(36, 0.12 * size.height))
                    .opacity(isHoveringDivider ? 1 : 0.6)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        fraction = PagerDetailsSplit.fraction(forDividerCenterX: value.location.x, in: size)
                    }
            )
            .onTapGesture(count: 2) { fraction = PagerDetailsSplit.defaultFraction }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.8, maximumDistance: 6)
                    .onEnded { _ in fraction = PagerDetailsSplit.defaultFraction }
            )
            .onHover { isHoveringDivider = $0 }
            .accessibilityElement()
            .accessibilityLabel("Item details divider")
            .accessibilityValue("\(Int((effectiveFraction * 100).rounded())) percent pager")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: fraction = PagerDetailsSplit.clamp(effectiveFraction + PagerDetailsSplit.nudge)
                case .decrement: fraction = PagerDetailsSplit.clamp(effectiveFraction - PagerDetailsSplit.nudge)
                @unknown default: break
                }
            }
        #endif
    }
}
#endif
