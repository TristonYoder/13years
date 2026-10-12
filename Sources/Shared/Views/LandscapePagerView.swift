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
    public var timeFontSize: CGFloat { min(0.075 * shorterSide, timeAvailableWidth / 5.6) }
    public var timeCaptionFontSize: CGFloat { 0.018 * shorterSide }
    public var topRowHeight: CGFloat { badgeFontSize * 1.3 }
    public var centreY: CGFloat { size.height / 2 }
    public var badgeWidthEstimate: CGFloat { badgeFontSize * 5.2 }
    public var timeAvailableWidth: CGFloat {
        max(1, size.width - 2 * (frameThickness + margin) - 2 * margin - badgeWidthEstimate - 0.2 * size.width)
    }
    public static let widestCueWord = "STANDBY"
    public var captionFontSize: CGFloat { 0.02 * shorterSide }
    public var roleFontSize: CGFloat { 0.04 * shorterSide }
    public var statusFontSize: CGFloat { 0.022 * shorterSide }
    public var noteFontSize: CGFloat { 0.028 * shorterSide }
    public var margin: CGFloat { 0.03 * shorterSide }
    public var cornerRadius: CGFloat { 0.02 * shorterSide }
    public var nextCardMaxWidth: CGFloat { 0.4 * size.width }
    public var notesCardMaxWidth: CGFloat { 0.55 * size.width }

    public static func isLandscape(_ size: CGSize) -> Bool {
        size.width > size.height
    }
}

public struct LandscapePagerView<RoleMenu: View, Banner: View>: View {
    let size: CGSize
    let presentation: PagerPresentationState
    let connectionText: String
    let isConnected: Bool
    let roleMenu: RoleMenu
    let banner: Banner
    let showMessages: () -> Void

    public init(
        size: CGSize,
        presentation: PagerPresentationState,
        connectionText: String,
        isConnected: Bool,
        showMessages: @escaping () -> Void,
        @ViewBuilder roleMenu: () -> RoleMenu,
        @ViewBuilder banner: () -> Banner
    ) {
        self.size = size
        self.presentation = presentation
        self.connectionText = connectionText
        self.isConnected = isConnected
        self.showMessages = showMessages
        self.roleMenu = roleMenu()
        self.banner = banner()
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

            VStack {
                Spacer()
                banner
                    .padding(.horizontal, m.frameThickness + m.margin)
                    .padding(.bottom, m.frameThickness + m.margin)
            }

            Rectangle()
                .strokeBorder(frameColor, lineWidth: m.frameThickness)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private func topRow(_ m: LandscapeMetrics) -> some View {
        HStack(alignment: .top, spacing: m.margin) {
            badge(m)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: m.timeCaptionFontSize * 0.2) {
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
            }
            .frame(maxWidth: .infinity)

            roleColumn(m)
                .frame(maxWidth: 0.2 * m.size.width, alignment: .trailing)
        }
        .frame(height: m.topRowHeight, alignment: .top)
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

    private func bottomRow(_ m: LandscapeMetrics) -> some View {
        HStack(alignment: .bottom, spacing: m.margin) {
            if !presentation.currentNotes.isEmpty {
                VStack(alignment: .leading, spacing: m.margin * 0.3) {
                    ForEach(presentation.currentNotes, id: \.category) { note in
                        notePanel(
                            m,
                            label: presentation.currentNotes.count > 1 ? "CURRENT — \(note.category.uppercased())" : "CURRENT",
                            text: note.text
                        )
                    }
                }
                .frame(maxWidth: m.notesCardMaxWidth, alignment: .leading)
            }

            Spacer(minLength: 0)

            if let next = presentation.nextItem {
                VStack(alignment: .leading, spacing: m.margin * 0.3) {
                    Text("NEXT")
                        .font(.inter(size: m.captionFontSize, weight: .heavy))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.5))
                    Text(next.title.uppercased())
                        .font(.inter(size: m.noteFontSize, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    ForEach(presentation.nextNotes, id: \.category) { note in
                        Text(note.text)
                            .font(.inter(size: m.noteFontSize * 0.85, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(m.margin * 0.6)
                .frame(maxWidth: m.nextCardMaxWidth, alignment: .leading)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: m.cornerRadius, style: .continuous))
            }
        }
    }

    private func notePanel(_ m: LandscapeMetrics, label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.inter(size: m.captionFontSize, weight: .heavy))
                .tracking(2)
                .foregroundColor(.white.opacity(0.5))
            Text(text)
                .font(.inter(size: m.noteFontSize, weight: .bold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(m.margin * 0.6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: m.cornerRadius, style: .continuous))
    }
}
