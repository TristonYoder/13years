// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

@main
struct PagerMacApp: App {
    @StateObject private var cueEngine = CueEngine(isMasterServer: false)
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("keepOnTop") private var keepOnTop = false

    init() {
        AppFonts.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            PagerRootView()
                .environmentObject(cueEngine)
                .frame(minWidth: 320, minHeight: 240)
                .ignoresSafeArea()
                .background(EdgelessWindow(keepOnTop: keepOnTop))
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { cueEngine.deviceDidBecomeActive() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 560)
    }
}

private struct EdgelessWindow: NSViewRepresentable {
    let keepOnTop: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = .black
            window.level = keepOnTop ? .floating : .normal
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.level = keepOnTop ? .floating : .normal
    }
}
