// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

final class PCOReferenceCache: @unchecked Sendable {
    private let lock = NSLock()
    private var attachments: [String: [PCOAttachmentInfo]] = [:]
    private var charts: [String: PCOArrangementChart] = [:]

    func attachments(for key: String) -> [PCOAttachmentInfo]? {
        lock.lock()
        defer { lock.unlock() }
        return attachments[key]
    }

    func store(_ value: [PCOAttachmentInfo], for key: String) {
        lock.lock()
        defer { lock.unlock() }
        attachments[key] = value
    }

    func chart(for key: String) -> PCOArrangementChart? {
        lock.lock()
        defer { lock.unlock() }
        return charts[key]
    }

    func store(_ value: PCOArrangementChart, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        charts[key] = value
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        attachments.removeAll()
        charts.removeAll()
    }
}

extension CueEngine {
    public var canBrowsePCOReference: Bool {
        isPCOConnected && !isRemoteMirror
    }

    public func invalidatePCOReferenceCache() {
        pcoReferenceCache.removeAll()
    }

    public func pcoAttachments(for owner: PCOAttachmentOwner, forceRefresh: Bool = false) async throws -> [PCOAttachmentInfo] {
        if !forceRefresh, let cached = pcoReferenceCache.attachments(for: owner.cacheKey) {
            return cached
        }
        let fetched = try await pcoClient.fetchAttachments(for: owner)
        pcoReferenceCache.store(fetched, for: owner.cacheKey)
        return fetched
    }

    public func pcoArrangementChart(songId: String, arrangementId: String, forceRefresh: Bool = false) async throws -> PCOArrangementChart {
        let key = "\(songId)/\(arrangementId)"
        if !forceRefresh, let cached = pcoReferenceCache.chart(for: key) {
            return cached
        }
        let fetched = try await pcoClient.fetchArrangementChart(songId: songId, arrangementId: arrangementId)
        pcoReferenceCache.store(fetched, for: key)
        return fetched
    }

    public func downloadPCOAttachment(_ attachment: PCOAttachmentInfo, owner: PCOAttachmentOwner) async throws -> URL {
        let signed = try await pcoClient.openAttachment(attachment.id, owner: owner)
        return try await pcoClient.downloadAttachment(from: signed, suggestedName: attachment.filename ?? attachment.title)
    }
}
