// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import UIKit

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
