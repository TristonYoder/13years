// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct MessagesView: View {
    @EnvironmentObject var engine: CueEngine
    @State private var messageText: String = ""
    @State private var isHighPriority = false
    @State private var showingClearConfirmation = false
    @State private var showingPhrases = false

    public init() {}

    private var selectedThreadId: String {
        get { engine.selectedMessageThreadId }
        nonmutating set { engine.selectedMessageThreadId = newValue }
    }

    private var targetRoleId: String? { selectedThreadId == "all" ? nil : selectedThreadId }

    private var threadMessages: [InterTeamMessage] {
        engine.recentMessages.filter { $0.targetRoleId == targetRoleId }
    }

    private var hasAnyActiveNotification: Bool {
        engine.roles.contains { engine.activeNotification(forRoleId: $0.id) != nil }
    }

    public var body: some View {
        VStack(spacing: 0) {
            SectionHeaderBar(mode: .messages) {
                Button(action: { engine.clearActiveNotification() }) {
                    Label("Clear Notification", systemImage: "bell.slash")
                }
                .disabled(engine.activeNotification(forRoleId: nil) == nil && !hasAnyActiveNotification)
                .help("Take the standing message off the web pagers and lower thirds, keeping the history")

                Button(role: .destructive, action: { showingClearConfirmation = true }) {
                    Label("Clear History", systemImage: "trash")
                }
                .help("Clear message history on every connected device — cannot be undone")
            }
            .onScreenshotTourSignal("messages.clear-history") { _ in showingClearConfirmation = true }
            .confirmationDialog(
                "Clear message history on every connected device?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear History", role: .destructive) {
                    engine.clearMessageHistory()
                }
            } message: {
                Text("This removes every message on this device, every connected Pager, and the ESP32 — it can't be undone.")
            }

            HStack(spacing: 0) {
                threadSidebar
                Divider()
                VStack(spacing: 0) {
                    messageList
                    Divider()
                    composer
                }
            }
        }
        .onAppear { engine.markThreadRead(roleId: selectedThreadId) }
        .onChange(of: selectedThreadId) { _, id in engine.markThreadRead(roleId: id) }
        .onChange(of: engine.recentMessages) { _, _ in engine.markThreadRead(roleId: selectedThreadId) }
    }

    private var threadSidebar: some View {
        List(selection: Binding(
            get: { selectedThreadId },
            set: { if let newValue = $0 { selectedThreadId = newValue } }
        )) {
            threadRow(id: "all", name: "Everyone", symbol: "person.3.fill")
                .tag("all")

            Section("Direct Messages") {
                ForEach(engine.roles) { role in
                    threadRow(id: role.id, name: role.name, symbol: nil)
                        .tag(role.id)
                }
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #endif
        .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
    }

    /// Avatar, name, the last message as a preview, its time, and an unread dot.
    private func threadRow(id: String, name: String, symbol: String?) -> some View {
        let latest = engine.recentMessages.first(where: { $0.targetRoleId == (id == "all" ? nil : id) })
        let hasUnread = id != "all" && engine.hasUnreadMessage(forRoleId: id)
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.12))
                if let symbol {
                    Image(systemName: symbol).font(.caption)
                } else {
                    Text(String(name.prefix(1)).uppercased()).font(.caption.weight(.bold))
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).fontWeight(hasUnread ? .bold : .medium).lineLimit(1)
                Text(latest.map { ($0.senderRoleId == nil ? "You: " : "") + $0.text } ?? "No messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                if let latest {
                    Text(latest.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if hasUnread {
                    Circle().fill(AppPalette.info).frame(width: 9, height: 9)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if threadMessages.isEmpty {
                        Text("No messages yet")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach(Array(threadMessages.reversed())) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: threadMessages.count) { _, _ in
                guard let latest = threadMessages.first else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(latest.id, anchor: .bottom)
                }
            }
        }
    }

    private func messageRow(_ message: InterTeamMessage) -> some View {
        let isFromProducer = message.senderRoleId == nil
        return HStack {
            if isFromProducer { Spacer(minLength: 40) }

            VStack(alignment: isFromProducer ? .trailing : .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if selectedThreadId == "all" {
                        Text(message.sender)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if message.isHighPriority {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(AppPalette.negative)
                    }
                }

                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(isFromProducer ? Color.white : Color.primary)
                    .background(
                        isFromProducer ? Color.accentColor : AppPalette.bubbleReceived,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )

                Text(engine.displayClockFormat.string(from: message.timestamp))
                    .font(.clock(.caption2, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            if !isFromProducer { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selectedThreadId == "all" ? "To: Everyone" : "To: \(threadName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle(isOn: $isHighPriority) {
                    Label("High priority", systemImage: isHighPriority ? "exclamationmark.circle.fill" : "exclamationmark.circle")
                }
                #if os(iOS) || os(macOS)
                .toggleStyle(.button)
                #endif
                .tint(AppPalette.negative)
                .help("Mark as high priority")
            }

            phraseChips

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message…", text: $messageText, axis: .vertical)
                    #if os(macOS)
                    .textFieldStyle(.roundedBorder)
                    #endif
                    .lineLimit(1...4)
                    .onSubmit(send)

                Button("Send") { send() }
                    .buttonStyle(.borderedProminent)
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    private var phraseChips: some View {
        let phrases = engine.phrases(forRoleId: targetRoleId)
        return HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(phrases, id: \.self) { phrase in
                        Button(phrase) {
                            messageText = messageText.isEmpty ? phrase : messageText + " " + phrase
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            Button {
                showingPhrases = true
            } label: {
                Label("Edit Phrases", systemImage: "slider.horizontal.3")
            }
            .controlSize(.small)
            .help("Edit the quick phrases, shared and per role")
        }
        #if os(macOS) || os(iOS)
        .sheet(isPresented: $showingPhrases) {
            CannedPhrasesView()
                .environmentObject(engine)
        }
        #endif
    }

    private var threadName: String {
        engine.roles.first(where: { $0.id == selectedThreadId })?.name ?? "Unknown role"
    }

    private func send() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        engine.sendMessage(trimmed, targetRoleId: targetRoleId, isHighPriority: isHighPriority)
        messageText = ""
        // Priority is for the one message it was set on; it should not stay on for the next.
        isHighPriority = false
    }
}
