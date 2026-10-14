// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import AppKit
import SwiftUI

@MainActor
final class PagerFlashingWindowController {
    private var window: NSWindow?
    private var hosting: NSHostingController<AnyView>?

    func present(cueEngine: CueEngine) {
        if let window, let hosting {
            hosting.rootView = AnyView(PagerFlashingView().environmentObject(cueEngine))
            window.makeKeyAndOrderFront(nil)
            return
        }

        let controller = NSHostingController(
            rootView: AnyView(PagerFlashingView().environmentObject(cueEngine)))
        hosting = controller
        let window = NSWindow(contentViewController: controller)
        window.title = "Flash a Pager"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
