// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

@main
struct ProducerIOSApp: App {
    @StateObject private var cueEngine = CueEngine(isMasterServer: true, hostsControlAPI: true, defersLANServing: true)
    @StateObject private var splash = SplashCoordinator()
    @StateObject private var documents = IOSDocumentController()
    @StateObject private var launchPreferences = LaunchPreferences()
    @StateObject private var remoteHub = RemoteProducerHub()
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(ProducerIOSAppDelegate.self) private var appDelegate

    init() {
        AppFonts.registerIfNeeded()
    }

    @ViewBuilder
    private var mainContent: some View {
        if let session = remoteHub.session {
            RemoteProducerContainerView(session: session, lan: remoteHub.lan) { remoteHub.disconnect() }
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
                                newFromTemplate: { documents.beginImport(template: true) },
                                open: { documents.beginImport(template: false) },
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
        WindowGroup {
            mainContent
                .environmentObject(launchPreferences)
                .splashScreen(isPresented: splash.isPresented)
                .task {
                    splash.markReady()
                    remoteHub.onActivated = { documents.noteRemote($0) }
                    documents.attach(cueEngine)
                    documents.applyLaunchBehavior(launchPreferences, engine: cueEngine)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { documents.flushForBackground() }
                    if phase == .active {
                        cueEngine.deviceDidBecomeActive()
                        remoteHub.session?.resync()
                        Task { await remoteHub.session?.checkLiveness() }
                    }
                }
                .onChange(of: remoteHub.isRemoteActive) { _, active in
                    documents.isRemoteActive = active
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
                .onReceive(NotificationCenter.default.publisher(for: .producerOpenDocument)) { _ in
                    documents.beginImport(template: false)
                }
                .onReceive(NotificationCenter.default.publisher(for: .producerOpenRecent)) { note in
                    if let index = note.object as? Int { documents.openRecent(at: index, in: cueEngine) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .producerClearRecents)) { _ in
                    guard !remoteHub.isRemoteActive else { return }
                    documents.clearRecents()
                }
                .sheet(isPresented: $remoteHub.isConnectPresented, onDismiss: {
                    remoteHub.requestedEndpoint = nil
                    remoteHub.promotePending()
                }) {
                    ConnectToView(
                        prefill: remoteHub.requestedEndpoint,
                        onConnected: { session in
                            documents.flushForBackground()
                            remoteHub.pending = session
                            remoteHub.isConnectPresented = false
                        },
                        onCancel: {
                            remoteHub.requestedEndpoint = nil
                            remoteHub.isConnectPresented = false
                        }
                    )
                }
                .fileImporter(isPresented: $documents.isImporting, allowedContentTypes: documents.importTypes) {
                    documents.handleImport($0.map { [$0] }, into: cueEngine)
                }
                .fileExporter(
                    isPresented: $documents.isExporting,
                    document: documents.exportFile,
                    contentType: documents.exportType,
                    defaultFilename: documents.exportFilename
                ) { documents.handleExport($0, engine: cueEngine) }
                .alert("Revert to Last Save?", isPresented: $documents.isConfirmingRevert) {
                    Button("Revert", role: .destructive) { documents.revert(cueEngine) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This restores the version from when the document was opened or last saved by hand in this session. Changes since then will be lost.")
                }
                .alert("Document Error", isPresented: documents.hasError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(documents.errorMessage ?? "")
                }
                .onAppear {
                    #if canImport(UIKit)
                    UIApplication.shared.isIdleTimerDisabled = true
                    #endif
                }
        }
        .commands { DocumentCommands(documents: documents, engine: cueEngine, remote: remoteHub) }
    }
}
