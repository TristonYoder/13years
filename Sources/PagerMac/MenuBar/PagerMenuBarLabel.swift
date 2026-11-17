// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

struct PagerMenuBarLabel: View {
    @EnvironmentObject private var engine: CueEngine
    @EnvironmentObject private var readState: PagerMenuBarReadState
    @AppStorage(PagerMenuBarPreferences.selectedRoleKey) private var selectedRoleId = "default"
    @AppStorage(PagerMenuBarPreferences.showItemNameKey) private var showItemName = true
    @AppStorage(PagerMenuBarPreferences.showUnreadBadgeKey) private var showUnreadBadge = true
    @AppStorage(PagerMenuBarPreferences.priorityTakeoverKey) private var priorityTakeover = true

    static let titleMaxWidth: CGFloat = 150
    static let messageMaxWidth: CGFloat = 260

    private var roleState: CueState {
        let role = engine.roles.first(where: { $0.id == selectedRoleId }) ?? engine.roles.first
        return role?.state ?? .off
    }

    private var unread: [InterTeamMessage] {
        readState.unread(in: engine.recentMessages, roleId: selectedRoleId)
    }

    private var disconnectPhase: DisconnectPhase {
        DisconnectPhase(signal: engine.producerSignal)
    }

    var body: some View {
        content
            .padding(.horizontal, 2)
            .frame(height: NSStatusBar.system.thickness)
            .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        if priorityTakeover, let urgent = unread.first(where: \.isHighPriority) {
            urgentPill(urgent)
        } else if !engine.hasSyncedWithProducer || disconnectPhase == .extended {
            HStack(spacing: 5) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 11, weight: .bold))
                Text("--:--")
                    .font(.inter(size: 13, weight: .black))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                if roleState != .off {
                    cuePill(roleState)
                }
                if let item = engine.activeTimerItem {
                    if showItemName || item.isHeader {
                        Text(item.title.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.3)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: Self.titleMaxWidth, alignment: .leading)
                    }
                    if !item.isHeader {
                        countdown(item)
                    }
                }
                if showUnreadBadge, !unread.isEmpty {
                    unreadBadge(unread.count)
                }
            }
            .opacity(disconnectPhase == .dimmed ? 0.55 : 1)
        }
    }

    private func cuePill(_ state: CueState) -> some View {
        Text(PagerPresentationState.cueWordText(for: state))
            .font(.system(size: 11, weight: .black))
            .foregroundColor(CueDisplayStyle.darkText)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(state.color, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func countdown(_ item: PCOTimerItem) -> some View {
        Text(TimeFormatting.string(forSeconds: item.remainingSeconds, threshold: engine.hourFormatThreshold))
            .font(.inter(size: 13, weight: .black))
            .monospacedDigit()
            .foregroundStyle(item.remainingSeconds < 0 ? AnyShapeStyle(AppPalette.negative) : AnyShapeStyle(.primary))
            .lineLimit(1)
    }

    private func unreadBadge(_ count: Int) -> some View {
        Text(count > 9 ? "9+" : "\(count)")
            .font(.inter(size: 10, weight: .black))
            .monospacedDigit()
            .foregroundColor(CueDisplayStyle.darkText)
            .padding(.horizontal, 5)
            .frame(minWidth: 16, minHeight: 16)
            .background(AppPalette.pagerMessage, in: Capsule())
    }

    private func urgentPill(_ message: InterTeamMessage) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .heavy))
            Text(message.text)
                .font(.system(size: 11.5, weight: .bold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundColor(CueDisplayStyle.darkText)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(maxWidth: Self.messageMaxWidth)
        .background(AppPalette.pagerMessage, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
