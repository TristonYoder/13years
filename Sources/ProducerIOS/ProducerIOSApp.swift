// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

@main
struct ProducerIOSApp: App {
    @StateObject private var cueEngine = CueEngine(isMasterServer: true, hostsControlAPI: true)
    @StateObject private var splash = SplashCoordinator()
    @StateObject private var documents = IOSDocumentController()

    init() {
        AppFonts.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ProducerRootView()
                .environmentObject(cueEngine)
                .overlay(alignment: .topTrailing) { DocumentMenu(documents: documents) }
                .splashScreen(isPresented: splash.isPresented)
                .task { splash.markReady() }
                .onOpenURL { documents.open($0, in: cueEngine) }
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
