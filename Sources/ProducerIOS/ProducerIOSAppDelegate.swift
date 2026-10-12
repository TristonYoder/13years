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
    static var recentURLs: [URL] = [] {
        didSet {
            guard recentURLs != oldValue else { return }
            UIMenuSystem.main.setNeedsRebuild()
        }
    }
}

final class ProducerIOSAppDelegate: UIResponder, UIApplicationDelegate {
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }

        let recents = MainActor.assumeIsolated { DocumentMenuBridge.recentURLs }

        builder.replaceChildren(ofMenu: .openRecent) { _ in
            let items: [UIMenuElement] = recents.map { url in
                UICommand(
                    title: url.deletingPathExtension().lastPathComponent,
                    action: #selector(ProducerIOSAppDelegate.openRecentDocument(_:)),
                    propertyList: url.absoluteString
                )
            }
            let clear = UICommand(
                title: "Clear Menu",
                action: #selector(ProducerIOSAppDelegate.clearRecentDocuments(_:)),
                attributes: recents.isEmpty ? .disabled : []
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
              let string = command.propertyList as? String,
              let url = URL(string: string) else { return }
        NotificationCenter.default.post(name: .producerOpenRecent, object: url)
    }

    @objc func clearRecentDocuments(_ sender: Any?) {
        NotificationCenter.default.post(name: .producerClearRecents, object: nil)
    }
}
