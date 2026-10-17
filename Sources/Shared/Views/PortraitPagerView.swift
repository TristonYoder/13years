// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct PortraitMetrics: Equatable, Sendable {
    public let size: CGSize

    public init(size: CGSize) {
        self.size = size
    }

    public var width: CGFloat { max(1, size.width) }
    public var frameThickness: CGFloat { max(10, 0.022 * width) }
    public var frameCornerRadius: CGFloat { max(18, 0.04 * width) }
    public var margin: CGFloat { 0.04 * width }
    public var inset: CGFloat { frameThickness + margin }
    public var cornerRadius: CGFloat { 0.03 * width }
    public var cardPadding: CGFloat { 0.035 * width }
    public var badgeFontSize: CGFloat { 0.085 * width }
    public var badgeWidthEstimate: CGFloat { badgeFontSize * 5.2 }
    public var slotWidth: CGFloat { min(badgeWidthEstimate, 0.5 * width) }
    public var timeFontSize: CGFloat { min(0.07 * width, slotWidth / 6.2) }
    public var timeCaptionFontSize: CGFloat { 0.026 * width }
    public var topRowHeight: CGFloat { badgeFontSize * 1.3 }
    public var headerHeight: CGFloat { chrome.headerHeight }
    public var topRowBottom: CGFloat { inset + headerHeight }
    public var roleColumnMaxWidth: CGFloat { max(1, width - 2 * inset - slotWidth - margin) }
    public var statusFontSize: CGFloat { 0.028 * width }
    public var roleFontSize: CGFloat { 0.045 * width }
    public var titleFontSize: CGFloat { 0.05 * width }
    public var countdownFontSize: CGFloat { 0.2 * width }
    public var tagFontSize: CGFloat { 0.026 * width }
    public var noteFontSize: CGFloat { 0.038 * width }
    public var nextTitleFontSize: CGFloat { 0.04 * width }
    public var nextCardMaxHeight: CGFloat { 0.4 * width }
    public var nextCardContentMaxHeight: CGFloat { max(1, nextCardMaxHeight - 2 * cardPadding) }
    public var messageFontSize: CGFloat { 0.055 * width }
    public var messageCaptionFontSize: CGFloat { 0.026 * width }
    public var messageMaxHeight: CGFloat { 0.34 * width }
    public static let messageMaxLines = 4
    public static let fitScales: [CGFloat] = [1, 0.85, 0.72, 0.6, 0.5, 0.4]

    public var bottomEdge: CGFloat { size.height - inset }

    public func currentCardCentreY(bottomStackHeight: CGFloat) -> CGFloat {
        let top = topRowBottom + margin
        let bottom = bottomEdge - bottomStackHeight - (bottomStackHeight > 0 ? margin : 0)
        return (top + bottom) / 2
    }

    public static func isPortrait(_ size: CGSize) -> Bool {
        size.height >= size.width
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
}

public struct PortraitPagerView<RoleMenu: View>: View {
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

    private var metrics: PortraitMetrics { PortraitMetrics(size: size) }
    private var state: CueState { presentation.currentState }
    private var style: CueDisplayStyle { CueDisplayStyle.resolve(cueDisplayRaw) }

