// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

@main
struct ProducerIOSApp: App {
    @StateObject private var cueEngine = CueEngine(isMasterServer: true, hostsControlAPI: true)
    @StateObject private var splash = SplashCoordinator()
    @StateObject private var documents = IOSDocumentController()
    @StateObject private var launchPreferences = LaunchPreferences()
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
                                skip: { documents.dismissLauncher() }
                            )
                        )
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: documents.isLauncherPresented)
                .splashScreen(isPresented: splash.isPresented)
                .task {
                    splash.markReady()
                    documents.applyLaunchBehavior(launchPreferences, engine: cueEngine)
                }
                .onOpenURL { documents.open($0, in: cueEngine) }
                .onReceive(NotificationCenter.default.publisher(for: .producerOpenDocument)) { _ in
                    documents.beginImport(template: false)
                }
                .onReceive(NotificationCenter.default.publisher(for: .producerOpenRecent)) { note in
                    if let url = note.object as? URL { documents.open(url, in: cueEngine) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .producerClearRecents)) { _ in
                    documents.clearRecents()
                }
                .fileImporter(isPresented: $documents.isImporting, allowedContentTypes: documents.importTypes) {
                    documents.handleImport($0.map { [$0] }, into: cueEngine)
                }
                .fileExporter(
                    isPresented: $documents.isExporting,
                    document: documents.exportFile,
                    contentType: documents.exportType,
                    defaultFilename: documents.exportFile.isTemplate ? "Untitled Template" : "Untitled"
                ) { documents.handleExport($0) }
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
        .commands { DocumentCommands(documents: documents, engine: cueEngine) }
    }
}
