// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

@main
struct ProducerMacApp: App {
    @StateObject private var cueEngine = CueEngine(isMasterServer: true, hostsControlAPI: true)
    @StateObject private var splash = SplashCoordinator()
    @StateObject private var documents = DocumentController()
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
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
                    guard let window = note.object as? NSWindow, window.canBecomeMain, !window.isSheet else { return }
                    documents.saveOnClose(cueEngine)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    documents.saveOnClose(cueEngine)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open…") { documents.open(cueEngine) }
                    .keyboardShortcut("o")
                Menu("Open Recent") {
                    ForEach(documents.recentURLs, id: \.self) { url in
                        Button(url.lastPathComponent) { documents.open(url, in: cueEngine) }
                    }
                    if !documents.recentURLs.isEmpty { Divider() }
                    Button("Clear Menu") { documents.clearRecents() }
                        .disabled(documents.recentURLs.isEmpty)
                }
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { documents.save(cueEngine) }
                    .keyboardShortcut("s")
                Button("Save As…") { documents.saveAs(cueEngine) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
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
