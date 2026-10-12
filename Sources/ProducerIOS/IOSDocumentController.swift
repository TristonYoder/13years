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
    @Published var isLauncherPresented = true
    @Published private(set) var recents: [RecentEntry] = [] {
        didSet { DocumentMenuBridge.recentURLs = recents.map(\.url) }
    }

    struct RecentEntry: Equatable {
        let url: URL
        let bookmark: Data
        static func == (lhs: RecentEntry, rhs: RecentEntry) -> Bool { lhs.url == rhs.url }
    }

    private static let recentsDefaultsKey = "recentDocumentBookmarks"
    private let defaults: UserDefaults

    var recentURLs: [URL] { recents.map(\.url) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let bookmarks = defaults.array(forKey: Self.recentsDefaultsKey) as? [Data] ?? []
        recents = bookmarks.compactMap { data in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: DocumentBookmark.resolve, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let fresh = stale ? (try? url.bookmarkData(options: DocumentBookmark.create, includingResourceValuesForKeys: nil, relativeTo: nil)) : nil
            return RecentEntry(url: url, bookmark: fresh ?? data)
        }
        DocumentMenuBridge.recentURLs = recents.map(\.url)
    }

    func dismissLauncher() {
        isLauncherPresented = false
    }

    func newDocument(_ engine: CueEngine) {
        engine.resetToNewDocument()
        isLauncherPresented = false
    }

    func applyLaunchBehavior(_ preferences: LaunchPreferences, engine: CueEngine) {
        switch preferences.behavior {
        case .showLauncher:
            return
        case .reopenLast:
            guard let url = recentURLs.first else { return }
            open(url, in: engine)
        case .openFile:
            guard let url = preferences.fileURL else { return }
            open(url, in: engine)
        }
    }

    func clearRecents() {
        recents = []
        persistRecents()
    }

    private func noteRecent(_ url: URL) {
        guard let data = try? url.bookmarkData(options: DocumentBookmark.create, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        recents = RecentDocuments.updated(recents, adding: RecentEntry(url: url, bookmark: data))
        persistRecents()
    }

    private func forget(_ url: URL) {
        recents.removeAll { $0.url == url }
        persistRecents()
    }

    private func persistRecents() {
        defaults.set(recents.map(\.bookmark), forKey: Self.recentsDefaultsKey)
    }

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
            isLauncherPresented = false
            if !isTemplate { noteRecent(url) }
        } catch {
            forget(url)
            errorMessage = "Couldn’t open “\(url.lastPathComponent)”. \(error.localizedDescription)"
        }
    }
}

struct DocumentCommands: Commands {
    @ObservedObject var documents: IOSDocumentController
    let engine: CueEngine

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New from Template…") { documents.beginImport(template: true) }
            Button("Save As…") { documents.saveAs(engine) }
                .keyboardShortcut("s")
            Button("Save as Template…") { documents.saveAsTemplate(engine) }
        }
    }
}
