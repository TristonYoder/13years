// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(iOS) || os(macOS)
import SwiftUI
import UniformTypeIdentifiers

enum RemoteDocumentLoader {
    @MainActor
    static func send(_ url: URL, to session: RemoteProducerSession) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let document = try ProducerDocument.read(from: url)
            try session.engine.loadDocumentIntoRemote(document)
        } catch {
            session.noteFailure("Couldn’t send “\(url.lastPathComponent)” to \(session.displayName).", detail: error.localizedDescription)
        }
    }

    static var contentTypes: [UTType] {
        [
            .thirteenYearsDocument,
            .thirteenYearsTemplate,
            UTType(filenameExtension: ProducerDocument.fileExtension),
            UTType(filenameExtension: ProducerDocument.templateExtension)
        ].compactMap { $0 }
    }
}
#endif
