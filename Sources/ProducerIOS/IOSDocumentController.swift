// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Combine
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
private final class BackgroundTaskBox {
    var identifier = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

@MainActor
final class IOSDocumentController: ObservableObject {
    @Published var isImporting = false
    @Published var importsTemplate = false
    @Published var isExporting = false
    @Published var exportFile = IOSDocumentController.blankFile
    @Published var errorMessage: String?
    @Published var isLauncherPresented = true {
        didSet { publishMenuState() }
    }
    @Published var isRemoteActive = false {
        didSet { publishMenuState() }
    }
    @Published private(set) var canRevert = false
    @Published var isConfirmingRevert = false
    @Published private(set) var recents: [RecentEntry] = [] {
        didSet { DocumentMenuBridge.recentTitles = recents.map { RecentDocuments.title(for: $0.url) } }
    }
    let saveIndicator = DocumentSaveIndicator()
    private var observers: [AnyCancellable] = []

    private let defaults: UserDefaults

    var recentURLs: [URL] { recents.map(\.url) }

    var isDocumentActionsEnabled: Bool { !isLauncherPresented && !isRemoteActive }

    private static var blankFile: ProducerDocumentFile {
        ProducerDocumentFile(ProducerDocument(
            roles: [], waypoints: [], serviceSchedules: [], planItems: [], activeItemIndex: 0,
            settings: .init(hourFormatThreshold: .never, pcoDefaultServiceTypeId: nil, plotipharRelayHost: "")
        ))
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = RecentDocuments.load(defaults: defaults)
        recents = loaded.entries
        if loaded.changed { RecentDocuments.persist(recents, defaults: defaults) }
        DocumentMenuBridge.recentTitles = recents.map { RecentDocuments.title(for: $0.url) }
        publishMenuState()
    }

    private func publishMenuState() {
        DocumentMenuBridge.isEnabled = isDocumentActionsEnabled
    }

    private enum ExportPurpose { case copy, saveAs, newDocument, newFromTemplate }
    private var exportPurpose = ExportPurpose.copy
    private var pendingTemplate: ProducerDocument?
    private var autosaver: DocumentAutosaver?
    private weak var engine: CueEngine?
    private var hasScheduledLaunchBehavior = false
    private var openedByURL = false
    private(set) var exportFilename = "Untitled"

    func attach(_ engine: CueEngine) {
        guard autosaver == nil else { return }
        self.engine = engine
        DocumentAutosaver.purgeLegacyBaselines()
        let saver = DocumentAutosaver(
            engine: engine,
            write: { document, url in try IOSDocumentController.coordinatedWrite(document, to: url) }
        )
        autosaver = saver
        observers = [
            saver.$canRevert.removeDuplicates().sink { [weak self] in self?.canRevert = $0 },
            saver.$status.removeDuplicates().sink { [weak self] in self?.saveIndicator.status = $0 }
        ]
        saveIndicator.onActivate = { [weak self, weak engine] in
            guard let self, let engine else { return }
            self.saveAs(engine)
        }
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

    func flushForBackground() {
        guard let saver = autosaver, saver.isDirty else { return }
        let box = BackgroundTaskBox()
        box.identifier = UIApplication.shared.beginBackgroundTask(withName: "DocumentSave") {
            MainActor.assumeIsolated { box.end() }
        }
        saver.writeInBackground(force: true) { box.end() }
    }

    private func settle() -> Bool {
        guard let saver = autosaver, let url = engine?.currentDocumentURL else { return true }
        if let error = saver.flush(force: true) {
            errorMessage = "Couldn’t save “\(url.lastPathComponent)”. \(error.localizedDescription) Use Save As… to keep a copy before switching documents."
            return false
        }
        return true
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
        guard settle() else { return }
        exportFile = Self.blankFile
        exportFilename = "Untitled"
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

    func handleOpenURL(_ url: URL, in engine: CueEngine) {
        openedByURL = true
        open(url, in: engine)
    }

    func applyLaunchBehavior(_ preferences: LaunchPreferences, engine: CueEngine) {
        guard !hasScheduledLaunchBehavior else { return }
        hasScheduledLaunchBehavior = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !self.openedByURL, self.isLauncherPresented else { return }
            switch preferences.behavior {
            case .showLauncher:
                return
            case .reopenLast:
                guard let url = self.recentURLs.first else { return }
                self.openRecent(url, in: engine)
            case .openFile:
                guard let url = preferences.fileURL else { return }
                self.open(url, in: engine)
            }
        }
    }

    func clearRecents() {
        recents = []
        RecentDocuments.persist(recents, defaults: defaults)
    }

    func pruneRecents() {
        let kept = RecentDocuments.pruned(recents)
        guard kept.count != recents.count else { return }
        recents = kept
        RecentDocuments.persist(recents, defaults: defaults)
    }

    private func noteRecent(_ url: URL) {
        do {
            let data = try DocumentBookmark.make(for: url)
            recents = RecentDocuments.updated(recents, adding: RecentEntry(url: url, bookmark: data))
            RecentDocuments.persist(recents, defaults: defaults)
        } catch {
            errorMessage = "Couldn’t add “\(url.lastPathComponent)” to Open Recent. \(error.localizedDescription)"
        }
    }

    private func forget(_ url: URL) {
        recents.removeAll { $0.url == url }
        RecentDocuments.persist(recents, defaults: defaults)
    }

    var importTypes: [UTType] {
        let base: UTType = importsTemplate ? .thirteenYearsTemplate : .thirteenYearsDocument
        let ext = importsTemplate ? ProducerDocument.templateExtension : ProducerDocument.fileExtension
        return [base, UTType(filenameExtension: ext)].compactMap { $0 }
    }

    func beginImport(template: Bool) {
        guard settle() else { return }
        importsTemplate = template
        isImporting = true
    }

    var exportType: UTType { exportFile.isTemplate ? .thirteenYearsTemplate : .thirteenYearsDocument }

    var hasError: Binding<Bool> {
        Binding(get: { self.errorMessage != nil }, set: { if !$0 { self.errorMessage = nil } })
    }

    func saveAs(_ engine: CueEngine) {
        exportFile = ProducerDocumentFile(engine.makeDocument())
        exportFilename = engine.currentDocumentURL.map { RecentDocuments.title(for: $0) } ?? "Untitled"
        exportPurpose = .saveAs
        isExporting = true
    }

    func saveAsTemplate(_ engine: CueEngine) {
        exportFile = ProducerDocumentFile(engine.makeDocument(), isTemplate: true)
        exportFilename = "Untitled Template"
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
            pendingTemplate = nil
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
                guard settle() else { return }
                create(engine, content: nil, at: url)
            case .newFromTemplate:
                let content = pendingTemplate
                pendingTemplate = nil
                guard settle() else { return }
                create(engine, content: content, at: url)
            }
        }
    }