    public var body: some View {
        let m = metrics
        ZStack {
            style.groundColor(for: state).ignoresSafeArea()

            VStack(spacing: m.margin) {
                Color.clear.frame(height: m.headerHeight)

                currentRegion(m)

                bottomStack(m)
            }
            .padding(m.inset)
            .opacity(disconnectPhase == .extended ? 0 : 1)

            PagerDisconnectOverlay(phase: disconnectPhase)

            VStack(spacing: 0) {
                PagerTopRow(
                    sizes: m.chrome,
                    state: state,
                    style: style,
                    producerClock: presentation.producerClock,
                    clockFormat: presentation.clockFormat,
                    roleName: presentation.activeRole?.name ?? "Host Pager",
                    roleColumnMaxWidth: m.roleColumnMaxWidth,
                    hidesLeading: disconnectPhase == .extended,
                    showMessages: showMessages,
                    showSettings: showSettings,
                    roleMenu: roleMenu
                )
                Spacer(minLength: 0)
            }
            .padding(m.inset)

            if disconnectPhase == .dimmed {
                PagerNoConnectionNotice(font: m.statusFontSize, bottomInset: m.frameThickness, style: style, state: state)
            }

            if let frame = style.frameColor(for: state) {
                FrameShape(thickness: m.frameThickness, radius: m.frameCornerRadius)
                    .fill(frame, style: FillStyle(eoFill: true))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }

    private func currentRegion(_ m: PortraitMetrics) -> some View {
        ZStack {
            if let item = presentation.activeTimerItem {
                ViewThatFits(in: .vertical) {
                    ForEach(Array(PortraitMetrics.fitScales.enumerated()), id: \.offset) { _, scale in
                        currentCard(m, item: item, scale: scale)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func currentCard(_ m: PortraitMetrics, item: PCOTimerItem, scale: CGFloat) -> some View {
        let notes = presentation.currentNotes
        let details = presentation.currentDetailsLine()
        return VStack(spacing: m.margin * 0.3 * scale) {
            Text(item.title.uppercased())
                .font(.inter(size: m.titleFontSize * scale, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            if !item.isHeader {
                Text(TimeFormatting.string(forSeconds: item.remainingSeconds, threshold: presentation.hourFormatThreshold))
                    .font(.inter(size: m.countdownFontSize * scale, weight: .black))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)

                Text(item.isDurationActual ? "ACTUAL" : "PROJECTED")
                    .font(.inter(size: m.tagFontSize * scale, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.5))
            }

            if !item.isHeader, let details {
                detailsText(m, details, opacity: 0.85, scale: scale)
            }

            if !item.isHeader && !notes.isEmpty {
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 1)
                    .padding(.vertical, m.margin * 0.2 * scale)
                noteLines(m, notes, weight: .bold, opacity: 1, scale: scale)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(m.cardPadding)
        .frame(maxWidth: .infinity)
        .background(style.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: m.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func bottomStack(_ m: PortraitMetrics) -> some View {
        let hasNext = presentation.nextItem != nil
        if hasNext || standingMessage != nil {
            VStack(spacing: m.margin) {
                if let next = presentation.nextItem {
                    nextCard(m, next: next)
                }
                if let message = standingMessage {
                    PagerMessagePanel(
                        message: message,
                        fontSize: m.messageFontSize,
                        captionFontSize: m.messageCaptionFontSize,
                        maxLines: PortraitMetrics.messageMaxLines,
                        maxHeight: m.messageMaxHeight,
                        padding: m.cardPadding,
                        cornerRadius: m.cornerRadius,
                        openMessage: openMessage,
                        dismissMessage: dismissMessage
                    )
                    .id(message.id)
                }
            }
        }
    }

    private func detailsText(_ m: PortraitMetrics, _ line: String, opacity: Double, scale: CGFloat) -> some View {
        Text(line)
            .font(.inter(size: m.noteFontSize * scale, weight: .semibold))
            .foregroundColor(.white.opacity(opacity))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func nextCard(_ m: PortraitMetrics, next: PCOTimerItem) -> some View {
        let details = presentation.nextDetailsLine()
        return FirstFittingLayout(maxHeight: m.nextCardContentMaxHeight) {
            ForEach(Array(PortraitMetrics.fitScales.enumerated()), id: \.offset) { _, scale in
                VStack(alignment: .leading, spacing: m.margin * 0.3 * scale) {
                    HStack(alignment: .firstTextBaseline, spacing: m.margin * 0.5) {
                        Text(next.title.uppercased())
                            .font(.inter(size: m.nextTitleFontSize * scale, weight: .bold))
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
        .padding(m.cardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(style.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: m.cornerRadius, style: .continuous))
    }

    private func noteLines(_ m: PortraitMetrics, _ notes: [(category: String, text: String)], weight: Font.Weight, opacity: Double, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            ForEach(notes, id: \.category) { note in
                PagerNoteText.line(category: note.category, text: note.text)
                    .font(.inter(size: m.noteFontSize * scale, weight: weight))
                    .foregroundColor(.white.opacity(opacity))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
