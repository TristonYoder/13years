// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct LandscapeMetrics: Equatable, Sendable {
    public let size: CGSize

    public init(size: CGSize) {
        self.size = size
    }

    public var shorterSide: CGFloat { max(1, min(size.width, size.height)) }
    public var frameThickness: CGFloat { max(14, 0.022 * shorterSide) }
    public var badgeFontSize: CGFloat { 0.11 * shorterSide }
    public var countdownFontSize: CGFloat { 0.32 * shorterSide }
    public var titleFontSize: CGFloat { 0.05 * shorterSide }
    public var timeFontSize: CGFloat { min(0.075 * shorterSide, slotWidth / 6.2) }
    public var timeCaptionFontSize: CGFloat { 0.018 * shorterSide }
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
    public var centreTagBottom: CGFloat { centreY + 0.17 * shorterSide }
    public var messageClearance: CGFloat { 0.01 * shorterSide }
    public var bottomRowBottom: CGFloat { size.height - frameThickness - margin }
    public var messageMaxHeight: CGFloat {
        max(1, min(0.25 * shorterSide, bottomRowBottom - centreTagBottom - messageClearance))
    }
    public var messageTop: CGFloat { bottomRowBottom - messageMaxHeight }
    public var messageCaptionFontSize: CGFloat { 0.022 * shorterSide }
    public static let messageMaxLines = 3
    public static let fitScales: [CGFloat] = [1, 0.85, 0.72, 0.6, 0.5, 0.4]
    public var nextTitleFontSize: CGFloat { 0.035 * shorterSide }
    public static let widestCueWord = "STANDBY"
    public var captionFontSize: CGFloat { 0.02 * shorterSide }
    public var roleFontSize: CGFloat { 0.04 * shorterSide }
    public var statusFontSize: CGFloat { 0.022 * shorterSide }
    public var noteFontSize: CGFloat { 0.028 * shorterSide }
    public var margin: CGFloat { 0.03 * shorterSide }
    public var cornerRadius: CGFloat { 0.02 * shorterSide }

    public static func firstFittingIndex(heights: [CGFloat], maxHeight: CGFloat) -> Int {
        heights.firstIndex { $0 <= maxHeight } ?? max(0, heights.count - 1)
    }

    public static func cardWidth(for visibleCards: Int, in metrics: LandscapeMetrics) -> CGFloat {
        visibleCards >= 2 ? metrics.cardWidth : metrics.singleCardWidth
    }

    public static func isLandscape(_ size: CGSize) -> Bool {
        size.width > size.height
    }
}

public struct LandscapePagerView<RoleMenu: View>: View {
    let size: CGSize
    let presentation: PagerPresentationState
    let connectionText: String
    let isConnected: Bool
    let roleMenu: RoleMenu
    let standingMessage: InterTeamMessage?
    let showMessages: () -> Void
    let openMessage: () -> Void
    let dismissMessage: () -> Void
    @State private var messageDragOffset: CGFloat = 0

    public init(
        size: CGSize,
        presentation: PagerPresentationState,
        connectionText: String,
        isConnected: Bool,
        standingMessage: InterTeamMessage?,
        showMessages: @escaping () -> Void,
        openMessage: @escaping () -> Void,
        dismissMessage: @escaping () -> Void,
        @ViewBuilder roleMenu: () -> RoleMenu
    ) {
        self.size = size
        self.presentation = presentation
        self.connectionText = connectionText
        self.isConnected = isConnected
        self.standingMessage = standingMessage
        self.showMessages = showMessages
        self.openMessage = openMessage
        self.dismissMessage = dismissMessage
        self.roleMenu = roleMenu()
    }

    private var metrics: LandscapeMetrics { LandscapeMetrics(size: size) }
    private var state: CueState { presentation.currentState }
    private var cueWord: String { PagerPresentationState.cueWordText(for: state) }
    private static var ground: Color { Color(red: 0.067, green: 0.067, blue: 0.078) }
    private static var darkText: Color { Color(red: 0.1, green: 0.1, blue: 0.1) }

