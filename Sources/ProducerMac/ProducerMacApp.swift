// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

@main
struct ProducerMacApp: App {
    @StateObject private var cueEngine = CueEngine(isMasterServer: true, hostsControlAPI: true)
    @StateObject private var splash = SplashCoordinator()
    private let flashingWindow = PagerFlashingWindowController()

    init() {
        AppFonts.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ProducerRootView()
                .environmentObject(cueEngine)
                .frame(minWidth: 800, minHeight: 600)
                .splashScreen(isPresented: splash.isPresented)
                .task {
                    splash.markReady()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Flash a Pager…") {
                    flashingWindow.present(cueEngine: cueEngine)
                }
                .keyboardShortcut("F", modifiers: [.command, .shift])
            }
        }

        #if os(macOS)
        MenuBarExtra("13 Years Producer", systemImage: "bell.badge.fill") {
            Button("Standby Selected (Yellow)") {
                cueEngine.setCueForSelectedRoles(.standby)
            }
            Button("GO Selected (Green)") {
                cueEngine.setCueForSelectedRoles(.go)
            }
            Divider()
            Button("Clear All Cues") {
                cueEngine.clearAllCues()
            }
            Divider()
            Button("Quit 13 Years Producer") {
                NSApplication.shared.terminate(nil)
            }
        }
        #endif
    }
}
