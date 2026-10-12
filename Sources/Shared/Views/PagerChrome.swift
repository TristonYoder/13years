// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public enum CueDisplayStyle: String, CaseIterable, Identifiable, Sendable {
    case outline
    case fullscreen

    public static let storageKey = "pagerCueDisplay"
    public static let defaultStyle: CueDisplayStyle = .outline

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .outline: return "Outline"
        case .fullscreen: return "Full screen"
        }
    }

    public static func resolve(_ raw: String) -> CueDisplayStyle {
        CueDisplayStyle(rawValue: raw) ?? defaultStyle
    }

    public static let ground = Color(red: 0.067, green: 0.067, blue: 0.078)
    public static let darkText = Color(red: 0.1, green: 0.1, blue: 0.1)

    public var showsFrame: Bool { self == .outline }
    public var showsBadgePill: Bool { self == .outline }

    public func groundColor(for state: CueState) -> Color {
        self == .fullscreen && state != .off ? state.color : Self.ground
    }

    public func frameColor(for state: CueState) -> Color? {
        guard showsFrame else { return nil }
        return state == .off ? Color.white.opacity(0.06) : state.color
    }

    public var cardFill: Color {
        self == .fullscreen ? Color.black.opacity(0.28) : Color.white.opacity(0.1)
    }

    public func primaryText(for state: CueState) -> Color {
        self == .fullscreen && state != .off ? Self.darkText : .white
    }

    public func secondaryText(for state: CueState, opacity: Double) -> Color {
        primaryText(for: state).opacity(opacity)
    }
}

struct PagerChromeSizes: Equatable {
    let timeFont: CGFloat
    let timeCaptionFont: CGFloat
    let badgeFont: CGFloat
    let topRowHeight: CGFloat
    let slotWidth: CGFloat
    let statusFont: CGFloat
    let roleFont: CGFloat
    let margin: CGFloat
    let cornerRadius: CGFloat
}

struct PagerTopRow<RoleMenu: View>: View {
    let sizes: PagerChromeSizes
    let state: CueState
    let style: CueDisplayStyle
    let roleName: String
    let roleColumnMaxWidth: CGFloat
    let roleMenu: RoleMenu

    private var cueWord: String { PagerPresentationState.cueWordText(for: state) }

