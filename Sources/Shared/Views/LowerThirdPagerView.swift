// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public enum PagerLayoutChoice: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case lowerThird

    public static let storageKey = "pagerLayout"
    public static let defaultChoice: PagerLayoutChoice = .automatic
    public static let lowerThirdAspect: CGFloat = 3

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .lowerThird: return "Lower third"
        }
    }

    public static func resolve(_ raw: String) -> PagerLayoutChoice {
        PagerLayoutChoice(rawValue: raw) ?? defaultChoice
    }

    public func usesLowerThird(for size: CGSize) -> Bool {
        switch self {
        case .lowerThird: return true
        case .automatic: return size.height > 0 && size.width / size.height >= Self.lowerThirdAspect
        }
    }
}

public struct LowerThirdMetrics: Equatable, Sendable {
    public let size: CGSize

    public init(size: CGSize) {
        self.size = size
    }

    public var frameThickness: CGFloat { max(6, 0.05 * size.height) }
    public var inset: CGFloat { frameThickness + 0.08 * size.height }
    public var contentHeight: CGFloat { max(1, size.height - 2 * inset) }
    public var fontSize: CGFloat { max(10, min(0.55 * contentHeight, 0.068 * size.width)) }
    public var tagFontSize: CGFloat { max(8, 0.26 * fontSize) }
    public var gap: CGFloat { 0.25 * fontSize }
    public var cornerRadius: CGFloat { 0.2 * fontSize }
    public var frameCornerRadius: CGFloat { max(10, 0.12 * size.height) }
    public var controlFontSize: CGFloat { max(12, min(0.16 * size.height, 22)) }
}

public struct LowerThirdPagerView<RoleMenu: View>: View {
    let size: CGSize
    let presentation: PagerPresentationState
    let disconnectPhase: DisconnectPhase
    let standingMessage: InterTeamMessage?
    let showMessages: () -> Void
    let showSettings: () -> Void
    let openMessage: () -> Void
    let dismissMessage: () -> Void
    let roleMenu: RoleMenu
    @AppStorage(CueDisplayStyle.storageKey) private var cueDisplayRaw: String = CueDisplayStyle.defaultStyle.rawValue
    @State private var showsControls = false

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

    private var metrics: LowerThirdMetrics { LowerThirdMetrics(size: size) }
    private var state: CueState { presentation.currentState }
    private var style: CueDisplayStyle { CueDisplayStyle.resolve(cueDisplayRaw) }
    private var cueWord: String { PagerPresentationState.cueWordText(for: state) }

    public var body: some View {
        let m = metrics
        ZStack {
            style.groundColor(for: state).ignoresSafeArea()

            strip(m)
                .padding(.horizontal, m.inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(disconnectPhase == .extended ? 0 : 1)

            PagerDisconnectOverlay(phase: disconnectPhase)

            if showsControls && disconnectPhase != .extended {
                controls(m)
            }

            if let frame = style.frameColor(for: state) {
                FrameShape(thickness: m.frameThickness, radius: m.frameCornerRadius)
                    .fill(frame, style: FillStyle(eoFill: true))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showsControls.toggle() }
        .task(id: showsControls) {
            guard showsControls else { return }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled { showsControls = false }
        }
    }

    private func strip(_ m: LowerThirdMetrics) -> some View {
        let primary = style.primaryText(for: state)
        let item = presentation.activeTimerItem
        return HStack(alignment: .center, spacing: m.gap) {
            if standingMessage == nil {
                clockBlock(m, primary: primary)
            }

            if let message = standingMessage {
                messageCard(message, m)
            } else {
                Text((item?.title ?? presentation.connectedMasterName ?? "—").uppercased())
                    .font(.inter(size: m.fontSize * 0.6, weight: .black))
                    .foregroundColor(primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .padding(.horizontal, m.fontSize * 0.22)
                    .padding(.vertical, m.fontSize * 0.12)
                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: m.cornerRadius, style: .continuous))
                    .frame(maxWidth: .infinity)
            }

            countdownBlock(m, item: item, primary: primary)
        }
    }

    private func clockBlock(_ m: LowerThirdMetrics, primary: Color) -> some View {
        VStack(alignment: .leading, spacing: m.tagFontSize * 0.3) {
            ZStack(alignment: .leading) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date, format: .dateTime.hour().minute().second())
                        .font(.inter(size: m.fontSize, weight: .black))
                        .monospacedDigit()
                        .foregroundColor(primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .opacity(cueWord.isEmpty ? 1 : 0)

                if !cueWord.isEmpty {
                    Text(cueWord)
                        .font(.inter(size: m.fontSize, weight: .black))
                        .foregroundColor(CueDisplayStyle.darkText)
                        .lineLimit(1)
                        .padding(.horizontal, style.showsBadgePill ? m.fontSize * 0.2 : 0)
                        .background(style.showsBadgePill ? state.color : Color.clear, in: RoundedRectangle(cornerRadius: m.cornerRadius, style: .continuous))
                }
            }
            Text("LOCAL TIME")
                .font(.inter(size: m.tagFontSize, weight: .bold))
                .tracking(m.tagFontSize * 0.15)
                .foregroundColor(style.secondaryText(for: state, opacity: 0.85))
                .opacity(cueWord.isEmpty ? 1 : 0)
        }
        .fixedSize()
    }

