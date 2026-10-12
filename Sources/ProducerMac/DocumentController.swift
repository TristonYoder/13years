// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DocumentController: ObservableObject {
    @Published private(set) var recentURLs: [URL] = []
    @Published var isLauncherPresented = true

    private var discardedOnClose = false

    private static let recentsDefaultsKey = "recentDocumentBookmarks"
    private static let maxRecents = 10

    private var contentType: UTType {
        .thirteenYearsDocument
    }

    private var templateType: UTType {
        .thirteenYearsTemplate
    }

    init() {
        let bookmarks = UserDefaults.standard.array(forKey: Self.recentsDefaultsKey) as? [Data] ?? []
        recentURLs = bookmarks.compactMap { data in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }
    }

    func save(_ engine: CueEngine) {
        guard let url = engine.currentDocumentURL else {
            saveAs(engine)
            return
        }
        write(engine, to: url)
    }

    func saveOnClose(_ engine: CueEngine) {
        guard let url = engine.currentDocumentURL, !discardedOnClose else { return }
        var failure: Error? = attemptWrite(engine, to: url)
        while let error = failure {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t save “\(url.lastPathComponent)”"
            alert.informativeText = "\(error.localizedDescription)\n\nSave a copy somewhere else, or close and lose the changes since the last save."
            alert.addButton(withTitle: "Save As…")
            alert.addButton(withTitle: "Close Without Saving")
            if alert.runModal() == .alertFirstButtonReturn {
                if saveAs(engine) { return }
            } else {
                discardedOnClose = true
                return
            }
            failure = attemptWrite(engine, to: url)
        }
    }

    private func attemptWrite(_ engine: CueEngine, to url: URL) -> Error? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try engine.makeDocument().write(to: url)
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
            ?? "Untitled.\(ProducerDocument.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return write(engine, to: url)
    }

    func newDocument(_ engine: CueEngine) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        panel.title = "New Document"
        panel.prompt = "Create"
        panel.nameFieldStringValue = "Untitled.\(ProducerDocument.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        engine.resetToNewDocument()
        write(engine, to: url)
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
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            engine.apply(try ProducerDocument.read(from: url))
            engine.currentDocumentURL = nil
            discardedOnClose = false
            isLauncherPresented = false
            return true
        } catch {
            if reportErrors { present(error, action: "open", url: url) }
            return false
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
            if preferences.isTemplate {
                openTemplate(url, in: engine)
            } else {
                open(url, in: engine)
            }
        }
    }

    func handleOpenURL(_ url: URL, in engine: CueEngine) {
        if url.pathExtension.lowercased() == ProducerDocument.templateExtension {
            openTemplate(url, in: engine)
        } else {
            open(url, in: engine)
        }
    }

    func open(_ engine: CueEngine) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [contentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url, in: engine)
    }

    func open(_ url: URL, in engine: CueEngine) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            engine.apply(try ProducerDocument.read(from: url))
            engine.currentDocumentURL = url
            discardedOnClose = false
            isLauncherPresented = false
            noteRecent(url)
        } catch {
            forget(url)
            present(error, action: "open", url: url)
        }
    }

    func clearRecents() {
        recentURLs = []
        persistRecents()
    }

    @discardableResult
    private func write(_ engine: CueEngine, to url: URL) -> Bool {
        if let error = attemptWrite(engine, to: url) {
            present(error, action: "save", url: url)
            return false
        }
        engine.currentDocumentURL = url
        discardedOnClose = false
        isLauncherPresented = false
        noteRecent(url)
        return true
    }

    private func noteRecent(_ url: URL) {
        recentURLs.removeAll { $0 == url }
        recentURLs.insert(url, at: 0)
        if recentURLs.count > Self.maxRecents { recentURLs.removeLast(recentURLs.count - Self.maxRecents) }
        persistRecents()
    }

    private func forget(_ url: URL) {
        recentURLs.removeAll { $0 == url }
        persistRecents()
    }

    private func persistRecents() {
        let bookmarks = recentURLs.compactMap {
            try? $0.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        UserDefaults.standard.set(bookmarks, forKey: Self.recentsDefaultsKey)
    }

    private func present(_ error: Error, action: String, url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t \(action) “\(url.lastPathComponent)”"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