    private var frameColor: Color {
        state == .off ? Color.white.opacity(0.06) : state.color
    }

    public var body: some View {
        let m = metrics
        ZStack {
            Self.ground.ignoresSafeArea()

            centre(m)
                .padding(.horizontal, m.frameThickness + m.margin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            VStack(spacing: m.margin) {
                topRow(m)
                Spacer(minLength: 0)
                bottomRow(m)
            }
            .padding(m.frameThickness + m.margin)

            FrameShape(thickness: m.frameThickness, radius: m.frameCornerRadius)
                .fill(frameColor, style: FillStyle(eoFill: true))
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onChange(of: standingMessage?.id) { _, _ in
            messageDragOffset = 0
        }
    }

    private func topRow(_ m: LandscapeMetrics) -> some View {
        HStack(alignment: .top, spacing: m.margin) {
            ZStack(alignment: .topLeading) {
                clock(m).opacity(cueWord.isEmpty ? 1 : 0)
                badge(m)
            }
            .frame(width: m.slotWidth, alignment: .leading)

            Spacer(minLength: 0)

            roleColumn(m)
                .frame(maxWidth: 0.2 * m.size.width, alignment: .trailing)
        }
        .frame(height: m.topRowHeight, alignment: .top)
    }

    private func clock(_ m: LandscapeMetrics) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: m.timeCaptionFontSize * 0.2) {
                Text(context.date, format: .dateTime.hour().minute().second())
                    .font(.inter(size: m.timeFontSize, weight: .black))
                    .monospacedDigit()
                    .foregroundColor(Color(white: 0.96))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("LOCAL TIME")
                    .font(.inter(size: m.timeCaptionFontSize, weight: .bold))
                    .tracking(m.timeCaptionFontSize * 0.25)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func badgeLabel(_ word: String, _ m: LandscapeMetrics) -> some View {
        Text(word)
            .font(.inter(size: m.badgeFontSize, weight: .black))
            .foregroundColor(Self.darkText)
            .lineLimit(1)
            .padding(.horizontal, m.badgeFontSize * 0.3)
            .padding(.vertical, m.badgeFontSize * 0.08)
    }

    private func badge(_ m: LandscapeMetrics) -> some View {
        ZStack {
            badgeLabel(LandscapeMetrics.widestCueWord, m).hidden()
            if !cueWord.isEmpty {
                badgeLabel(cueWord, m)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(state.color)
                    .clipShape(RoundedRectangle(cornerRadius: m.cornerRadius, style: .continuous))
            }
        }
        .fixedSize()
        .frame(height: m.topRowHeight, alignment: .top)
    }

    private func roleColumn(_ m: LandscapeMetrics) -> some View {
        VStack(alignment: .trailing, spacing: m.margin * 0.2) {
            Menu {
                roleMenu
            } label: {
                Text(presentation.activeRole?.name ?? "Host Pager")
                    .font(.inter(size: m.roleFontSize, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .buttonStyle(.plain)

            if let person = presentation.activeRole?.personName {
                Text("FOR: \(person.uppercased())")
                    .font(.inter(size: m.statusFontSize, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(isConnected ? Color.green : Color.red)
                    .frame(width: m.statusFontSize * 0.7, height: m.statusFontSize * 0.7)
                Text(connectionText)
                    .font(.inter(size: m.statusFontSize, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Button(action: showMessages) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: m.statusFontSize * 1.1))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
    }

    private func centre(_ m: LandscapeMetrics) -> some View {
        Group {
            if let item = presentation.activeTimerItem {
                VStack(spacing: m.margin * 0.2) {
                    Text(item.title.uppercased())
                        .font(.inter(size: m.titleFontSize, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)

                    if !item.isHeader {
                        Text(TimeFormatting.string(forSeconds: item.remainingSeconds, threshold: presentation.hourFormatThreshold))
                            .font(.inter(size: m.countdownFontSize, weight: .black))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.3)

                        Text(item.isDurationActual ? "ACTUAL" : "PROJECTED")
                            .font(.inter(size: m.captionFontSize, weight: .bold))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.5))
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
            messagePanel(m, message)
        } else {
            cardsRow(m)
        }
    }

    private var messageOpacity: Double {
        1.0 - min(Double(abs(messageDragOffset)) / 200.0, 1.0) * 0.7
    }

    private func messagePanel(_ m: LandscapeMetrics, _ message: InterTeamMessage) -> some View {
        VStack(alignment: .leading, spacing: m.messageCaptionFontSize * 0.3) {
            Text(message.sender.uppercased())
                .font(.inter(size: m.messageCaptionFontSize, weight: .heavy))
                .tracking(m.messageCaptionFontSize * 0.15)
                .foregroundColor(Self.darkText.opacity(0.7))
                .lineLimit(1)
            Text(message.text)
                .font(.inter(size: m.messageFontSize, weight: .bold))
                .foregroundColor(Self.darkText)
                .multilineTextAlignment(.leading)
                .lineLimit(LandscapeMetrics.messageMaxLines)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(m.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: m.messageMaxHeight, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.yellow)
        .clipShape(RoundedRectangle(cornerRadius: m.cornerRadius, style: .continuous))
        .offset(x: messageDragOffset)
        .opacity(messageOpacity)
        .contentShape(Rectangle())
        #if os(iOS) || os(macOS)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    messageDragOffset = value.translation.width
                }
                .onEnded { value in
                    let distance = abs(value.translation.width)
                    if distance > 80 {
                        let direction: CGFloat = value.translation.width > 0 ? 1 : -1
                        withAnimation(.easeOut(duration: 0.2)) {
                            messageDragOffset = direction * 500
                        }
                        dismissMessage()
                    } else if distance < 10 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            messageDragOffset = 0
                        }
                        openMessage()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            messageDragOffset = 0
                        }
                    }
                }
        )
        #else
        .onTapGesture {
            openMessage()
        }
        .focusable(true)
        #endif
    }

    @ViewBuilder
    private func cardsRow(_ m: LandscapeMetrics) -> some View {
        let hasCurrent = !presentation.currentNotes.isEmpty
        let hasNext = presentation.nextItem != nil
        let width = LandscapeMetrics.cardWidth(for: (hasCurrent ? 1 : 0) + (hasNext ? 1 : 0), in: m)
        if hasCurrent || hasNext {
            HStack(alignment: .top, spacing: m.margin) {
                if hasCurrent {
                    card(m, width: width) { scale in currentContent(m, scale: scale) }
                }
                if hasNext {
                    card(m, width: width) { scale in nextContent(m, scale: scale) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func currentContent(_ m: LandscapeMetrics, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: m.margin * 0.3 * scale) {
            Text("CURRENT")
                .font(.inter(size: m.captionFontSize * scale, weight: .heavy))
                .tracking(2)
                .foregroundColor(.white.opacity(0.5))
            noteLines(m, presentation.currentNotes, weight: .bold, opacity: 1, scale: scale)
        }
    }

    @ViewBuilder
    private func nextContent(_ m: LandscapeMetrics, scale: CGFloat) -> some View {
        if let next = presentation.nextItem {
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
                noteLines(m, presentation.nextNotes, weight: .medium, opacity: 0.85, scale: scale)
            }
        }
    }

    private func noteLines(_ m: LandscapeMetrics, _ notes: [(category: String, text: String)], weight: Font.Weight, opacity: Double, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            ForEach(notes, id: \.category) { note in
                PagerNoteText.line(category: note.category, text: note.text)
                    .font(.inter(size: m.noteFontSize * scale, weight: weight))
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
        .background(Color.white.opacity(0.1))
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

struct FrameShape: Shape {
    let thickness: CGFloat
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(
            in: rect.insetBy(dx: thickness, dy: thickness),
            cornerSize: CGSize(width: radius, height: radius),
            style: .continuous
        )
        return path
    }
}
