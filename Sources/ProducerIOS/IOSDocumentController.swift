// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Combine
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
    @Published private(set) var canRevert = false
    @Published var isConfirmingRevert = false
    private var revertObserver: AnyCancellable?
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

    private enum ExportPurpose { case copy, saveAs, newDocument }
    private var exportPurpose = ExportPurpose.copy
    private var autosaver: DocumentAutosaver?

    func attach(_ engine: CueEngine) {
        guard autosaver == nil else { return }
        let saver = DocumentAutosaver(
            engine: engine,
            write: { document, url in try Self.coordinatedWrite(document, to: url) },
            onFailure: { [weak self] error, url in
                self?.errorMessage = "Couldn’t save “\(url.lastPathComponent)”. \(error.localizedDescription)"
            }
        )
        autosaver = saver
        revertObserver = saver.$canRevert.removeDuplicates().sink { [weak self] in self?.canRevert = $0 }
    }

    func revert(_ engine: CueEngine) {
        guard let url = engine.currentDocumentURL, let document = autosaver?.revertDocument() else { return }
        engine.apply(document)
        do {
            try Self.coordinatedWrite(engine.makeDocument(), to: url)
        } catch {
            errorMessage = "Couldn’t save “\(url.lastPathComponent)”. \(error.localizedDescription)"
            return
        }
        autosaver?.reseed()
        autosaver?.markManualSave()
    }

    func flushIfNeeded() {
        autosaver?.flush()
    }

    nonisolated private static func coordinatedWrite(_ document: ProducerDocument, to url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do { try document.write(to: target) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError.map({ $0 as NSError }) { throw error }
    }

    func newDocument(_ engine: CueEngine) {
        exportFile = ProducerDocumentFile(ProducerDocument(
            roles: [], waypoints: [], serviceSchedules: [], planItems: [], activeItemIndex: 0,
            settings: .init(hourFormatThreshold: .never, pcoDefaultServiceTypeId: nil, plotipharRelayHost: "")
        ))
        exportPurpose = .newDocument
        isExporting = true
    }

    func save(_ engine: CueEngine) {
        guard let url = engine.currentDocumentURL else {
            saveAs(engine)
            return
        }
        do {
            try Self.coordinatedWrite(engine.makeDocument(), to: url)
            autosaver?.reseed()
            autosaver?.markManualSave()
        } catch {
            errorMessage = "Couldn’t save “\(url.lastPathComponent)”. \(error.localizedDescription)"
        }
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
        exportPurpose = .saveAs
        isExporting = true
    }

    func saveAsTemplate(_ engine: CueEngine) {
        exportFile = ProducerDocumentFile(engine.makeDocument(), isTemplate: true)
        exportPurpose = .copy
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

    func handleExport(_ result: Result<URL, Error>, engine: CueEngine) {
        let purpose = exportPurpose
        exportPurpose = .copy
        switch result {
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled { errorMessage = error.localizedDescription }
        case .success(let url):
            switch purpose {
            case .copy:
                break
            case .saveAs:
                engine.currentDocumentURL = url
                noteRecent(url)
                autosaver?.reseed()
                autosaver?.markManualSave()
            case .newDocument:
                engine.resetToNewDocument()
                do {
                    try Self.coordinatedWrite(engine.makeDocument(), to: url)
                } catch {
                    errorMessage = "Couldn’t save “\(url.lastPathComponent)”. \(error.localizedDescription)"
                    return
                }
                engine.currentDocumentURL = url
                noteRecent(url)
                autosaver?.reseed()
                autosaver?.markManualSave()
                isLauncherPresented = false
            }
        }
    }

    func open(_ url: URL, in engine: CueEngine) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let document = try ProducerDocument.read(from: url)
            let isTemplate = url.pathExtension.lowercased() == ProducerDocument.templateExtension
            engine.apply(document)
            engine.currentDocumentURL = isTemplate ? nil : url
            autosaver?.reseed()
            autosaver?.markOpened()
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
    @ObservedObject var remote: RemoteProducerHub

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Document…") { documents.newDocument(engine) }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(remote.isRemoteActive)
            Button("New from Template…") { documents.beginImport(template: true) }
                .disabled(remote.isRemoteActive)
            Button("Connect To…") { remote.isConnectPresented = true }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(remote.isRemoteActive)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { documents.save(engine) }
                .keyboardShortcut("s")
                .disabled(remote.isRemoteActive)
            Button("Save As…") { documents.saveAs(engine) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(remote.isRemoteActive)
            Button("Revert to Last Save") { documents.isConfirmingRevert = true }
                .disabled(!documents.canRevert || remote.isRemoteActive)
            Button("Save as Template…") { documents.saveAsTemplate(engine) }
                .disabled(remote.isRemoteActive)
        }
    }
}
