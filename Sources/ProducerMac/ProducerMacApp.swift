// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

@main
struct ProducerMacApp: App {
    @StateObject private var cueEngine = CueEngine(isMasterServer: true, hostsControlAPI: true)
    @StateObject private var splash = SplashCoordinator()
    @StateObject private var documents = DocumentController()
    @StateObject private var launchPreferences = LaunchPreferences()
    @StateObject private var remoteHub = RemoteProducerHub()
    private let flashingWindow = PagerFlashingWindowController()

    init() {
        AppFonts.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ProducerRootView()
                .environmentObject(cueEngine)
                .environmentObject(launchPreferences)
                .environment(\.documentSaveIndicator, documents.saveIndicator)
                .frame(minWidth: 800, minHeight: 600)
                .disabled(documents.isLauncherPresented)
                .overlay {
                    if documents.isLauncherPresented {
                        LauncherView(
                            recentURLs: documents.recentURLs,
                            actions: LauncherActions(
                                newDocument: { documents.newDocument(cueEngine) },
                                newFromTemplate: { documents.newFromTemplate(cueEngine) },
                                open: { documents.open(cueEngine) },
                                openRecent: { documents.openRecent($0, in: cueEngine) },
                                connect: { remoteHub.isConnectPresented = true },
                                refreshRecents: { documents.pruneRecents() }
                            )
                        )
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: documents.isLauncherPresented)
                .splashScreen(isPresented: splash.isPresented)
                .modifier(ConnectWindowOpener(hub: remoteHub))
                .onChange(of: remoteHub.isRemoteActive) { _, active in
                    cueEngine.setLANServingSuspended(active)
                }
                .onOpenURL { url in
                    if let session = remoteHub.session {
                        RemoteDocumentLoader.send(url, to: session)
                    } else {
                        documents.handleOpenURL(url, in: cueEngine)
                    }
                }
                .task {
                    splash.markReady()
                    remoteHub.localEngine = cueEngine
                    documents.attach(cueEngine)
                    documents.applyLaunchBehavior(launchPreferences, engine: cueEngine)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
                    guard let window = note.object as? NSWindow, window.canBecomeMain, !window.isSheet, !RemoteWindowIDs.isAuxiliary(identifier: window.identifier) else { return }
                    documents.saveOnClose(cueEngine)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    documents.saveOnClose(cueEngine)
                    remoteHub.lan.shutdown()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    cueEngine.deviceDidBecomeActive()
                    remoteHub.session?.resync()
                    Task { await remoteHub.session?.checkLiveness() }
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                    cueEngine.deviceDidBecomeActive()
                    remoteHub.session?.resync()
                    Task { await remoteHub.session?.checkLiveness() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            MacFileCommands(documents: documents, engine: cueEngine, flashingWindow: flashingWindow)
        }

        Window(RemoteWindowIDs.connectTitle, id: RemoteWindowIDs.connect) {
            MacConnectWindow(hub: remoteHub)
        }
        .windowResizability(.contentSize)

        Window("Remote Producer", id: RemoteWindowIDs.remote) {
            MacRemoteWindow(hub: remoteHub)
        }

        #if os(macOS)
        MenuBarExtra("13 Years Producer", systemImage: "bell.badge.fill") {
            if let session = remoteHub.session {
                RemoteMenuBarItems(session: session)
            }
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

private struct ConnectWindowOpener: ViewModifier {
    @ObservedObject var hub: RemoteProducerHub
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onChange(of: hub.isConnectPresented) { _, requested in
            guard requested else { return }
            hub.isConnectPresented = false
            openWindow(id: RemoteWindowIDs.connect)
        }
    }
}
