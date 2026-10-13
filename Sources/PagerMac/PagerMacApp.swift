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
                .frame(minWidth: 240, minHeight: 64)
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

    func makeCoordinator() -> Coordinator { Coordinator() }

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
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.level = keepOnTop ? .floating : .normal
    }

    final class Coordinator {
        private var observers: [NSObjectProtocol] = []
        private var keepAwake: NSObjectProtocol?

        func attach(to window: NSWindow) {
            setButtons(visible: window.isKeyWindow, in: window)
            setKeepAwake(window.styleMask.contains(.fullScreen))
            let center = NotificationCenter.default
            for (name, visible) in [(NSWindow.didBecomeKeyNotification, true), (NSWindow.didResignKeyNotification, false)] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                    guard let window else { return }
                    self?.setButtons(visible: visible, in: window)
                })
            }
            for (name, fullScreen) in [(NSWindow.didEnterFullScreenNotification, true), (NSWindow.didExitFullScreenNotification, false), (NSWindow.willCloseNotification, false)] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.setKeepAwake(fullScreen)
                })
            }
        }

        private func setKeepAwake(_ on: Bool) {
            if on, keepAwake == nil {
                keepAwake = ProcessInfo.processInfo.beginActivity(
                    options: [.userInitiated, .idleDisplaySleepDisabled, .latencyCritical],
                    reason: "Pager is full screen"
                )
            } else if !on, let token = keepAwake {
                ProcessInfo.processInfo.endActivity(token)
                keepAwake = nil
            }
        }

        private func setButtons(visible: Bool, in window: NSWindow) {
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = !visible
            }
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
            if let keepAwake { ProcessInfo.processInfo.endActivity(keepAwake) }
        }
    }
}
