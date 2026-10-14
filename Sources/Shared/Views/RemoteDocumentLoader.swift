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

struct RemoteLoadFileButton: View {
    @ObservedObject var session: RemoteProducerSession
    let tint: Color
    @State private var isChoosing = false

    var body: some View {
        Button("Load File…") { isChoosing = true }
            .producerSecondaryButton()
            .tint(tint)
            .disabled(!session.isLive)
            .fileImporter(isPresented: $isChoosing, allowedContentTypes: RemoteDocumentLoader.contentTypes) { result in
                switch result {
                case .success(let url):
                    RemoteDocumentLoader.send(url, to: session)
                case .failure(let error):
                    session.noteFailure("Couldn’t open that file.", detail: error.localizedDescription)
                }
            }
    }
}
#endif
