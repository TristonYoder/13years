// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

struct WatchChatView: View {
    @ObservedObject var model: WatchPagerModel

    @State private var draft = ""
    @State private var isSending = false

    private var threadMessages: [InterTeamMessage] {
        guard let messages = model.state?.messages else { return [] }
        return messages.filter { $0.targetRoleId == nil || $0.targetRoleId == model.selectedRoleId }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(threadMessages) { message in
                bubble(message)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)

            composer
        }
        .navigationTitle(model.activeRole?.name ?? "Messages")
    }

    private func bubble(_ message: InterTeamMessage) -> some View {
        let isMine = message.senderRoleId == model.selectedRoleId
        return HStack {
            if isMine { Spacer(minLength: 30) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 1) {
                if !isMine {
                    Text(message.sender.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }
                Text(message.text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isMine ? Color.white : Color.black)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.shortTime(message.timestamp))
                    .font(.system(size: 8, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isMine ? Color.accentColor : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !isMine { Spacer(minLength: 30) }
        }
        .listRowInsets(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6))
    }

    private static func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: date)
    }

    private var composer: some View {
        HStack(spacing: 6) {
            TextField("Reply to Producer…", text: $draft)
                .font(.system(size: 12))

            Button {
                let text = draft
                draft = ""
                isSending = true
                Task {
                    await model.sendMessage(text)
                    isSending = false
                }
            } label: {
                if isSending {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                }
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding(8)
    }
}