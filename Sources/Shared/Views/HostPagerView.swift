// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct HostPagerView: View {
    @EnvironmentObject var engine: CueEngine
    @State private var selectedRoleId: String = "default"
    @State private var isShowingChat = false
    @State private var dismissedMessageId: String?
    @State private var bannerDragOffset: CGFloat = 0
    @State private var lastSeenMessageId: String?

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
            hourFormatThreshold: engine.hourFormatThreshold
        )
    }

    private var activeRole: RoleCue? { presentation.activeRole }

    private var currentState: CueState { presentation.currentState }

    private var assignedNoteCategories: [String] { presentation.assignedNoteCategories }

    private var currentNotes: [(category: String, text: String)] { presentation.currentNotes }

    private var nextItem: PCOTimerItem? { presentation.nextItem }

    private var nextNotes: [(category: String, text: String)] { presentation.nextNotes }

    private var latestRelevantMessage: InterTeamMessage? { presentation.latestRelevantMessage }

    public var body: some View {
        if !engine.hasSyncedWithProducer && !engine.isMasterServer {
            PagerWaitingView()
        } else {
            pagerView
        }
    }

    private var pagerView: some View {
        ZStack {
            currentState.color.ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Menu {
                        ForEach(presentation.roles) { role in
                            Button(role.name) {
                                selectedRoleId = role.id
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(activeRole?.name ?? "Host Pager")
                                .font(.inter(size: 14, weight: .bold))
                            Image(systemName: "chevron.down")
                                .font(.inter(size: 12))
                        }
                        .foregroundColor(currentState.textColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(8)
                    }

                    Spacer()

                    if engine.isMasterServer {
                        EmptyView()
                    } else if engine.isProducerLive, let master = engine.connectedMasterName {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Live — \(master)")
                                .font(.inter(size: 11, weight: .semibold))
                        }
                        .foregroundColor(currentState.textColor.opacity(0.8))
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text(engine.isLANConnected ? "Disconnected — retrying…" : "Not connected — retrying…")
                                .font(.inter(size: 11, weight: .semibold))
                        }
                        .foregroundColor(currentState.textColor.opacity(0.8))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                VStack(spacing: 12) {
                    Text(currentState.displayName.uppercased())
                        .font(.inter(size: 72, weight: .black))
                        .foregroundColor(currentState.textColor)
                        .minimumScaleFactor(0.5)

                    if let person = activeRole?.personName {
                        Text("FOR: \(person.uppercased())")
                            .font(.inter(size: 16, weight: .bold))
                            .foregroundColor(currentState.textColor.opacity(0.8))
                            .tracking(2.0)
                    }
                }

                Spacer()

                if let item = presentation.activeTimerItem {
                    VStack(spacing: 6) {
                        Text(item.title.uppercased())
                            .font(.inter(size: item.isHeader ? 22 : 16, weight: .bold))
                            .foregroundColor(currentState.textColor)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        if !item.isHeader {
                            Text(TimeFormatting.string(forSeconds: item.remainingSeconds, threshold: presentation.hourFormatThreshold))
                                .font(.inter(size: 54, weight: .black))
                                .foregroundColor(currentState.textColor)

                            Text(item.isDurationActual ? "ACTUAL" : "PROJECTED")
                                .font(.inter(size: 11, weight: .bold))
                                .tracking(1.5)
                                .foregroundColor(currentState.textColor.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(Color.black.opacity(0.25))
                    .cornerRadius(16)
                }

                if !currentNotes.isEmpty || !nextNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(currentNotes, id: \.category) { note in
                            notePanel(label: currentNotes.count > 1 ? "CURRENT — \(note.category.uppercased())" : "CURRENT", text: note.text, emphasized: true)
                        }
                        ForEach(nextNotes, id: \.category) { note in
                            notePanel(label: nextNotes.count > 1 ? "NEXT — \(note.category.uppercased())" : "NEXT", text: note.text, emphasized: false)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Spacer()

                if let latestMsg = latestRelevantMessage, latestMsg.id != dismissedMessageId {
                    HStack(spacing: 10) {
                        Image(systemName: "text.bubble.fill")
                            .font(.inter(size: 18))
                        Text(latestMsg.text)
                            .font(.inter(size: 18, weight: .bold))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.inter(size: 14))
                            .opacity(0.6)
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.yellow)
                    .cornerRadius(12)
                    .shadow(radius: 4)
                    .padding(.horizontal, 20)
                    .offset(x: bannerDragOffset)
                    .opacity(1 - min(abs(bannerDragOffset) / 200, 1) * 0.7)
                    .contentShape(Rectangle())
                    #if os(iOS) || os(macOS)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                bannerDragOffset = value.translation.width
                            }
                            .onEnded { value in
                                let distance = abs(value.translation.width)
                                if distance > 80 {
                                    let direction: CGFloat = value.translation.width > 0 ? 1 : -1
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        bannerDragOffset = direction * 500
                                    }
                                    dismissedMessageId = latestMsg.id
                                } else if distance < 10 {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        bannerDragOffset = 0
                                    }
                                    isShowingChat = true
                                    dismissedMessageId = latestMsg.id
                                } else {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        bannerDragOffset = 0
                                    }
                                }
                            }
                    )
                    #else
                    .onTapGesture {
                        isShowingChat = true
                        dismissedMessageId = latestMsg.id
                    }
                    .focusable(true)
                    #endif
                }

                Button {
                    isShowingChat = true
                    dismissedMessageId = latestRelevantMessage?.id
                } label: {
                    Label("Messages", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.inter(size: 15, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(currentState.textColor)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .onChange(of: currentState) { _, newState in
            PagerHaptics.shared.playCueTransition(for: newState)
        }
        .onChange(of: selectedRoleId) { _, _ in
            lastSeenMessageId = latestRelevantMessage?.id
        }
        .onChange(of: latestRelevantMessage?.id) { _, newId in
            bannerDragOffset = 0
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

    private func notePanel(label: String, text: String, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.inter(size: 11, weight: .heavy))
                .tracking(1.5)
                .foregroundColor(currentState.textColor.opacity(0.7))
            Text(text)
                .font(.inter(size: emphasized ? 18 : 15, weight: emphasized ? .bold : .medium))
                .foregroundColor(currentState.textColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(emphasized ? 0.3 : 0.18))
        .cornerRadius(12)
    }

}
