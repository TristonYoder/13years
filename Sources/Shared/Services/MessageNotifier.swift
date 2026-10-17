// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS) || os(iOS)
import SwiftUI
import Combine
import UserNotifications
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class MessageNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    private weak var engine: CueEngine?
    private var cancellables: Set<AnyCancellable> = []
    private var hasRequestedAuthorization = false
    nonisolated private static let threadKey = "roleId"

    private static var canPostNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    func attach(to engine: CueEngine) {
        guard Self.canPostNotifications, self.engine !== engine else { return }
        self.engine = engine
        cancellables.removeAll()
        UNUserNotificationCenter.current().delegate = self
        engine.incomingMessages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in self?.notify(message) }
            .store(in: &cancellables)
        engine.$recentMessages
            .combineLatest(engine.$selectedMessageThreadId, engine.$appMode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateBadge() }
            .store(in: &cancellables)
    }

    private func isShowing(_ message: InterTeamMessage) -> Bool {
        guard let engine, engine.appMode == .messages, isAppActive else { return false }
        let thread = engine.selectedMessageThreadId
        return thread == CueEngine.allMessagesThreadId || thread == message.senderRoleId
    }

    private var isAppActive: Bool {
        #if os(macOS)
        NSApplication.shared.isActive
        #else
        UIApplication.shared.applicationState == .active
        #endif
    }

    private func notify(_ message: InterTeamMessage) {
        guard !isShowing(message) else { return }
        let center = UNUserNotificationCenter.current()
        let post = { [weak self] in
            guard let self else { return }
            let content = UNMutableNotificationContent()
            content.title = self.title(for: message)
            content.body = message.text
            content.sound = .default
            content.threadIdentifier = message.senderRoleId ?? CueEngine.allMessagesThreadId
            if let role = message.senderRoleId { content.userInfo = [Self.threadKey: role] }
            if message.isHighPriority { content.interruptionLevel = .timeSensitive }
            center.add(UNNotificationRequest(identifier: message.id, content: content, trigger: nil))
        }
        if hasRequestedAuthorization {
            post()
        } else {
            hasRequestedAuthorization = true
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                guard granted else { return }
                DispatchQueue.main.async { post() }
            }
        }
    }

    private func title(for message: InterTeamMessage) -> String {
        let roleName = message.senderRoleId.flatMap { id in engine?.roles.first { $0.id == id }?.name }
        if let roleName, roleName != message.sender {
            return "\(message.sender) \u{00B7} \(roleName)"
        }
        return message.sender
    }

    private func updateBadge() {
        let count = engine?.unreadMessageCount ?? 0
        #if os(macOS)
        NSApplication.shared.dockTile.badgeLabel = count > 0 ? String(count) : nil
        #else
        UNUserNotificationCenter.current().setBadgeCount(count)
        #endif
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let role = response.notification.request.content.userInfo[Self.threadKey] as? String
        await MainActor.run {
            guard let engine = self.engine else { return }
            if let role {
                engine.openMessageThread(forRoleId: role)
            } else {
                engine.appMode = .messages
            }
            #if os(macOS)
            NSApplication.shared.activate()
            #endif
        }
    }
}

struct MessageNotificationsModifier: ViewModifier {
    @EnvironmentObject var engine: CueEngine
    @StateObject private var notifier = MessageNotifier()

    func body(content: Content) -> some View {
        content.onAppear { notifier.attach(to: engine) }
    }
}
#endif
