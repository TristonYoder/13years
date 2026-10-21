// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct LandscapeMetrics: Equatable, Sendable {
    public let size: CGSize

    public init(size: CGSize) {
        self.size = size
    }

    private func legible(_ value: CGFloat) -> CGFloat {
        #if os(tvOS)
        max(23, value)
        #else
        value
        #endif
    }

    public var shorterSide: CGFloat { max(1, min(size.width, size.height)) }
    public var frameThickness: CGFloat { max(14, 0.022 * shorterSide) }
    public var badgeFontSize: CGFloat { 0.11 * shorterSide }
    public var countdownFontSize: CGFloat { 0.32 * shorterSide }
    public var titleFontSize: CGFloat { 0.05 * shorterSide }
    public var timeFontSize: CGFloat { min(0.075 * shorterSide, slotWidth / 6.2) }
    public var timeCaptionFontSize: CGFloat { legible(0.018 * shorterSide) }
    public var topRowHeight: CGFloat { badgeFontSize * 1.3 }
    public var centreY: CGFloat { size.height / 2 }
    public var badgeWidthEstimate: CGFloat { badgeFontSize * 5.2 }
    public var clockLeading: CGFloat { frameThickness + margin }
    public var slotWidth: CGFloat { min(badgeWidthEstimate, 0.38 * size.width) }
    public var frameCornerRadius: CGFloat { max(18, 0.04 * shorterSide) }
    public var cardWidth: CGFloat { max(1, (size.width - 2 * clockLeading - margin) / 2) }
    public var cardMaxHeight: CGFloat { 0.28 * shorterSide }
    public var cardPadding: CGFloat { margin * 0.6 }
    public var cardContentMaxHeight: CGFloat { max(1, cardMaxHeight - 2 * cardPadding) }
    public var singleCardWidth: CGFloat { 2 * cardWidth + margin }
    public var messageFontSize: CGFloat { 0.06 * shorterSide }
    public var centreTagBottom: CGFloat { centreY + 0.185 * shorterSide }
    public var messageClearance: CGFloat { 0.01 * shorterSide }
    public var bottomRowBottom: CGFloat { size.height - frameThickness - margin }
    public var messageMaxHeight: CGFloat {
        max(1, min(0.25 * shorterSide, bottomRowBottom - centreTagBottom - messageClearance))
    }
    public var messageTop: CGFloat { bottomRowBottom - messageMaxHeight }
    public var messageCaptionFontSize: CGFloat { legible(0.022 * shorterSide) }
    public static let messageMaxLines = 3
    public static let fitScales: [CGFloat] = [1, 0.85, 0.72, 0.6, 0.5, 0.4]
    public var nextTitleFontSize: CGFloat { 0.035 * shorterSide }
    public static let widestCueWord = "STANDBY"
    public var captionFontSize: CGFloat { legible(0.02 * shorterSide) }
    public var tagFontSize: CGFloat { 0.035 * shorterSide }
    public var roleFontSize: CGFloat { 0.04 * shorterSide }
    public var statusFontSize: CGFloat { legible(0.022 * shorterSide) }
    public var noteFontSize: CGFloat { 0.028 * shorterSide }
    public var margin: CGFloat { 0.03 * shorterSide }
    public var cornerRadius: CGFloat { 0.02 * shorterSide }

    public static func firstFittingIndex(heights: [CGFloat], maxHeight: CGFloat) -> Int {
        heights.firstIndex { $0 <= maxHeight } ?? max(0, heights.count - 1)
    }

    public static func cardWidth(for visibleCards: Int, in metrics: LandscapeMetrics) -> CGFloat {
        visibleCards >= 2 ? metrics.cardWidth : metrics.singleCardWidth
    }

    var chrome: PagerChromeSizes {
        PagerChromeSizes(
            timeFont: timeFontSize,
            timeCaptionFont: timeCaptionFontSize,
            badgeFont: badgeFontSize,
            topRowHeight: topRowHeight,
            slotWidth: slotWidth,
            statusFont: statusFontSize,
            roleFont: roleFontSize,
            margin: margin,
            cornerRadius: cornerRadius
        )
    }

    public static func isLandscape(_ size: CGSize) -> Bool {
        size.width > size.height
    }
}

public struct LandscapePagerView<RoleMenu: View>: View {
    let size: CGSize
    let presentation: PagerPresentationState
    let disconnectPhase: DisconnectPhase
    let roleMenu: RoleMenu
    let standingMessage: InterTeamMessage?
    let showMessages: () -> Void
    let showSettings: () -> Void
    let openMessage: () -> Void
    let dismissMessage: () -> Void
    @AppStorage(CueDisplayStyle.storageKey) private var cueDisplayRaw: String = CueDisplayStyle.defaultStyle.rawValue

