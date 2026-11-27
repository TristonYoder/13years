// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import UIKit
import ObjectiveC

extension Notification.Name {
    static let producerOpenDocument = Notification.Name("producerOpenDocument")
    static let producerOpenRecent = Notification.Name("producerOpenRecent")
    static let producerClearRecents = Notification.Name("producerClearRecents")
}

@MainActor
enum DocumentMenuBridge {
    static var recentTitles: [String] = [] {
        didSet {
            guard recentTitles != oldValue else { return }
            UIMenuSystem.main.setNeedsRebuild()
        }
    }

    static var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            UIMenuSystem.main.setNeedsRebuild()
            UIMenuSystem.main.setNeedsRevalidate()
        }
    }
}

final class ProducerIOSAppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        ProducerKeyInterceptor.install()
        return true
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }

        let (recents, enabled) = MainActor.assumeIsolated { (DocumentMenuBridge.recentTitles, DocumentMenuBridge.isEnabled) }

        builder.replaceChildren(ofMenu: .openRecent) { _ in
            let items: [UIMenuElement] = recents.enumerated().map { index, title in
                UICommand(
                    title: title,
                    action: #selector(ProducerIOSAppDelegate.openRecentDocument(_:)),
                    propertyList: index,
                    attributes: enabled ? [] : .disabled
                )
            }
            let clear = UICommand(
                title: "Clear Menu",
                action: #selector(ProducerIOSAppDelegate.clearRecentDocuments(_:)),
                attributes: (recents.isEmpty || !enabled) ? .disabled : []
            )
            return items + [UIMenu(options: .displayInline, children: [clear])]
        }

        builder.replaceChildren(ofMenu: .open) { existing in
            let open = UIKeyCommand(
                title: "Open…",
                action: #selector(ProducerIOSAppDelegate.openDocument(_:)),
                input: "o",
                modifierFlags: .command
            )
            return [open] + existing.compactMap { $0 as? UIMenu }
        }
    }

    @objc func openDocument(_ sender: Any?) {
        NotificationCenter.default.post(name: .producerOpenDocument, object: nil)
    }

    @objc func openRecentDocument(_ sender: Any?) {
        guard let command = sender as? UICommand,
              let index = command.propertyList as? Int else { return }
        NotificationCenter.default.post(name: .producerOpenRecent, object: index)
    }

    @objc func clearRecentDocuments(_ sender: Any?) {
        NotificationCenter.default.post(name: .producerClearRecents, object: nil)
    }
}

@MainActor
enum ProducerKeyInterceptor {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        let original = #selector(UIApplication.sendEvent(_:))
        let replacement = #selector(UIApplication.producerSendEvent(_:))
        guard let originalMethod = class_getInstanceMethod(UIApplication.self, original),
              let replacementMethod = class_getInstanceMethod(UIApplication.self, replacement) else { return }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }

    static func handle(_ event: UIPressesEvent) -> Bool {
        guard let handler = TypedStartRelay.handler,
              let press = event.allPresses.first(where: { $0.phase == .began && $0.key != nil }), let key = press.key,
              key.modifierFlags.isDisjoint(with: [.command, .control, .alternate]) else { return false }
        let characters = key.characters
        guard characters.count == 1, let first = characters.first, !first.isWhitespace,
              characters.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 && !(0xF700...0xF8FF).contains($0.value) }) else { return false }
        if UIResponder.currentFirstResponder() is UITextInput { return false }
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        if window?.rootViewController?.presentedViewController != nil { return false }
        return handler(characters)
    }
}

extension UIApplication {
    @objc fileprivate func producerSendEvent(_ event: UIEvent) {
        if let presses = event as? UIPressesEvent, MainActor.assumeIsolated({ ProducerKeyInterceptor.handle(presses) }) { return }
        producerSendEvent(event)
    }
}

private extension UIResponder {
    private static weak var firstResponderProbe: UIResponder?

    @MainActor static func currentFirstResponder() -> UIResponder? {
        firstResponderProbe = nil
        UIApplication.shared.sendAction(#selector(captureFirstResponder), to: nil, from: nil, for: nil)
        return firstResponderProbe
    }

    @objc func captureFirstResponder() {
        UIResponder.firstResponderProbe = self
    }
}
