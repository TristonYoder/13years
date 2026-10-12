// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class IOSDocumentController: ObservableObject {
    @Published var isImporting = false
    @Published var importsTemplate = false
    @Published var isExporting = false
    @Published var exportFile = ProducerDocumentFile(ProducerDocument(
        roles: [], waypoints: [], serviceSchedules: [], planItems: [], activeItemIndex: 0,
        settings: .init(hourFormatThreshold: .never, pcoDefaultServiceTypeId: nil, plotipharRelayHost: "")
    ))
    @Published var errorMessage: String?

    var importTypes: [UTType] {
        let base: UTType = importsTemplate ? .thirteenYearsTemplate : .thirteenYearsDocument
        let ext = importsTemplate ? ProducerDocument.templateExtension : ProducerDocument.fileExtension
        return [base, UTType(filenameExtension: ext), .json].compactMap { $0 }
    }

    func beginImport(template: Bool) {
        importsTemplate = template
        isImporting = true
    }

    var exportType: UTType { exportFile.isTemplate ? .thirteenYearsTemplate : .thirteenYearsDocument }

    var hasError: Binding<Bool> {
        Binding(get: { self.errorMessage != nil }, set: { if !$0 { self.errorMessage = nil } })
    }

    func saveAs(_ engine: CueEngine) {
        exportFile = ProducerDocumentFile(engine.makeDocument())
        isExporting = true
    }

    func saveAsTemplate(_ engine: CueEngine) {
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
            Button("Open…") { documents.beginImport(template: false) }
                .keyboardShortcut("o")
            Button("New from Template…") { documents.beginImport(template: true) }
            Button("Save As…") { documents.saveAs(engine) }
                .keyboardShortcut("s")
            Button("Save as Template…") { documents.saveAsTemplate(engine) }
        }
    }
}

struct DocumentMenu: View {
    @ObservedObject var documents: IOSDocumentController
    @EnvironmentObject var engine: CueEngine

    var body: some View {
        Menu {
            Button("Open…", systemImage: "folder") { documents.beginImport(template: false) }
            Button("New from Template…", systemImage: "doc.on.doc") { documents.beginImport(template: true) }
            Divider()
            Button("Save As…", systemImage: "square.and.arrow.up") { documents.saveAs(engine) }
            Button("Save as Template…", systemImage: "doc.badge.plus") { documents.saveAsTemplate(engine) }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .padding(10)
                .background(.regularMaterial, in: Circle())
        }
        .padding(8)
    }
}
