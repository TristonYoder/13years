// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

struct WatchCueView: View {
    @ObservedObject var model: WatchPagerModel

    @Environment(\.scenePhase) private var scenePhase

    @State private var showingRoles = false
    @State private var showingChat = false
    @State private var showingSettings = false

    private let isPagerModeEnabled = false
    private let showsNotes = false
    private let showsMessages = false

    private var isBasicTimerMode: Bool {
        !isPagerModeEnabled && !showsNotes && !showsMessages
    }

    private var presentation: PagerPresentationState? { model.presentation }
    private var currentState: CueState { model.currentState }
    private var activeRole: RoleCue? { model.activeRole }
    private var currentNotes: [(category: String, text: String)] { presentation?.currentNotes ?? [] }
    private var nextNotes: [(category: String, text: String)] { presentation?.nextNotes ?? [] }

    private var isTimerFresh: Bool {
        guard scenePhase == .active, let last = model.lastSuccessfulPollAt else { return false }
        return Date.now.timeIntervalSince(last) <= 4
    }

    private var backgroundColor: Color {
        isPagerModeEnabled ? currentState.color : CueState.off.color
    }

    private var contentTextColor: Color {
        isPagerModeEnabled ? currentState.textColor : CueState.off.textColor
    }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 10)
                    .padding(.top, 4)

                if isBasicTimerMode {
                    basicTimerBody
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            if isPagerModeEnabled {
                                stateBlock
                            }
                            if let item = presentation?.activeTimerItem {
                                itemBlock(item)
                            }
                            if showsNotes, !currentNotes.isEmpty || !nextNotes.isEmpty {
                                notesBlock
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 2)
                        .padding(.bottom, 6)
                    }
                }

                if showsMessages {
                    messagesBar
                        .padding(.bottom, 4)
                }
            }
        }
        .sheet(isPresented: $showingRoles) {
            roleSheet
        }
        .sheet(isPresented: $showingChat) {
            WatchChatView(model: model)
        }
        .sheet(isPresented: $showingSettings) {
            WatchSettingsView(model: model)
        }
    }

    private var basicTimerBody: some View {
        GeometryReader { geo in
            VStack(spacing: 2) {
                Spacer()
                timerDigits(geo: geo)
                Spacer()
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func timerDigits(geo: GeometryProxy) -> some View {
        let item = presentation?.activeTimerItem
        return Group {
            if let item, !item.isHeader {
                VStack(spacing: 4) {
                    Text(item.title.uppercased())
                        .font(.system(size: 20, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(countdownText(for: item))
                        .font(.inter(size: 54, weight: .black))
                        .monospacedDigit()
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                }
                .foregroundStyle(contentTextColor)
                .frame(width: geo.size.width)
            } else {
                Text("--:--")
                    .font(.inter(size: 54, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(contentTextColor)
            }
        }
    }

    private func countdownText(for item: PCOTimerItem) -> String {
        guard isTimerFresh else { return "--:--" }
        return TimeFormatting.string(forSeconds: item.remainingSeconds, threshold: presentation?.hourFormatThreshold ?? .over90Minutes)
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            if isPagerModeEnabled {
                Button {
                    showingRoles = true
                } label: {
                    HStack(spacing: 3) {
                        Text(activeRole?.name ?? "Pager")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(contentTextColor)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.18))
                .clipShape(Capsule())
            }

            Spacer()

            HStack(spacing: 3) {
                Circle()
                    .fill(model.isReachable ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(model.isReachable ? "Live" : "Offline")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(contentTextColor.opacity(0.85))

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(contentTextColor.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
    }

    private var stateBlock: some View {
        VStack(spacing: 2) {
            Text(currentState.displayName.uppercased())
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(contentTextColor)
                .minimumScaleFactor(0.4)
                .lineLimit(1)

            if let person = activeRole?.personName {
                Text("FOR: \(person.uppercased())")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(contentTextColor.opacity(0.8))
            }
        }
        .padding(.top, 6)
    }

    private func itemBlock(_ item: PCOTimerItem) -> some View {
        VStack(spacing: 2) {
            Text(item.title.uppercased())
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(contentTextColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if !item.isHeader, let threshold = presentation?.hourFormatThreshold {
                Text(TimeFormatting.string(forSeconds: item.remainingSeconds, threshold: threshold))
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(contentTextColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(item.isDurationActual ? "ACTUAL" : "PROJECTED")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(contentTextColor.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var notesBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(currentNotes, id: \.category) { note in
                notePanel(
                    label: currentNotes.count > 1 ? "NOW — \(note.category.uppercased())" : "NOW",
                    text: note.text,
                    emphasized: true
                )
            }
            ForEach(nextNotes, id: \.category) { note in
                notePanel(
                    label: nextNotes.count > 1 ? "NEXT — \(note.category.uppercased())" : "NEXT",
                    text: note.text,
                    emphasized: false
                )
            }
        }
    }

    private func notePanel(label: String, text: String, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(contentTextColor.opacity(0.7))
            Text(text)
                .font(.system(size: emphasized ? 13 : 12, weight: emphasized ? .bold : .medium))
                .foregroundStyle(contentTextColor)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(emphasized ? 0.3 : 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var messagesBar: some View {
        Button {
            showingChat = true
        } label: {
            Label("Messages", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(contentTextColor)
        }
        .buttonStyle(.bordered)
        .tint(contentTextColor)
    }

    private var roleSheet: some View {
        List(model.roles) { role in
            Button {
                model.selectedRoleId = role.id
                showingRoles = false
            } label: {
                HStack {
                    Text(role.name)
                    Spacer()
                    if role.id == model.selectedRoleId {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .navigationTitle("Role")
    }
}