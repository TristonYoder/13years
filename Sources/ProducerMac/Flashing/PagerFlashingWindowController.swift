// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import AppKit
import SwiftUI

@MainActor
final class PagerFlashingWindowController {
    private var window: NSWindow?

    func present(cueEngine: CueEngine) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let controller = NSHostingController(
            rootView: PagerFlashingView().environmentObject(cueEngine))
        let window = NSWindow(contentViewController: controller)
        window.title = "Flash a Pager"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
