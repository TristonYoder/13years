// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DocumentController: ObservableObject {
    @Published private(set) var items: [RecentItem] = []
    @Published var isLauncherPresented = true
    @Published private(set) var canRevert = false
    var remoteSession: RemoteProducerSession?
    let saveIndicator = DocumentSaveIndicator()
    private var observers: [AnyCancellable] = []

    private var discardedOnClose = false
    private var autosaver: DocumentAutosaver?
    private var hasScheduledLaunchBehavior = false
    private var openedByURL = false
    private let defaults: UserDefaults

    var recents: [RecentItem] { items.filter { $0.kind == .document && $0.url != nil } }

    var recentURLs: [URL] { recents.compactMap(\.url) }

    private var contentType: UTType {
        .thirteenYearsDocument
    }

    private var templateType: UTType {
        .thirteenYearsTemplate
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = RecentItems.load(defaults: defaults)
        items = loaded.items
        if loaded.changed { RecentItems.persist(items, defaults: defaults) }
    }

    func attach(_ engine: CueEngine) {
        guard autosaver == nil else { return }
        DocumentAutosaver.purgeLegacyBaselines()
        let saver = DocumentAutosaver(
            engine: engine,
            write: { document, url in try DocumentController.performWrite(document, to: url) }
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
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Revert to Last Save?"
        alert.informativeText = "This restores the version from when the document was opened or last saved by hand in this session. Changes since then will be lost."
        let revert = alert.addButton(withTitle: "Revert")
        revert.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        engine.apply(document)
        if let error = attemptWrite(engine.makeDocument(), to: url) {
            present(error, action: "save", url: url)
            return
        }
        autosaver?.reseed()
        autosaver?.markManualSave()
    }

    func save(_ engine: CueEngine) {
        guard let url = engine.currentDocumentURL else {
            saveAs(engine)
            return
        }
        write(engine, to: url)
    }

    func saveOnClose(_ engine: CueEngine) {
        guard !discardedOnClose else { return }
        if engine.currentDocumentURL == nil {
            confirmUntitledClose(engine)
        } else {
            _ = settle(engine, closing: true)
        }
    }

    private func confirmUntitledClose(_ engine: CueEngine) {
        guard !isLauncherPresented, autosaver?.hasUnsavedUntitledChanges == true else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save this document?"
        alert.informativeText = "This document hasn’t been saved. If you don’t save it, your changes will be lost."
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Don’t Save")
        if alert.runModal() == .alertFirstButtonReturn {
            if !saveAs(engine) { discardedOnClose = true }
        } else {
            discardedOnClose = true
        }
    }

    private func settle(_ engine: CueEngine, closing: Bool) -> Bool {
        guard let saver = autosaver, let url = engine.currentDocumentURL else { return true }
        var failure = saver.flush(force: true)
        while let error = failure {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t save “\(url.lastPathComponent)”"
            alert.informativeText = "\(error.localizedDescription)\n\nSave a copy somewhere else, or discard the changes since the last save."
            alert.addButton(withTitle: "Save As…")
            let discard = alert.addButton(withTitle: closing ? "Close Without Saving" : "Discard Changes")
            discard.hasDestructiveAction = true
            if !closing { alert.addButton(withTitle: "Cancel") }
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                if saveAs(engine) { return true }
                failure = saver.flush(force: true)
            case .alertSecondButtonReturn:
                if closing { discardedOnClose = true }
                return true
            default:
                return false
            }
        }
        return true
    }

    nonisolated static func performWrite(_ document: ProducerDocument, to url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try document.write(to: url)
    }

    private func attemptWrite(_ document: ProducerDocument, to url: URL) -> Error? {
        do {
            try Self.performWrite(document, to: url)
            return nil
        } catch {
            return error
        }
    }

    @discardableResult
    func saveAs(_ engine: CueEngine) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = engine.currentDocumentURL?.lastPathComponent
            ?? "\(engine.isRemoteMirror ? (engine.remoteProducerName ?? "Remote Producer") : "Untitled").\(ProducerDocument.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return write(engine, to: url)
    }

    func newDocument(_ engine: CueEngine) {
        guard remoteSession == nil else { return }
        guard settle(engine, closing: false) else { return }
        guard let url = chooseNewDocumentLocation(name: "Untitled") else { return }
        create(engine, content: nil, at: url)
    }

    private func chooseNewDocumentLocation(name: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        panel.title = "New Document"
        panel.prompt = "Create"
        panel.nameFieldStringValue = "\(name).\(ProducerDocument.fileExtension)"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    @discardableResult
    private func create(_ engine: CueEngine, content: ProducerDocument?, at url: URL) -> Bool {
        let previous = engine.makeDocument()
        let previousURL = engine.currentDocumentURL
        if let content {
            engine.apply(content)
        } else {
            engine.resetToNewDocument()
        }
        engine.currentDocumentURL = nil
        if write(engine, to: url) { return true }
        engine.apply(previous)
        engine.currentDocumentURL = previousURL
        return false
    }

    func saveAsTemplate(_ engine: CueEngine) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [templateType]
        panel.canCreateDirectories = true
        panel.title = "Save as Template"
        panel.prompt = "Save Template"
        let base = engine.currentDocumentURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.nameFieldStringValue = "\(base).\(ProducerDocument.templateExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try engine.makeDocument().asTemplate().write(to: url)
        } catch {
            present(error, action: "save the template", url: url)
        }
    }

    func newFromTemplate(_ engine: CueEngine) {
        guard remoteSession != nil || settle(engine, closing: false) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [templateType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "New from Template"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openTemplate(url, in: engine)
    }

    @discardableResult
    func openTemplate(_ url: URL, in engine: CueEngine, reportErrors: Bool = true) -> Bool {
        if let session = remoteSession {
            RemoteDocumentLoader.send(url, to: session)
            return true
        }
        guard settle(engine, closing: false) else { return false }
        let document: ProducerDocument
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            document = try ProducerDocument.read(from: url)
        } catch {
            if reportErrors { present(error, action: "open", url: url) }
            return false
        }
        guard let destination = chooseNewDocumentLocation(name: RecentDocuments.title(for: url)) else { return false }
        let created = create(engine, content: document, at: destination)
        if created { noteRecent(url, kind: .template) }
        return created
    }

    func applyLaunchBehavior(_ preferences: LaunchPreferences, engine: CueEngine, connectRemote: @escaping (RemoteEndpoint) -> Void) {
        guard !hasScheduledLaunchBehavior else { return }
        hasScheduledLaunchBehavior = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !self.openedByURL, self.isLauncherPresented else { return }
            self.runLaunchBehavior(preferences, engine: engine, connectRemote: connectRemote)
        }
    }

    private func runLaunchBehavior(_ preferences: LaunchPreferences, engine: CueEngine, connectRemote: (RemoteEndpoint) -> Void) {
        switch preferences.action {
        case .showLauncher:
            return
        case .connectRemote(let endpoint):
            connectRemote(endpoint)
        case .reopenLast:
            guard let url = recentURLs.first else { return }
            open(url, in: engine)
        case .openFile:
            guard let url = preferences.fileURL else { return }
            if preferences.isTemplate {
                openTemplate(url, in: engine)
            } else {
                open(url, in: engine)
            }
        }
    }

    func handleOpenURL(_ url: URL, in engine: CueEngine) {
        openedByURL = true
        if url.pathExtension.lowercased() == ProducerDocument.templateExtension {
            openTemplate(url, in: engine)
        } else {
            open(url, in: engine)
        }
    }

    func open(_ engine: CueEngine) {
        guard remoteSession != nil || settle(engine, closing: false) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = remoteSession != nil ? RemoteDocumentLoader.contentTypes : [contentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url, in: engine)
    }

    func open(_ url: URL, in engine: CueEngine) {
        if let session = remoteSession {
            RemoteDocumentLoader.send(url, to: session)
            return
        }
        guard settle(engine, closing: false) else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let document = try ProducerDocument.read(from: url)
            engine.apply(document)
            engine.currentDocumentURL = url
            autosaver?.reseed()
            autosaver?.markOpened()
            discardedOnClose = false
            isLauncherPresented = false
            noteRecent(url)
        } catch {
            if RecentDocuments.isFileNotFound(error) { forget(url) }
            present(error, action: "open", url: url)
        }
    }

    func openRecent(_ url: URL, in engine: CueEngine) {
        let target = recents.first { $0.url == url }
            .flatMap { $0.bookmark }
            .flatMap { try? DocumentBookmark.resolved($0).url } ?? url
        open(target, in: engine)
    }

    func openRecent(_ item: RecentItem, in engine: CueEngine) {
        guard item.isFile, let url = item.url else { return }
        let target = item.bookmark.flatMap { try? DocumentBookmark.resolved($0).url } ?? url
        if item.kind == .template {
            if !openTemplate(target, in: engine), RecentDocuments.availability(of: target) == .missing { forget(target, kind: .template) }
        } else {
            open(target, in: engine)
        }
    }

    func removeRecent(_ item: RecentItem) {
        items.removeAll { $0.identity == item.identity }
        RecentItems.persist(items, defaults: defaults)
    }

    func noteRemote(_ session: RemoteProducerSession) {
        items = RecentItems.updated(items, adding: .remote(session.endpoint, name: session.displayName))
        RecentItems.persist(items, defaults: defaults)
    }

    func pruneRecents() {
        let kept = RecentItems.pruned(items)
        guard kept.count != items.count else { return }
        items = kept
        RecentItems.persist(items, defaults: defaults)
    }

    func clearRecents() {
        items = []
        RecentItems.persist(items, defaults: defaults)
    }

    @discardableResult
    private func write(_ engine: CueEngine, to url: URL) -> Bool {
        if let error = attemptWrite(engine.makeDocument(), to: url) {
            present(error, action: "save", url: url)
            return false
        }
        engine.currentDocumentURL = url
        noteRecent(url)
        if engine.isRemoteMirror { return true }
        discardedOnClose = false
        isLauncherPresented = false
        autosaver?.reseed()
        autosaver?.markManualSave()
        return true
    }

    private func noteRecent(_ url: URL, kind: RecentKind = .document) {
        do {
            let bookmark = try DocumentBookmark.make(for: url)
            items = RecentItems.updated(items, adding: .file(url, bookmark: bookmark, kind: kind))
            RecentItems.persist(items, defaults: defaults)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Couldn’t add “\(url.lastPathComponent)” to Open Recent"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func forget(_ url: URL, kind: RecentKind = .document) {
        items.removeAll { $0.kind == kind && $0.url == url }
        RecentItems.persist(items, defaults: defaults)
    }

    private func present(_ error: Error, action: String, url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t \(action) “\(url.lastPathComponent)”"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