    private func countdownBlock(_ m: LowerThirdMetrics, item: PCOTimerItem?, primary: Color) -> some View {
        let hasCountdown = item.map { !$0.isHeader } ?? false
        let text = hasCountdown
            ? TimeFormatting.string(forSeconds: item?.remainingSeconds ?? 0, threshold: presentation.hourFormatThreshold)
            : "--:--"
        return VStack(alignment: .trailing, spacing: m.tagFontSize * 0.3) {
            Text(text)
                .font(.inter(size: m.fontSize, weight: .black))
                .monospacedDigit()
                .foregroundColor(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text((item?.isDurationActual ?? false) ? "ACTUAL" : "PROJECTED")
                .font(.inter(size: m.tagFontSize, weight: .bold))
                .tracking(m.tagFontSize * 0.15)
                .foregroundColor(style.secondaryText(for: state, opacity: 0.85))
                .opacity(hasCountdown ? 1 : 0)
        }
        .fixedSize()
    }

    private func messageCard(_ message: InterTeamMessage, _ m: LowerThirdMetrics) -> some View {
        Button(action: openMessage) {
            Text(message.text)
                .font(.inter(size: m.fontSize * 0.55, weight: .black))
                .foregroundColor(.black)
                .lineLimit(2)
                .minimumScaleFactor(0.3)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, m.fontSize * 0.25)
                .padding(.vertical, m.fontSize * 0.12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 1, green: 0.84, blue: 0.04), in: RoundedRectangle(cornerRadius: m.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Dismiss", action: dismissMessage)
        }
        .id(message.id)
    }

    private func controls(_ m: LowerThirdMetrics) -> some View {
        VStack {
            HStack(spacing: m.controlFontSize * 0.6) {
                Spacer(minLength: 0)
                Menu {
                    roleMenu
                } label: {
                    HStack(spacing: m.controlFontSize * 0.35) {
                        Text(presentation.activeRole?.name ?? "Host Pager")
                            .font(.inter(size: m.controlFontSize, weight: .bold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: m.controlFontSize * 0.6, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, m.controlFontSize * 0.6)
                    .padding(.vertical, m.controlFontSize * 0.3)
                    .background(Color.black.opacity(0.7), in: Capsule())
                }
                .buttonStyle(.plain)

                controlButton("bubble.left.and.bubble.right", label: "Messages", m, action: showMessages)
                controlButton("gearshape", label: "Settings", m, action: showSettings)
            }
            .padding(m.frameThickness + m.controlFontSize * 0.3)
            Spacer(minLength: 0)
        }
    }

    private func controlButton(_ symbol: String, label: String, _ m: LowerThirdMetrics, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: m.controlFontSize))
                .foregroundColor(.white)
                .padding(m.controlFontSize * 0.4)
                .background(Color.black.opacity(0.7), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
