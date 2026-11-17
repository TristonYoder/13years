// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

struct PagerMenuBarPanel: View {
    @EnvironmentObject private var engine: CueEngine
    @AppStorage(PagerMenuBarPreferences.selectedRoleKey) private var selectedRoleId = "default"
    let openPager: () -> Void
    let openSettings: () -> Void

    static let width: CGFloat = 300
    private let margin: CGFloat = 12
    private let radius: CGFloat = 10

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

    private var disconnectPhase: DisconnectPhase {
        DisconnectPhase(signal: engine.producerSignal)
    }

    private var isConnected: Bool {
        engine.hasSyncedWithProducer && disconnectPhase != .extended
    }

    var body: some View {
        let p = presentation
        VStack(spacing: margin) {
            topRow(p)
            if isConnected {
                if let item = p.activeTimerItem {
                    currentCard(p, item: item)
                }
                if let next = p.nextItem {
                    nextCard(p, next: next)
                }
            } else {
                noConnection
            }
            if let message = PagerMenuBarReadState.incoming(in: p.recentMessages, roleId: selectedRoleId).first {
                messageCard(message)
            }
            footer
        }
        .padding(margin + 4)
        .frame(width: Self.width)
        .background(AppPalette.pagerGround)
        .overlay {
            if isConnected, p.currentState != .off {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(p.currentState.color, lineWidth: 4)
            }
        }
        .environment(\.colorScheme, .dark)
    }


    private func topRow(_ p: PagerPresentationState) -> some View {
        HStack(alignment: .center, spacing: margin) {
            if isConnected, p.currentState != .off {
                Text(PagerPresentationState.cueWordText(for: p.currentState))
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(CueDisplayStyle.darkText)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(p.currentState.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ProducerClockText(
                        info: p.producerClock,
                        format: p.clockFormat,
                        font: .inter(size: 18, weight: .black),
                        color: AppPalette.pagerClock
                    )
                    Text("LOCAL TIME")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
            roleMenu(p)
        }
    }

    private func roleMenu(_ p: PagerPresentationState) -> some View {
        Menu {
            ForEach(p.roles) { role in
                Button(role.name) { selectedRoleId = role.id }
            }
        } label: {
            HStack(spacing: 4) {
                Text(p.activeRole?.name ?? "Host Pager")
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(.white)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }


    private func currentCard(_ p: PagerPresentationState, item: PCOTimerItem) -> some View {
        VStack(spacing: 4) {
            Text(item.title.uppercased())
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if !item.isHeader {
                Text(TimeFormatting.string(forSeconds: item.remainingSeconds, threshold: p.hourFormatThreshold))
                    .font(.inter(size: 52, weight: .black))
                    .monospacedDigit()
                    .foregroundColor(item.remainingSeconds < 0 ? AppPalette.negative : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(item.isDurationActual ? "ACTUAL" : "PROJECTED")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.5))
                if let details = p.currentDetailsLine() {
                    Text(details)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if !p.currentNotes.isEmpty {
                    Rectangle()
                        .fill(AppPalette.glassMedium)
                        .frame(height: 1)
                        .padding(.vertical, 4)
                    notes(p.currentNotes, weight: .bold, opacity: 1)
                }
            }
        }
        .padding(margin)
        .frame(maxWidth: .infinity)
        .background(CueDisplayStyle.outline.cardFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func nextCard(_ p: PagerPresentationState, next: PCOTimerItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(next.title.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !next.isHeader {
                    Text(TimeFormatting.string(forSeconds: next.lengthInSeconds, threshold: p.hourFormatThreshold))
                        .font(.inter(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            notes(p.nextNotes, weight: .medium, opacity: 0.85)
        }
        .padding(margin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CueDisplayStyle.outline.cardFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func notes(_ notes: [(category: String, text: String)], weight: Font.Weight, opacity: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(notes, id: \.category) { note in
                PagerNoteText.line(category: note.category, text: note.text)
                    .font(.system(size: 11, weight: weight))
                    .foregroundColor(.white.opacity(opacity))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func messageCard(_ message: InterTeamMessage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if message.isHighPriority {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                Text(message.sender.uppercased())
                    .tracking(1.2)
                Spacer(minLength: 0)
                Text(message.timestamp, style: .time)
            }
            .font(.system(size: 9, weight: .heavy))
            .foregroundColor(CueDisplayStyle.darkText.opacity(0.7))
            .lineLimit(1)
            Text(message.text)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(CueDisplayStyle.darkText)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(margin)
        .background(AppPalette.pagerMessage, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var noConnection: some View {
        VStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 20, weight: .bold))
            Text("NO CONNECTION")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
            Text("Looking for the producer…")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
        .foregroundColor(.white.opacity(0.85))
        .frame(maxWidth: .infinity)
        .padding(.vertical, margin)
    }


    private var footer: some View {
        HStack(spacing: 14) {
            Button("Open Pager", action: openPager)
            Spacer(minLength: 0)
            Button(action: openSettings) {
                Image(systemName: "gearshape.fill")
            }
            .help("Settings")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit 13 Years")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.white.opacity(0.7))
    }
}
