// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class IOSDocumentController: ObservableObject {
    @Published var isImporting = false
    @Published var isImportingTemplate = false
    @Published var isExporting = false
    @Published var exportFile = ProducerDocumentFile(ProducerDocument(
        roles: [], waypoints: [], serviceSchedules: [], planItems: [], activeItemIndex: 0,
        settings: .init(hourFormatThreshold: .never, pcoDefaultServiceTypeId: nil, plotipharRelayHost: "")
    ))
    @Published var errorMessage: String?

    var exportType: UTType { exportFile.isTemplate ? .thirteenYearsTemplate : .thirteenYearsShow }

    var hasError: Binding<Bool> {
        Binding(get: { self.errorMessage != nil }, set: { if !$0 { self.errorMessage = nil } })
    }

    func exportShow(_ engine: CueEngine) {
        exportFile = ProducerDocumentFile(engine.makeDocument())
        isExporting = true
    }

    func exportTemplate(_ engine: CueEngine) {
        exportFile = ProducerDocumentFile(engine.makeDocument(), isTemplate: true)
        isExporting = true
    }

    func handleImport(_ result: Result<[URL], Error>, into engine: CueEngine) {
        switch result {
        case .success(let urls):
            if let url = urls.first { open(url, in: engine) }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func handleExport(_ result: Result<URL, Error>) {
        if case .failure(let error) = result { errorMessage = error.localizedDescription }
    }

    func open(_ url: URL, in engine: CueEngine) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let document = try ProducerDocument.read(from: url)
            let isTemplate = url.pathExtension.lowercased() == ProducerDocument.templateExtension
            engine.apply(document)
            engine.currentDocumentURL = isTemplate ? nil : url
        } catch {
            errorMessage = "Couldn’t open “\(url.lastPathComponent)”. \(error.localizedDescription)"
        }
    }
}

struct DocumentCommands: Commands {
    @ObservedObject var documents: IOSDocumentController
    let engine: CueEngine

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Show…") { documents.isImporting = true }
                .keyboardShortcut("o")
            Button("Open Template…") { documents.isImportingTemplate = true }
            Button("Export Show…") { documents.exportShow(engine) }
                .keyboardShortcut("s")
            Button("Export as Template…") { documents.exportTemplate(engine) }
        }
    }
}

struct DocumentMenu: View {
    @ObservedObject var documents: IOSDocumentController
    @EnvironmentObject var engine: CueEngine

    var body: some View {
        Menu {
            Button("Open Show…", systemImage: "folder") { documents.isImporting = true }
            Button("Open Template…", systemImage: "doc.on.doc") { documents.isImportingTemplate = true }
            Divider()
            Button("Export Show…", systemImage: "square.and.arrow.up") { documents.exportShow(engine) }
            Button("Export as Template…", systemImage: "doc.badge.plus") { documents.exportTemplate(engine) }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .padding(10)
                .background(.regularMaterial, in: Circle())
        }
        .padding(8)
    }
}
