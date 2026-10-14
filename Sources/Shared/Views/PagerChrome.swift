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

    static let iconRowHeight: CGFloat = 44

    var headerHeight: CGFloat {
        max(topRowHeight, roleFont * 1.6 + margin * 0.2 + Self.iconRowHeight)
    }
}

struct PagerTopRow<RoleMenu: View>: View {
    let sizes: PagerChromeSizes
    let state: CueState
    let style: CueDisplayStyle
    let roleName: String
    let roleColumnMaxWidth: CGFloat
    let hidesLeading: Bool
    let showMessages: () -> Void
    let showSettings: () -> Void
    let roleMenu: RoleMenu

    private var cueWord: String { PagerPresentationState.cueWordText(for: state) }

    var body: some View {
        HStack(alignment: .top, spacing: sizes.margin) {
            ZStack(alignment: .topLeading) {
                clock.opacity(cueWord.isEmpty ? 1 : 0)
                badge
            }
            .frame(width: sizes.slotWidth, alignment: .leading)
            .opacity(hidesLeading ? 0 : 1)

            Spacer(minLength: 0)

            roleColumn
                .frame(maxWidth: roleColumnMaxWidth, alignment: .trailing)
        }
        .frame(height: sizes.headerHeight, alignment: .top)
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
        ChipMatchedColumn(spacing: sizes.margin * 0.2) {
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
            #if os(tvOS)
            .buttonStyle(.card)
            #else
            .buttonStyle(.plain)
            #endif

            PagerHeaderIcons(sizes: sizes, style: style, state: state, showMessages: showMessages, showSettings: showSettings)
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

public enum PagerLinkIndicator: Equatable, Sendable {
    case live
    case waitingForProducer
    case connecting(host: String)
    case problem(String)
    case notConnected

    public init(isMasterServer: Bool, isLANConnected: Bool, isProducerLive: Bool, link: ProducerLinkStatus) {
        if isMasterServer {
            self = .live
            return
        }
        if link.isProblem, let message = link.message {
            self = .problem(message)
            return
        }
        guard isLANConnected else {
            if case .connecting(let host) = link {
                self = .connecting(host: host)
            } else {
                self = .notConnected
            }
            return
        }
        self = isProducerLive ? .live : .waitingForProducer
    }

    public var title: String {
        switch self {
        case .live: return "Live"
        case .waitingForProducer: return "Connected, waiting for producer"
        case .connecting(let host): return "Connecting to \(host)…"
        case .problem(let message): return message
        case .notConnected: return "Not connected"
        }
    }

    public var tint: Color {
        switch self {
        case .live: return .green
        case .waitingForProducer, .connecting: return .orange
        case .problem, .notConnected: return .red
        }
    }

    public var isLinked: Bool {
        switch self {
        case .live, .waitingForProducer: return true
        default: return false
        }
    }
}

struct ChipMatchedColumn: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let chip = subviews[0].sizeThatFits(proposal)
        let row = subviews[1].sizeThatFits(ProposedViewSize(width: chip.width, height: nil))
        return CGSize(width: chip.width, height: chip.height + spacing + row.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let chip = subviews[0].sizeThatFits(proposal)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(chip))
        let row = subviews[1].sizeThatFits(ProposedViewSize(width: chip.width, height: nil))
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + chip.height + spacing),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: chip.width, height: row.height)
        )
    }
}

struct PagerHeaderIcons: View {
    let sizes: PagerChromeSizes
    let style: CueDisplayStyle
    let state: CueState
    let showMessages: () -> Void
    let showSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            button("bubble.left.and.bubble.right", label: "Messages", action: showMessages)
            button("gearshape", label: "Settings", action: showSettings)
        }
        .frame(height: PagerChromeSizes.iconRowHeight)
    }

    private func button(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: sizes.roleFont * 0.9))
                .foregroundColor(style.secondaryText(for: state, opacity: 0.8))
                .frame(maxWidth: .infinity, minHeight: PagerChromeSizes.iconRowHeight, maxHeight: PagerChromeSizes.iconRowHeight)
                .contentShape(Rectangle())
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel(label)
    }
}

struct PagerNoConnectionNotice: View {
    let font: CGFloat
    let bottomInset: CGFloat
    let style: CueDisplayStyle
    let state: CueState

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            Label("No connection", systemImage: "wifi.slash")
                .font(.inter(size: font, weight: .bold))
                .foregroundColor(style.secondaryText(for: state, opacity: 0.85))
                .lineLimit(1)
                .padding(.bottom, bottomInset)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
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
