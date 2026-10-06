// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct PagerChatView: View {
    @EnvironmentObject var engine: CueEngine
    let roleId: String
    let roleName: String

    @Environment(\.dismiss) private var dismiss
    @State private var messageText = ""

    public init(roleId: String, roleName: String) {
        self.roleId = roleId
        self.roleName = roleName
    }

    private var messages: [InterTeamMessage] {
        engine.recentMessages
            .filter { $0.targetRoleId == nil || $0.targetRoleId == roleId }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                Divider()
                composer
            }
            .navigationTitle("Messages")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        Text("No messages yet")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach(messages) { message in
                        messageRow(message).id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                guard let latest = messages.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(latest.id, anchor: .bottom)
                }
            }
            .onAppear {
                guard let latest = messages.last else { return }
                proxy.scrollTo(latest.id, anchor: .bottom)
            }
        }
    }

    private func messageRow(_ message: InterTeamMessage) -> some View {
        let isBroadcast = message.targetRoleId == nil
        let isMine = message.senderRoleId == roleId
        return HStack {
            if isMine { Spacer(minLength: 40) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(isBroadcast ? "EVERYONE" : "DIRECT")
                        .font(.inter(size: 9, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(isBroadcast ? Color.orange : Color.blue)
                    Text(message.sender)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if message.isHighPriority {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(isMine ? Color.white : Color.primary)
                    .background(
                        isMine ? Color.blue : Color.gray.opacity(0.2),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !isMine { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message Producer…", text: $messageText, axis: .vertical)
                #if os(iOS)
                .textFieldStyle(.roundedBorder)
                #endif
                .lineLimit(1...4)
                .onSubmit(send)

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.inter(size: 28))
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(.regularMaterial)
    }

    private func send() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        engine.sendMessage(trimmed, targetRoleId: roleId, senderRoleId: roleId)
        messageText = ""
    }
}
