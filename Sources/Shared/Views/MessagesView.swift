// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct MessagesView: View {
    @EnvironmentObject var engine: CueEngine
    @State private var messageText: String = ""
    @State private var selectedThreadId: String = "all"
    @State private var isHighPriority = false
    @State private var showingClearConfirmation = false

    public init() {}

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
    }

    private var threadSidebar: some View {
        List(selection: Binding(
            get: { selectedThreadId },
            set: { if let newValue = $0 { selectedThreadId = newValue } }
        )) {
            Label("Everyone", systemImage: "person.3.fill")
                .tag("all")

            Section("Direct Messages") {
                ForEach(engine.roles) { role in
                    Label(role.name, systemImage: "person.fill")
                        .tag(role.id)
                }
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #endif
        .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)
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
                            .foregroundStyle(.red)
                    }
                }

                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(isFromProducer ? Color.white : Color.primary)
                    .background(
                        isFromProducer ? Color.accentColor : Color.primary.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )

                Text(message.timestamp, style: .time)
                    .font(.caption2)
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
                .tint(.red)
                .help("Mark as high priority")
            }

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

    private var threadName: String {
        engine.roles.first(where: { $0.id == selectedThreadId })?.name ?? "Unknown role"
    }

    private func send() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        engine.sendMessage(trimmed, targetRoleId: targetRoleId, isHighPriority: isHighPriority)
        messageText = ""
    }
}