    public init(
        size: CGSize,
        presentation: PagerPresentationState,
        disconnectPhase: DisconnectPhase,
        standingMessage: InterTeamMessage?,
        showMessages: @escaping () -> Void,
        showSettings: @escaping () -> Void,
        openMessage: @escaping () -> Void,
        dismissMessage: @escaping () -> Void,
        @ViewBuilder roleMenu: () -> RoleMenu
    ) {
        self.size = size
        self.presentation = presentation
        self.disconnectPhase = disconnectPhase
        self.standingMessage = standingMessage
        self.showMessages = showMessages
        self.showSettings = showSettings
        self.openMessage = openMessage
        self.dismissMessage = dismissMessage
        self.roleMenu = roleMenu()
    }

    private var metrics: LandscapeMetrics { LandscapeMetrics(size: size) }
    private var state: CueState { presentation.currentState }
    private var style: CueDisplayStyle { CueDisplayStyle.resolve(cueDisplayRaw) }

    public var body: some View {
        let m = metrics
        ZStack {
            style.groundColor(for: state).ignoresSafeArea()

            centre(m)
                .opacity(disconnectPhase == .extended ? 0 : 1)
                .padding(.horizontal, m.frameThickness + m.margin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            VStack(spacing: m.margin) {
                Color.clear.frame(height: m.chrome.headerHeight)
                Spacer(minLength: 0)
                bottomRow(m)
            }
            .opacity(disconnectPhase == .extended ? 0 : 1)
            .padding(m.frameThickness + m.margin)

            PagerDisconnectOverlay(phase: disconnectPhase)

            VStack(spacing: 0) {
                PagerTopRow(
                    sizes: m.chrome,
                    state: state,
                    style: style,
                    producerClock: presentation.producerClock,
                    clockFormat: presentation.clockFormat,
                    roleName: presentation.activeRole?.name ?? "Host Pager",
                    roleColumnMaxWidth: 0.2 * m.size.width,
                    hidesLeading: disconnectPhase == .extended,
                    showMessages: showMessages,
                    showSettings: showSettings,
                    roleMenu: roleMenu
                )
                Spacer(minLength: 0)
            }
            .padding(m.frameThickness + m.margin)

            if disconnectPhase == .dimmed {
                PagerNoConnectionNotice(font: m.statusFontSize, bottomInset: m.frameThickness, style: style, state: state)
            }

            if let frame = style.frameColor(for: state) {
                PagerCueFrame(color: frame, thickness: m.frameThickness, radius: m.frameCornerRadius)
            }
        }
    }

    private func centre(_ m: LandscapeMetrics) -> some View {
        let primary = style.primaryText(for: state)
        return Group {
            if let item = presentation.activeTimerItem {
                VStack(spacing: m.margin * 0.2) {
                    Text(item.title.uppercased())
                        .font(.system(size: m.titleFontSize, weight: .bold))
                        .foregroundColor(primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)

                    if !item.isHeader {
                        Text(TimeFormatting.string(forSeconds: item.remainingSeconds, threshold: presentation.hourFormatThreshold))
                            .font(.inter(size: m.countdownFontSize, weight: .black))
                            .monospacedDigit()
                            .foregroundColor(primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.3)

                        Text(item.isDurationActual ? "ACTUAL" : "PROJECTED")
                            .font(.system(size: m.tagFontSize, weight: .bold))
                            .tracking(m.tagFontSize * 0.12)
                            .foregroundColor(style.secondaryText(for: state, opacity: 0.6))
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                Color.clear.frame(height: 0)
            }
        }
    }

    @ViewBuilder
    private func bottomRow(_ m: LandscapeMetrics) -> some View {
        if let message = standingMessage {
            PagerMessagePanel(
                message: message,
                fontSize: m.messageFontSize,
                captionFontSize: m.messageCaptionFontSize,
                maxLines: LandscapeMetrics.messageMaxLines,
                maxHeight: m.messageMaxHeight,
                padding: m.cardPadding,
                cornerRadius: m.cornerRadius,
                openMessage: openMessage,
                dismissMessage: dismissMessage
            )
            .id(message.id)
        } else {
            cardsRow(m)
        }
    }

    @ViewBuilder
    private func cardsRow(_ m: LandscapeMetrics) -> some View {
        let currentDetails = presentation.currentDetailsLine()
        let nextDetails = presentation.nextDetailsLine()
        let hasCurrent = !presentation.currentNotes.isEmpty || currentDetails != nil
        let hasNext = presentation.nextItem != nil
        let width = LandscapeMetrics.cardWidth(for: (hasCurrent ? 1 : 0) + (hasNext ? 1 : 0), in: m)
        if hasCurrent || hasNext {
            HStack(alignment: .top, spacing: m.margin) {
                if hasCurrent {
                    card(m, width: width) { scale in currentContent(m, details: currentDetails, scale: scale) }
                }
                if hasNext {
                    card(m, width: width) { scale in nextContent(m, details: nextDetails, scale: scale) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detailsText(_ m: LandscapeMetrics, _ line: String, opacity: Double, scale: CGFloat) -> some View {
        Text(line)
            .font(.system(size: m.noteFontSize * scale, weight: .semibold))
            .foregroundColor(.white.opacity(opacity))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func currentContent(_ m: LandscapeMetrics, details: String?, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: m.margin * 0.3 * scale) {
            Text("CURRENT")
                .font(.system(size: m.captionFontSize * scale, weight: .heavy))
                .tracking(2)
                .foregroundColor(.white.opacity(0.5))
            if let details {
                detailsText(m, details, opacity: 0.9, scale: scale)
            }
            noteLines(m, presentation.currentNotes, weight: .bold, opacity: 1, scale: scale)
        }
    }

    @ViewBuilder
    private func nextContent(_ m: LandscapeMetrics, details: String?, scale: CGFloat) -> some View {
        if let next = presentation.nextItem {
            VStack(alignment: .leading, spacing: m.margin * 0.3 * scale) {
                HStack(alignment: .firstTextBaseline, spacing: m.margin * 0.5) {
                    Text(next.title.uppercased())
                        .font(.system(size: m.nextTitleFontSize * scale, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    Text(TimeFormatting.string(forSeconds: next.lengthInSeconds, threshold: presentation.hourFormatThreshold))
                        .font(.inter(size: m.nextTitleFontSize * scale, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                if let details {
                    detailsText(m, details, opacity: 0.8, scale: scale)
                }
                noteLines(m, presentation.nextNotes, weight: .medium, opacity: 0.85, scale: scale)
            }
        }
    }

    private func noteLines(_ m: LandscapeMetrics, _ notes: [(category: String, text: String)], weight: Font.Weight, opacity: Double, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            ForEach(notes, id: \.category) { note in
                PagerNoteText.line(category: note.category, text: note.text)
                    .font(.system(size: m.noteFontSize * scale, weight: weight))
                    .foregroundColor(.white.opacity(opacity))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func card<Content: View>(_ m: LandscapeMetrics, width: CGFloat, @ViewBuilder content: @escaping (CGFloat) -> Content) -> some View {
        FirstFittingLayout(maxHeight: m.cardContentMaxHeight) {
            ForEach(Array(LandscapeMetrics.fitScales.enumerated()), id: \.offset) { _, scale in
                content(scale)
            }
        }
        .padding(m.cardPadding)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(style.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: m.cornerRadius, style: .continuous))
    }
}

struct FirstFittingLayout: Layout {
    let maxHeight: CGFloat

    private func chosen(_ subviews: Subviews, width: CGFloat?) -> (index: Int, size: CGSize)? {
        guard !subviews.isEmpty else { return nil }
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
        let index = LandscapeMetrics.firstFittingIndex(heights: sizes.map(\.height), maxHeight: maxHeight)
        return (index, sizes[index])
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let pick = chosen(subviews, width: proposal.width) else { return .zero }
        return CGSize(width: proposal.width ?? pick.size.width, height: min(pick.size.height, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let pick = chosen(subviews, width: bounds.width) else { return }
        for (i, sub) in subviews.enumerated() {
            if i == pick.index {
                sub.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
            } else {
                sub.place(at: CGPoint(x: -10000, y: -10000), anchor: .topLeading, proposal: ProposedViewSize(width: 1, height: 1))
            }
        }
    }
}

enum PagerNoteText {
    static func line(category: String, text: String) -> Text {
        Text("\(category):").bold() + Text(" \(text)")
    }
}

struct PagerCueFrame: View {
    let color: Color
    let thickness: CGFloat
    let radius: CGFloat

    var body: some View {
        #if os(iOS)
        GeometryReader { proxy in
            let edges = bandEdges(safe: proxy.safeAreaInsets)
            if #available(iOS 26.0, *) {
                Rectangle()
                    .fill(color)
                    .overlay {
                        ConcentricRectangle(corners: .concentric(minimum: .fixed(radius)), isUniform: true)
                            .padding(edges)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                    .ignoresSafeArea()
            } else {
                FrameShape(edges: edges, radius: radius)
                    .fill(color, style: FillStyle(eoFill: true))
                    .ignoresSafeArea()
            }
        }
        .allowsHitTesting(false)
        #else
        FrameShape(edges: EdgeInsets(top: thickness, leading: thickness, bottom: thickness, trailing: thickness), radius: radius)
            .fill(color, style: FillStyle(eoFill: true))
            .ignoresSafeArea()
            .allowsHitTesting(false)
        #endif
    }

    private func bandEdges(safe: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: max(thickness, safe.top),
            leading: max(thickness, safe.leading),
            bottom: thickness,
            trailing: max(thickness, safe.trailing)
        )
    }
}

struct FrameShape: Shape {
    let edges: EdgeInsets
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(
            in: CGRect(
                x: rect.minX + edges.leading,
                y: rect.minY + edges.top,
                width: rect.width - edges.leading - edges.trailing,
                height: rect.height - edges.top - edges.bottom
            ),
            cornerSize: CGSize(width: radius, height: radius),
            style: .continuous
        )
        return path
    }
}
