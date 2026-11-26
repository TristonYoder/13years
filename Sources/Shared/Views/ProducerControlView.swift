// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct ProducerControlView: View {
    @EnvironmentObject var engine: CueEngine
    @State private var showingPlanPicker = false
    @AppStorage("showPagerPreview") private var showsPreview = true
    @AppStorage("pagerRoleLayout") private var roleLayout = "table"

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            SectionHeaderBar(mode: .producerControl) {
                Button(action: { engine.whenPCOConnected { showingPlanPicker = true } }) {
                    Label(engine.isPCOConnected ? "Change Plan" : "Sync PCO", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Pick a Planning Center plan type and plan to sync")

                Button(action: { showsPreview.toggle() }) {
                    Label(showsPreview ? "Hide Preview" : "Show Preview", systemImage: "iphone.gen3")
                }
                .help(showsPreview ? "Hide the live pager preview" : "Show the live pager preview")
            }

            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        roleGrid
                    }
                    .padding()
                }

                if showsPreview {
                    PagerPreviewPane()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .clipped()
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showsPreview)
        }
        .sheet(isPresented: $showingPlanPicker) {
            PCOPlanPickerView()
        }
    }

    private var roleGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Roles", systemImage: "person.3.fill")
                    .font(.headline)
                Spacer()
                Picker("Layout", selection: $roleLayout) {
                    Label("Table", systemImage: "list.bullet").tag("table")
                    Label("Cards", systemImage: "square.grid.2x2").tag("cards")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Show the roles as a dense table or as cards")
                Button("Clear All", role: .destructive) {
                    engine.clearAllCues()
                }
                .compactControlSize()
                .help("Clear the cue for every role")
            }

            if roleLayout == "table" {
                roleTable
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                    ForEach(engine.roles) { role in
                        roleCard(role)
                    }
                }
            }
        }
    }

    /// One line per role with every control inline, for scanning a long team quickly.
    private var roleTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Color.clear.frame(width: 22)
                Text("ROLE").frame(width: 150, alignment: .leading)
                Text("PERSON").frame(width: 110, alignment: .leading)
                Text("CUE").frame(width: 230, alignment: .leading)
                Text("LAST MESSAGE").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            ForEach(Array(engine.roles.enumerated()), id: \.element.id) { index, role in
                roleRow(role, striped: index % 2 == 0)
            }
        }
    }

    private func roleRow(_ role: RoleCue, striped: Bool) -> some View {
        let isSelected = engine.selectedRoleIds.contains(role.id)
        let unread = engine.hasUnreadMessage(forRoleId: role.id)
        let last = engine.recentMessages.first(where: { $0.targetRoleId == role.id })
        return HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? AppPalette.info : .secondary)
                .frame(width: 22)
            Text(role.name)
                .fontWeight(.semibold)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            Text(role.personName ?? "\u{2014}")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)
            HStack(spacing: 6) {
                Button("Standby") { engine.setCueForRole(id: role.id, state: .standby) }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.cueStandby)
                    .foregroundStyle(.black)
                    .opacity(role.state == .standby ? 1 : 0.55)
                Button("GO!") { engine.setCueForRole(id: role.id, state: .go) }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.cueGo)
                    .opacity(role.state == .go ? 1 : 0.55)
                Button("Off") { engine.setCueForRole(id: role.id, state: .off) }
                    .producerSecondaryButton()
            }
            .compactControlSize()
            .frame(width: 230, alignment: .leading)
            Text(last.map { ($0.senderRoleId == nil ? "You: " : "") + $0.text } ?? "\u{2014}")
                .font(.callout)
                .foregroundStyle(unread ? Color.primary : Color.secondary)
                .fontWeight(unread ? .semibold : .regular)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: { engine.openMessageThread(forRoleId: role.id) }) {
                Image(systemName: unread ? "message.badge.fill" : "message")
            }
            .producerSecondaryButton()
            .compactControlSize()
            .help("Open the message thread with \(role.name)")
            Button(action: { engine.clearActiveNotification() }) {
                Image(systemName: "bell.slash")
            }
            .producerSecondaryButton()
            .compactControlSize()
            .disabled(engine.activeNotification(forRoleId: role.id) == nil)
            .help("Take the standing message off the web pagers and lower thirds, keeping the history")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(striped ? Color.primary.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? AppPalette.info : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { engine.toggleRoleSelection(role.id) }
    }

    private func roleCard(_ role: RoleCue) -> some View {
        let isSelected = engine.selectedRoleIds.contains(role.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppPalette.info : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(role.name)
                        .font(.headline)
                    if let person = role.personName {
                        Text(person)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if role.state != .off {
                    Text(role.state.displayName)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(role.state.color.opacity(0.2), in: Capsule())
                        .foregroundStyle(role.state.color)
                }

                Button(action: { engine.openMessageThread(forRoleId: role.id) }) {
                    Image(systemName: "message.fill")
                }
                .producerSecondaryButton()
                .compactControlSize()
                .help("Open the message thread with \(role.name)")

                Button(action: { engine.clearActiveNotification() }) {
                    Image(systemName: "bell.slash")
                }
                .producerSecondaryButton()
                .compactControlSize()
                .disabled(engine.activeNotification(forRoleId: role.id) == nil)
                .help("Take the standing message off the web pagers and lower thirds, keeping the history")
            }

            HStack(spacing: 8) {
                Button("Standby") { engine.setCueForRole(id: role.id, state: .standby) }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.cueStandby)
                    .foregroundStyle(.black)
                    .compactControlSize()
                    .frame(maxWidth: .infinity)

                Button("GO!") { engine.setCueForRole(id: role.id, state: .go) }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.cueGo)
                    .compactControlSize()
                    .frame(maxWidth: .infinity)

                Button("Off") { engine.setCueForRole(id: role.id, state: .off) }
                    .producerSecondaryButton()
                    .compactControlSize()
            }
        }
        .padding(12)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.regularMaterial)
                if engine.hasUnreadMessage(forRoleId: role.id) {
                    PulsingBlueFill()
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? AppPalette.info : .clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            if engine.hasUnreadMessage(forRoleId: role.id) {
                UnreadMessageBadge()
                    .offset(x: 18, y: -18)
                    .allowsHitTesting(false)
            }
        }
        .onTapGesture { engine.toggleRoleSelection(role.id) }
    }
}

private struct UnreadMessageBadge: View {
    var body: some View {
        Image(systemName: "message.fill")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .padding(8)
            .background(AppPalette.info, in: Circle())
            .accessibilityLabel("Unread message")
    }
}

private struct PulsingBlueFill: View {
    @State private var isBright = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(AppPalette.info)
            .opacity(isBright ? 0.3 : 0.04)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    isBright = true
                }
            }
            .allowsHitTesting(false)
    }
}

private struct PagerPreviewPane: View {
    private static let phoneSize = CGSize(width: 320, height: 660)
    private static let padding: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let availableHeight = max(proxy.size.height - Self.padding * 2, 1)
            let scale = min(1, availableHeight / Self.phoneSize.height)

            HostPagerView()
                .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 16) }
                .safeAreaInset(edge: .leading, spacing: 0) { Color.clear.frame(width: 12) }
                .frame(width: Self.phoneSize.width, height: Self.phoneSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 44, style: .continuous)
                        .strokeBorder(.black, lineWidth: 10)
                )
                .shadow(color: AppPalette.scrimSoft, radius: 20, y: 10)
                .scaleEffect(scale)
                .frame(width: Self.phoneSize.width * scale, height: Self.phoneSize.height * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 380)
    }
}
