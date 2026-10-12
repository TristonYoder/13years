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
                .disabled(documents.isLauncherPresented)
                .overlay {
                    if documents.isLauncherPresented {
                        LauncherView(
                            recentURLs: documents.recentURLs,
                            actions: LauncherActions(
                                newDocument: { documents.newDocument(cueEngine) },
                                newFromTemplate: { documents.beginImport(template: true) },
                                open: { documents.beginImport(template: false) },
                                openRecent: { documents.open($0, in: cueEngine) },
                                connect: { remoteHub.isConnectPresented = true }
                            )
                        )
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: documents.isLauncherPresented)
                .splashScreen(isPresented: splash.isPresented)
                .task {
                    splash.markReady()
                    documents.attach(cueEngine)
                    documents.applyLaunchBehavior(launchPreferences, engine: cueEngine)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { documents.flushIfNeeded() }
                    if phase == .active {
                        cueEngine.deviceDidBecomeActive()
                        remoteHub.session?.resync()
                    }
                }
                .onOpenURL { documents.open($0, in: cueEngine) }
                .onReceive(NotificationCenter.default.publisher(for: .producerOpenDocument)) { _ in
                    guard !remoteHub.isRemoteActive else { return }
                    documents.beginImport(template: false)
                }
                .onReceive(NotificationCenter.default.publisher(for: .producerOpenRecent)) { note in
                    guard !remoteHub.isRemoteActive else { return }
                    if let url = note.object as? URL { documents.open(url, in: cueEngine) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .producerClearRecents)) { _ in
                    guard !remoteHub.isRemoteActive else { return }
                    documents.clearRecents()
                }
                .sheet(isPresented: $remoteHub.isConnectPresented, onDismiss: { remoteHub.promotePending() }) {
                    ConnectToView(
                        onConnected: { session in
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
                        RemoteProducerContainerView(session: session) { remoteHub.disconnect() }
                    }
                }
                .fileImporter(isPresented: $documents.isImporting, allowedContentTypes: documents.importTypes) {
                    documents.handleImport($0.map { [$0] }, into: cueEngine)
                }
                .fileExporter(
                    isPresented: $documents.isExporting,
                    document: documents.exportFile,
                    contentType: documents.exportType,
                    defaultFilename: documents.exportFile.isTemplate ? "Untitled Template" : "Untitled"
                ) { documents.handleExport($0, engine: cueEngine) }
                .alert("Revert to Last Save?", isPresented: $documents.isConfirmingRevert) {
                    Button("Revert", role: .destructive) { documents.revert(cueEngine) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Changes since the last save will be lost.")
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
