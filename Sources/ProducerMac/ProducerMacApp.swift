// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

@main
struct ProducerMacApp: App {
    @StateObject private var cueEngine = CueEngine(isMasterServer: true, hostsControlAPI: true)
    @StateObject private var splash = SplashCoordinator()
    @StateObject private var documents = DocumentController()
    @StateObject private var launchPreferences = LaunchPreferences()
    private let flashingWindow = PagerFlashingWindowController()

    init() {
        AppFonts.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ProducerRootView()
                .environmentObject(cueEngine)
                .environmentObject(launchPreferences)
                .frame(minWidth: 800, minHeight: 600)
                .disabled(documents.isLauncherPresented)
                .overlay {
                    if documents.isLauncherPresented {
                        LauncherView(documents: documents)
                            .environmentObject(cueEngine)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: documents.isLauncherPresented)
                .splashScreen(isPresented: splash.isPresented)
                .task {
                    splash.markReady()
                    documents.applyLaunchBehavior(launchPreferences, engine: cueEngine)
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
                Button("New Document…") { documents.newDocument(cueEngine) }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("New from Template…") { documents.newFromTemplate(cueEngine) }
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
                Button("Save as Template…") { documents.saveAsTemplate(cueEngine) }
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
