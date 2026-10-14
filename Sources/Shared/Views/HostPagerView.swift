// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct HostPagerView: View {
    @EnvironmentObject var engine: CueEngine
    @AppStorage("pagerSelectedRoleId") private var selectedRoleId: String = "default"
    @State private var isShowingChat = false
    @State private var isShowingSettings = false
    @State private var dismissedMessageId: String?
    @State private var lastSeenMessageId: String?
    @AppStorage(PagerLayoutChoice.storageKey) private var layoutRaw: String = PagerLayoutChoice.defaultChoice.rawValue

    public init() {}

    private var presentation: PagerPresentationState {
        PagerPresentationState(
            roles: engine.roles,
            planItems: engine.planItems,
            activeItemIndex: engine.activeItemIndex,
            activeTimerItem: engine.activeTimerItem,
            recentMessages: engine.recentMessages,
            selectedRoleId: selectedRoleId,
            isProducerLive: engine.isProducerLive,
            isLANConnected: engine.isLANConnected,
            connectedMasterName: engine.connectedMasterName,
            hourFormatThreshold: engine.hourFormatThreshold,
            receivedNextItem: engine.nextItem
        )
    }

    private var activeRole: RoleCue? { presentation.activeRole }

    private var currentState: CueState { presentation.currentState }

    private var latestRelevantMessage: InterTeamMessage? { presentation.latestRelevantMessage }

    public var body: some View {
        if !engine.hasSyncedWithProducer && !engine.isMasterServer {
            PagerWaitingView()
        } else {
            pagerView
        }
    }

    private var disconnectPhase: DisconnectPhase {
        DisconnectPhase(signal: engine.isMasterServer ? .live : engine.producerSignal)
    }

    private var pagerView: some View {
        pagerLayouts
            .pagerStaleLook(disconnectPhase)
            .sheet(isPresented: $isShowingSettings) {
                PagerSettingsView()
            }
    }

    private var pagerLayouts: some View {
        GeometryReader { geo in
            #if os(tvOS)
            landscapeView(size: geo.size)
            #else
            if PagerLayoutChoice.resolve(layoutRaw).usesLowerThird(for: geo.size) {
                lowerThirdView(size: geo.size)
            } else if !PortraitMetrics.isPortrait(geo.size) {
                landscapeView(size: geo.size)
            } else {
                portraitView(size: geo.size)
            }
            #endif
        }
        .onChange(of: currentState) { _, newState in
            PagerHaptics.shared.playCueTransition(for: newState)
        }
        .onChange(of: selectedRoleId) { _, _ in
            lastSeenMessageId = latestRelevantMessage?.id
        }
        .onChange(of: latestRelevantMessage?.id) { _, newId in
            guard let newId, newId != lastSeenMessageId else { return }
            lastSeenMessageId = newId
            guard let msg = latestRelevantMessage, msg.senderRoleId != selectedRoleId else { return }
            PagerHaptics.shared.playMessageReceived(for: currentState)
        }
        .onAppear {
            lastSeenMessageId = latestRelevantMessage?.id
            PagerHaptics.shared.prepareIfNeeded()
        }
        .sheet(isPresented: $isShowingChat) {
            PagerChatView(roleId: selectedRoleId, roleName: activeRole?.name ?? "Host")
        }
    }

    private func landscapeView(size: CGSize) -> some View {
        LandscapePagerView(
            size: size,
            presentation: presentation,
            disconnectPhase: disconnectPhase,
            standingMessage: visibleStandingMessage,
            showMessages: openChat,
            showSettings: { isShowingSettings = true },
            openMessage: openChat,
            dismissMessage: dismissStanding,
            roleMenu: { roleMenuItems }
        )
    }

    private func lowerThirdView(size: CGSize) -> some View {
        LowerThirdPagerView(
            size: size,
            presentation: presentation,
            disconnectPhase: disconnectPhase,
            standingMessage: visibleStandingMessage,
            showMessages: openChat,
            showSettings: { isShowingSettings = true },
            openMessage: openChat,
            dismissMessage: dismissStanding,
            roleMenu: { roleMenuItems }
        )
    }

    private func portraitView(size: CGSize) -> some View {
        PortraitPagerView(
            size: size,
            presentation: presentation,
            disconnectPhase: disconnectPhase,
            standingMessage: visibleStandingMessage,
            showMessages: openChat,
            showSettings: { isShowingSettings = true },
            openMessage: openChat,
            dismissMessage: dismissStanding,
            roleMenu: { roleMenuItems }
        )
    }

    private var visibleStandingMessage: InterTeamMessage? {
        latestRelevantMessage.flatMap { $0.id == dismissedMessageId ? nil : $0 }
    }

    private func openChat() {
        isShowingChat = true
        dismissedMessageId = latestRelevantMessage?.id
    }

    private func dismissStanding() {
        dismissedMessageId = latestRelevantMessage?.id
    }

    @ViewBuilder
    private var roleMenuItems: some View {
        ForEach(presentation.roles) { role in
            Button(role.name) {
                selectedRoleId = role.id
            }
        }
    }
}
