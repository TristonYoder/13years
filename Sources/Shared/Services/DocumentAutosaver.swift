// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Combine
import CryptoKit
import Foundation

public struct DocumentBaselineStore {
    public let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DocumentBaselines", isDirectory: true)
    }

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(name).json")
    }

    public func load(for url: URL) -> ProducerDocument? {
        try? ProducerDocument.read(from: fileURL(for: url))
    }

    public func save(_ document: ProducerDocument, for url: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? document.write(to: fileURL(for: url))
    }
}

@MainActor
public final class DocumentAutosaver: ObservableObject {
    @Published public private(set) var canRevert = false
    private let store: DocumentBaselineStore
    private var manualBaseline: ProducerDocument?

    private weak var engine: CueEngine?
    private let writeDocument: (ProducerDocument, URL) throws -> Void
    private let onFailure: (Error, URL) -> Void
    private var baseline: ProducerDocument
    private var failed: ProducerDocument?
    private var cancellable: AnyCancellable?

    public init(
        engine: CueEngine,
        debounce: TimeInterval = 1.5,
        store: DocumentBaselineStore = DocumentBaselineStore(),
        write: @escaping (ProducerDocument, URL) throws -> Void,
        onFailure: @escaping (Error, URL) -> Void
    ) {
        self.engine = engine
        self.store = store
        self.writeDocument = write
        self.onFailure = onFailure
        baseline = engine.makeDocument().normalizedForComparison()
        let triggers: [AnyPublisher<Void, Never>] = [
            engine.$roles.map { _ in }.eraseToAnyPublisher(),
            engine.$selectedRoleIds.map { _ in }.eraseToAnyPublisher(),
            engine.$waypoints.map { _ in }.eraseToAnyPublisher(),
            engine.$serviceSchedules.map { _ in }.eraseToAnyPublisher(),
            engine.$planItems.map { _ in }.eraseToAnyPublisher(),
            engine.$activeItemIndex.map { _ in }.eraseToAnyPublisher(),
            engine.$hourFormatThreshold.map { _ in }.eraseToAnyPublisher(),
            engine.$pcoDefaultServiceTypeId.map { _ in }.eraseToAnyPublisher(),
            engine.$plotipharRelayHost.map { _ in }.eraseToAnyPublisher()
        ]
        cancellable = Publishers.MergeMany(triggers)
            .receive(on: DispatchQueue.main)
            .compactMap { [weak self] in self?.engine?.makeDocument().normalizedForComparison() }
            .removeDuplicates()
            .handleEvents(receiveOutput: { [weak self] _ in self?.refreshRevert() })
            .debounce(for: .seconds(debounce), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.flush() }
    }

    public var hasUnsavedChanges: Bool {
        guard let engine, engine.currentDocumentURL != nil else { return false }
        let current = engine.makeDocument().normalizedForComparison()
        return current != baseline && current != failed
    }

    public func reseed() {
        guard let engine else { return }
        baseline = engine.makeDocument().normalizedForComparison()
        failed = nil
    }

    public func flush() {
        guard let engine, let url = engine.currentDocumentURL, hasUnsavedChanges else { return }
        let document = engine.makeDocument()
        let normalized = document.normalizedForComparison()
        do {
            try writeDocument(document, url)
            baseline = normalized
            failed = nil
        } catch {
            failed = normalized
            onFailure(error, url)
        }
    }

    public func refreshRevert() {
        guard let engine, engine.currentDocumentURL != nil, let manualBaseline else {
            canRevert = false
            return
        }
        canRevert = engine.makeDocument().normalizedForComparison() != manualBaseline.normalizedForComparison()
    }

    public func markManualSave() {
        guard let engine, let url = engine.currentDocumentURL else {
            manualBaseline = nil
            refreshRevert()
            return
        }
        let document = engine.makeDocument()
        manualBaseline = document
        store.save(document, for: url)
        refreshRevert()
    }

    public func markOpened() {
        guard let engine, let url = engine.currentDocumentURL else {
            manualBaseline = nil
            refreshRevert()
            return
        }
        if let saved = store.load(for: url) {
            manualBaseline = saved
        } else {
            manualBaseline = engine.makeDocument()
            store.save(engine.makeDocument(), for: url)
        }
        refreshRevert()
    }

    public func revertDocument() -> ProducerDocument? {
        canRevert ? manualBaseline : nil
    }
}
