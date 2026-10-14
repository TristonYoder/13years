// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

@main
struct ProducerIOSApp: App {
    @StateObject private var cueEngine = CueEngine(isMasterServer: true, hostsControlAPI: true)
    @StateObject private var splash = SplashCoordinator()
    @StateObject private var documents = IOSDocumentController()
    @StateObject private var launchPreferences = LaunchPreferences()
    @StateObject private var remoteHub = RemoteProducerHub()
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(ProducerIOSAppDelegate.self) private var appDelegate

    init() {
        AppFonts.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ProducerRootView()
                .environmentObject(cueEngine)
                .environmentObject(launchPreferences)
                .environment(\.documentSaveIndicator, documents.saveIndicator)
                .disabled(documents.isLauncherPresented)
                .overlay {
                    if documents.isLauncherPresented {
                        LauncherView(
                            recentURLs: documents.recentURLs,
                            actions: LauncherActions(
                                newDocument: { documents.newDocument(cueEngine) },
                                newFromTemplate: { documents.beginImport(template: true) },
                                open: { documents.beginImport(template: false) },
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
                .task {
                    splash.markReady()
                    remoteHub.localEngine = cueEngine
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
                .onOpenURL { url in
                    if let session = remoteHub.session {
                        RemoteDocumentLoader.send(url, to: session)
                    } else {
                        documents.handleOpenURL(url, in: cueEngine)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .producerOpenDocument)) { _ in
                    guard !remoteHub.isRemoteActive else { return }
                    documents.beginImport(template: false)
                }
                .onReceive(NotificationCenter.default.publisher(for: .producerOpenRecent)) { note in
                    guard !remoteHub.isRemoteActive else { return }
                    if let index = note.object as? Int { documents.openRecent(at: index, in: cueEngine) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .producerClearRecents)) { _ in
                    guard !remoteHub.isRemoteActive else { return }
                    documents.clearRecents()
                }
                .sheet(isPresented: $remoteHub.isConnectPresented, onDismiss: { remoteHub.promotePending() }) {
                    ConnectToView(
                        onConnected: { session in
                            documents.flushForBackground()
                            remoteHub.pending = session
                            remoteHub.isConnectPresented = false
                        },
                        onCancel: { remoteHub.isConnectPresented = false }
                    )
                }
                .fullScreenCover(isPresented: Binding(
                    get: { remoteHub.isRemoteActive },
                    set: { if !$0 { remoteHub.disconnect() } }
                )) {
                    if let session = remoteHub.session {
                        RemoteProducerContainerView(session: session, lan: remoteHub.lan) { remoteHub.disconnect() }
                    }
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