    private func create(_ engine: CueEngine, content: ProducerDocument?, at url: URL) {
        let previous = engine.makeDocument()
        let previousURL = engine.currentDocumentURL
        if let content {
            engine.apply(content)
        } else {
            engine.resetToNewDocument()
        }
        engine.currentDocumentURL = nil
        do {
            try Self.coordinatedWrite(engine.makeDocument(), to: url)
        } catch {
            engine.apply(previous)
            engine.currentDocumentURL = previousURL
            errorMessage = "Couldn’t save “\(url.lastPathComponent)”. \(error.localizedDescription)"
            return
        }
        engine.currentDocumentURL = url
        noteRecent(url)
        autosaver?.reseed()
        autosaver?.markManualSave()
        isLauncherPresented = false
    }

    func openRecent(_ url: URL, in engine: CueEngine) {
        guard let index = recents.firstIndex(where: { $0.url == url }) else {
            open(url, in: engine)
            return
        }
        openRecent(at: index, in: engine)
    }

    func openRecent(at index: Int, in engine: CueEngine) {
        guard recents.indices.contains(index) else { return }
        let entry = recents[index]
        do {
            let resolved = try DocumentBookmark.resolved(entry.bookmark)
            open(resolved.url, in: engine)
        } catch {
            if RecentDocuments.isFileNotFound(error) { forget(entry.url) }
            errorMessage = "Couldn’t open “\(entry.url.lastPathComponent)”. \(error.localizedDescription)"
        }
    }

    private func openTemplate(_ url: URL) {
        guard settle() else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let document = try ProducerDocument.read(from: url)
            pendingTemplate = document
            exportFile = ProducerDocumentFile(document)
            exportFilename = RecentDocuments.title(for: url)
            exportPurpose = .newFromTemplate
            isExporting = true
        } catch {
            errorMessage = "Couldn’t open “\(url.lastPathComponent)”. \(error.localizedDescription)"
        }
    }

    func open(_ url: URL, in engine: CueEngine) {
        if url.pathExtension.lowercased() == ProducerDocument.templateExtension {
            openTemplate(url)
            return
        }
        guard settle() else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let document = try ProducerDocument.read(from: url)
            engine.apply(document)
            engine.currentDocumentURL = url
            autosaver?.reseed()
            autosaver?.markOpened()
            isLauncherPresented = false
            noteRecent(url)
        } catch {
            if RecentDocuments.isFileNotFound(error) { forget(url) }
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
                .disabled(!documents.isDocumentActionsEnabled)
            Button("Save As…") { documents.saveAs(engine) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!documents.isDocumentActionsEnabled)
            Button("Revert to Last Save") { documents.isConfirmingRevert = true }
                .disabled(!documents.canRevert || !documents.isDocumentActionsEnabled)
            Button("Save as Template…") { documents.saveAsTemplate(engine) }
                .disabled(!documents.isDocumentActionsEnabled)
        }
    }
}
