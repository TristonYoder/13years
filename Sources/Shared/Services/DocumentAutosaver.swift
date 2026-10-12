// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Combine
import Foundation

public enum DocumentSaveStatus: Equatable, Sendable {
    case untitled
    case saved
    case saving
    case failed

    public var text: String {
        switch self {
        case .untitled: return "Untitled — not saved"
        case .saved: return "Saved"
        case .saving: return "Saving…"
        case .failed: return "Not saved — click to Save As…"
        }
    }

    public var isActionable: Bool {
        self == .failed || self == .untitled
    }
}

@MainActor
public final class DocumentSaveIndicator: ObservableObject {
    @Published public var status: DocumentSaveStatus = .untitled
    public var onActivate: (() -> Void)?

    public init() {}
}

@MainActor
public final class DocumentAutosaver: ObservableObject {
    @Published public private(set) var canRevert = false
    @Published public private(set) var status: DocumentSaveStatus = .untitled

    private weak var engine: CueEngine?
    private let writeDocument: @Sendable (ProducerDocument, URL) throws -> Void
    private let onFailure: (Error, URL) -> Void
    private let indexThrottle: TimeInterval
    private let queue = DispatchQueue(label: "dev.7co.13years.autosave")
    private var baseline: ProducerDocument
    private var manualBaseline: ProducerDocument?
    private var isSuspended = false
    private var inFlight = 0
    private var generation = 0
    private var lastWrite: Date?
    private var throttleItem: DispatchWorkItem?
    private var cancellable: AnyCancellable?

    public init(
        engine: CueEngine,
        debounce: TimeInterval = 1.5,
        indexThrottle: TimeInterval = 10,
        write: @escaping @Sendable (ProducerDocument, URL) throws -> Void,
        onFailure: @escaping (Error, URL) -> Void = { _, _ in }
    ) {
        self.engine = engine
        self.indexThrottle = indexThrottle
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
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.refreshRevert()
                self?.refreshStatus()
            })
            .debounce(for: .seconds(debounce), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.autosave() }
    }

    public static func purgeLegacyBaselines() {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DocumentBaselines", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    private var current: ProducerDocument? {
        engine?.makeDocument().normalizedForComparison()
    }

    public var isDirty: Bool {
        guard let engine, engine.currentDocumentURL != nil else { return false }
        return engine.makeDocument().normalizedForComparison() != baseline
    }

    public var hasUnsavedChanges: Bool {
        isDirty && !isSuspended
    }

    public var hasUnsavedUntitledChanges: Bool {
        guard let engine, engine.currentDocumentURL == nil else { return false }
        return engine.makeDocument().normalizedForComparison() != baseline
    }

    public var isAutosaveSuspended: Bool { isSuspended }

    public func reseed() {
        guard let engine else { return }
        baseline = engine.makeDocument().normalizedForComparison()
        isSuspended = false
        generation += 1
        throttleItem?.cancel()
        refreshStatus()
    }

    private func autosave() {
        guard hasUnsavedChanges else {
            refreshStatus()
            return
        }
        if deferIfIndexOnly() { return }
        writeInBackground(completion: nil)
    }

    private func deferIfIndexOnly() -> Bool {
        guard let engine, let last = lastWrite, engine.planItems.contains(where: \.isRunning) else { return false }
        let remaining = indexThrottle - Date().timeIntervalSince(last)
        guard remaining > 0, var probe = current else { return false }
        probe.activeItemIndex = baseline.activeItemIndex
        guard probe == baseline else { return false }
        throttleItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.autosave() }
        }
        throttleItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: item)
        return true
    }

    public func writeInBackground(force: Bool = false, completion: (() -> Void)?) {
        guard let engine, let url = engine.currentDocumentURL, force ? isDirty : hasUnsavedChanges else {
            completion?()
            return
        }
        let document = engine.makeDocument()
        let normalized = document.normalizedForComparison()
        let token = generation
        let write = writeDocument
        inFlight += 1
        refreshStatus()
        queue.async { [weak self] in
            var failure: Error?
            do { try write(document, url) } catch { failure = error }
            let outcome = failure
            Task { @MainActor [weak self] in
                guard let self else { completion?(); return }
                self.inFlight -= 1
                if token == self.generation {
                    self.settle(outcome, normalized: normalized, url: url)
                } else {
                    self.refreshStatus()
                }
                completion?()
            }
        }
    }

    @discardableResult
    public func flush(force: Bool = false) -> Error? {
        guard let engine, let url = engine.currentDocumentURL, force ? isDirty : hasUnsavedChanges else { return nil }
        let document = engine.makeDocument()
        let normalized = document.normalizedForComparison()
        let write = writeDocument
        var failure: Error?
        do { try queue.sync { try write(document, url) } } catch { failure = error }
        settle(failure, normalized: normalized, url: url)
        return failure
    }

    private func settle(_ error: Error?, normalized: ProducerDocument, url: URL) {
        if let error {
            isSuspended = true
            refreshStatus()
            onFailure(error, url)
        } else {
            baseline = normalized
            isSuspended = false
            lastWrite = Date()
            refreshStatus()
        }
    }

    public func refreshStatus() {
        guard let engine else { return }
        let next: DocumentSaveStatus
        if engine.currentDocumentURL == nil {
            next = .untitled
        } else if isSuspended {
            next = .failed
        } else if inFlight > 0 || isDirty {
            next = .saving
        } else {
            next = .saved
        }
        if status != next { status = next }
    }

    public func refreshRevert() {
        guard let engine, engine.currentDocumentURL != nil, let manualBaseline else {
            canRevert = false
            return
        }
        canRevert = engine.makeDocument().normalizedForComparison() != manualBaseline.normalizedForComparison()
    }

    public func markManualSave() {
        guard let engine, engine.currentDocumentURL != nil else {
            manualBaseline = nil
            refreshRevert()
            refreshStatus()
            return
        }
        manualBaseline = engine.makeDocument()
        isSuspended = false
        refreshRevert()
        refreshStatus()
    }

    public func markOpened() {
        markManualSave()
    }

    public func revertDocument() -> ProducerDocument? {
        canRevert ? manualBaseline : nil
    }
}
