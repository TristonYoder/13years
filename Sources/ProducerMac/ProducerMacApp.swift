// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

@main
struct ProducerMacApp: App {
    @StateObject private var cueEngine = CueEngine(isMasterServer: true, hostsControlAPI: true, defersLANServing: true)
    @StateObject private var splash = SplashCoordinator()
    @StateObject private var documents = DocumentController()
    @StateObject private var launchPreferences = LaunchPreferences()
    @StateObject private var remoteHub = RemoteProducerHub()
    private let flashingWindow = PagerFlashingWindowController()

    init() {
        AppFonts.registerIfNeeded()
    }

    @ViewBuilder
    private var mainContent: some View {
        if let session = remoteHub.session {
            RemoteProducerContainerView(session: session, lan: remoteHub.lan) {
                remoteHub.disconnect()
            }
            .navigationTitle("Remote: \(session.displayName)")
        } else {
            ProducerRootView()
                .environmentObject(cueEngine)
                .environment(\.documentSaveIndicator, documents.saveIndicator)
                .disabled(documents.isLauncherPresented)
                .overlay {
                    if documents.isLauncherPresented {
                        LauncherView(
                            recents: documents.items,
                            actions: LauncherActions(
                                newDocument: { documents.newDocument(cueEngine) },
                                newFromTemplate: { documents.newFromTemplate(cueEngine) },
                                open: { documents.open(cueEngine) },
                                openRecent: { item in
                                    if let endpoint = item.endpoint {
                                        remoteHub.connect(to: endpoint)
                                    } else {
                                        documents.openRecent(item, in: cueEngine)
                                    }
                                },
                                removeRecent: { documents.removeRecent($0) },
                                connect: { remoteHub.isConnectPresented = true },
                                refreshRecents: { documents.pruneRecents() }
                            )
                        )
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: documents.isLauncherPresented)
        }
    }

    var body: some Scene {
        Window("13 Years Producer", id: "main") {
            mainContent
                .environment(\.remoteLAN, remoteHub.lan)
                .background(WindowCloseHandler(
                    decide: { WindowClosePolicy.decide(isRemoteActive: remoteHub.isRemoteActive, isLauncherPresented: documents.isLauncherPresented) },
                    disconnect: { remoteHub.disconnect() }
                ))
                .frame(minWidth: 800, minHeight: 600)
                .environmentObject(launchPreferences)
                .splashScreen(isPresented: splash.isPresented)
                .sheet(isPresented: $remoteHub.isConnectPresented, onDismiss: { remoteHub.requestedEndpoint = nil }) {
                    ConnectToView(
                        prefill: remoteHub.requestedEndpoint,
                        onConnected: { session in
                            remoteHub.activate(session)
                            remoteHub.isConnectPresented = false
                        },
                        onCancel: {
                            remoteHub.requestedEndpoint = nil
                            remoteHub.isConnectPresented = false
                        }
                    )
                }
                .onChange(of: remoteHub.isRemoteActive) { _, active in
                    cueEngine.setLANServingSuspended(active)
                }
                .onChange(of: remoteHub.session?.id) { _, _ in
                    documents.remoteSession = remoteHub.session
                }
                .onChange(of: documents.isLauncherPresented) { _, presented in
                    cueEngine.setLANServingHeld(presented)
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
                    remoteHub.onActivated = { documents.noteRemote($0) }
                    documents.attach(cueEngine)
                    documents.applyLaunchBehavior(launchPreferences, engine: cueEngine)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
                    guard let window = note.object as? NSWindow, window.canBecomeMain, !window.isSheet else { return }
                    remoteHub.disconnect()
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
            MacFileCommands(documents: documents, hub: remoteHub, engine: cueEngine, flashingWindow: flashingWindow)
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
