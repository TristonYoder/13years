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
    @AppStorage(PagerDetailsSplit.storageKey) private var detailsSplit: Double = PagerDetailsSplit.defaultFraction
    @StateObject private var itemDetailsStore = PagerItemDetailsStore()

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
            clockFormat: engine.displayClockFormat,
            receivedNextItem: engine.nextItem,
            producerClockOffsetMs: engine.producerClockOffsetMs,
            producerUTCOffsetSeconds: engine.producerUTCOffsetSeconds,
            nextItemStartDate: engine.nextItemStartDate
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

    private struct DetailsFetchKey: Hashable {
        var itemId: String?
        var host: String?
        var port: Int?
    }

    private var holdsFullItemDetails: Bool { engine.isMasterServer || engine.isRemoteMirror }

    private var itemDetailsSource: String? {
        guard presentation.wantsItemDetails, let item = presentation.activeTimerItem else { return nil }
        return presentation.localItemDetailsSource(includingDescription: holdsFullItemDetails)
            ?? itemDetailsStore.source(for: item.id)
    }

    private var detailsFetchKey: DetailsFetchKey {
        guard presentation.wantsItemDetails, !holdsFullItemDetails,
              let item = presentation.activeTimerItem, !item.isHeader,
              presentation.localItemDetailsSource(includingDescription: false) == nil else {
            return DetailsFetchKey(itemId: nil, host: nil, port: nil)
        }
        return DetailsFetchKey(itemId: item.id, host: engine.connectedProducerHost, port: engine.connectedProducerAPIPort ?? Int(ControlAPIServer.defaultPort))
    }

    private var pagerView: some View {
        pagerLayouts
            .pagerStaleLook(disconnectPhase)
            .task(id: detailsFetchKey) {
                let key = detailsFetchKey
                guard let itemId = key.itemId, let host = key.host, let port = key.port else {
                    itemDetailsStore.reset()
                    return
                }
                await itemDetailsStore.run(itemId: itemId, host: host, port: port)
            }
            .sheet(isPresented: $isShowingSettings) {
                PagerSettingsView()
            }
    }

    private var pagerLayouts: some View {
        GeometryReader { geo in
            #if os(tvOS)
            landscapeView(size: geo.size)
            #else
            switch PagerLayoutChoice.resolve(layoutRaw).layout(for: geo.size) {
            case .lowerThird: lowerThirdView(size: geo.size)
            case .landscape: landscapeView(size: geo.size)
            case .portrait: portraitView(size: geo.size)
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
        .onScreenshotTourSignal("pager.chat") { _ in isShowingChat = true }
        .onScreenshotTourSignal("pager.settings") { _ in isShowingSettings = true }
        .onScreenshotTourSignal("pager.dismiss") { _ in
            isShowingChat = false
            isShowingSettings = false
        }
        .sheet(isPresented: $isShowingChat) {
            PagerChatView(roleId: selectedRoleId, roleName: activeRole?.name ?? "Host")
        }
    }

    @ViewBuilder
    private func landscapeView(size: CGSize) -> some View {
        if let html = itemDetailsSource, let itemId = presentation.activeTimerItem?.id, PagerDetailsSplit.isSplitLayout(size) {
            PagerDetailsSplitView(
                size: size,
                html: html,
                itemId: itemId,
                detailsVisible: disconnectPhase != .extended,
                fraction: $detailsSplit
            ) { pagerSize in
                splitPager(size: pagerSize)
            }
        } else {
            landscapePager(size: size)
        }
    }

    @ViewBuilder
    private func splitPager(size: CGSize) -> some View {
        switch PagerLayoutChoice.resolve(layoutRaw).splitPagerLayout(for: size) {
        case .portrait: portraitView(size: size)
        case .landscape, .lowerThird: landscapePager(size: size)
        }
    }

    private func landscapePager(size: CGSize) -> some View {
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