    var body: some View {
        HStack(alignment: .top, spacing: sizes.margin) {
            ZStack(alignment: .topLeading) {
                clock.opacity(cueWord.isEmpty ? 1 : 0)
                badge
            }
            .frame(width: sizes.slotWidth, alignment: .leading)

            Spacer(minLength: 0)

            roleColumn
                .frame(maxWidth: roleColumnMaxWidth, alignment: .trailing)
        }
        .frame(height: sizes.topRowHeight, alignment: .top)
    }

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: sizes.timeCaptionFont * 0.2) {
                Text(context.date, format: .dateTime.hour().minute().second())
                    .font(.inter(size: sizes.timeFont, weight: .black))
                    .monospacedDigit()
                    .foregroundColor(Color(white: 0.96))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("LOCAL TIME")
                    .font(.inter(size: sizes.timeCaptionFont, weight: .bold))
                    .tracking(sizes.timeCaptionFont * 0.25)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func badgeLabel(_ word: String) -> some View {
        Text(word)
            .font(.inter(size: sizes.badgeFont, weight: .black))
            .foregroundColor(CueDisplayStyle.darkText)
            .lineLimit(1)
            .padding(.horizontal, style.showsBadgePill ? sizes.badgeFont * 0.3 : 0)
            .padding(.vertical, style.showsBadgePill ? sizes.badgeFont * 0.08 : 0)
    }

    private var badge: some View {
        ZStack(alignment: .topLeading) {
            badgeLabel(PagerChromeConstants.widestCueWord).hidden()
            if !cueWord.isEmpty {
                if style.showsBadgePill {
                    badgeLabel(cueWord)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(state.color)
                        .clipShape(RoundedRectangle(cornerRadius: sizes.cornerRadius, style: .continuous))
                } else {
                    badgeLabel(cueWord)
                }
            }
        }
        .fixedSize()
        .frame(height: sizes.topRowHeight, alignment: .top)
    }

    private var roleColumn: some View {
        VStack(alignment: .trailing, spacing: sizes.margin * 0.2) {
            Menu {
                roleMenu
            } label: {
                HStack(spacing: sizes.roleFont * 0.35) {
                    Text(roleName)
                        .font(.inter(size: sizes.roleFont, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Image(systemName: "chevron.down")
                        .font(.system(size: sizes.roleFont * 0.6, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, sizes.roleFont * 0.5)
                .padding(.vertical, sizes.roleFont * 0.25)
                .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: sizes.cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: sizes.cornerRadius, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

public enum DisconnectPhase: Equatable, Sendable {
    case live
    case dimmed
    case extended

    public static let extendedThreshold: TimeInterval = 20

    public init(elapsedSinceLive: TimeInterval?) {
        guard let elapsed = elapsedSinceLive, elapsed > 0 else {
            self = .live
            return
        }
        self = elapsed >= Self.extendedThreshold ? .extended : .dimmed
    }
}

public enum PagerConnectionState: Equatable, Sendable {
    case live
    case disconnected
    case notConnected

    public init(isProducerLive: Bool, isLANConnected: Bool) {
        if isProducerLive {
            self = .live
        } else {
            self = isLANConnected ? .disconnected : .notConnected
        }
    }

    public var title: String {
        switch self {
        case .live: return "Live"
        case .disconnected: return "Disconnected — retrying…"
        case .notConnected: return "Not connected"
        }
    }
}

struct PagerFooter: View {
    let footerHeight: CGFloat
    let buttonSide: CGFloat
    let trailingInset: CGFloat
    let leadingInset: CGFloat
    let bottomInset: CGFloat
    let noticeFont: CGFloat
    let style: CueDisplayStyle
    let state: CueState
    let showsNotice: Bool
    let showMessages: () -> Void
    let showSettings: () -> Void

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                if showsNotice {
                    Label("No connection", systemImage: "wifi.slash")
                        .font(.inter(size: noticeFont, weight: .bold))
                        .foregroundColor(style.secondaryText(for: state, opacity: 0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                footerButton("bubble.left.and.bubble.right", label: "Messages", action: showMessages)
                footerButton("gearshape", label: "Settings", action: showSettings)
            }
            .frame(height: footerHeight)
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .padding(.bottom, bottomInset)
        }
    }

    private func footerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: footerHeight * 0.7))
                .foregroundColor(style.secondaryText(for: state, opacity: 0.75))
                .frame(width: buttonSide, height: buttonSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct PagerDisconnectOverlay: View {
    let phase: DisconnectPhase

    var body: some View {
        switch phase {
        case .live:
            EmptyView()
        case .dimmed:
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        case .extended:
            PagerWaitingView()
        }
    }
}

enum PagerChromeConstants {
    static let widestCueWord = "STANDBY"
}

struct PagerMessagePanel: View {
    let message: InterTeamMessage
    let fontSize: CGFloat
    let captionFontSize: CGFloat
    let maxLines: Int
    let maxHeight: CGFloat
    let padding: CGFloat
    let cornerRadius: CGFloat
    let openMessage: () -> Void
    let dismissMessage: () -> Void
    @State private var dragOffset: CGFloat = 0

    private var opacity: Double {
        1.0 - min(Double(abs(dragOffset)) / 200.0, 1.0) * 0.7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: captionFontSize * 0.3) {
            Text(message.sender.uppercased())
                .font(.inter(size: captionFontSize, weight: .heavy))
                .tracking(captionFontSize * 0.15)
                .foregroundColor(CueDisplayStyle.darkText.opacity(0.7))
                .lineLimit(1)
            Text(message.text)
                .font(.inter(size: fontSize, weight: .bold))
                .foregroundColor(CueDisplayStyle.darkText)
                .multilineTextAlignment(.leading)
                .lineLimit(maxLines)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.yellow)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .offset(x: dragOffset)
        .opacity(opacity)
        .contentShape(Rectangle())
        #if os(iOS) || os(macOS)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    let distance = abs(value.translation.width)
                    if distance > 80 {
                        let direction: CGFloat = value.translation.width > 0 ? 1 : -1
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffset = direction * 500
                        }
                        dismissMessage()
                    } else if distance < 10 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                        openMessage()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
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
}
