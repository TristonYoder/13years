// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let thirteenYearsDocument = UTType(exportedAs: "dev.7co.13years.document")
    static let thirteenYearsTemplate = UTType(exportedAs: "dev.7co.13years.template")
}

#if !os(tvOS)
struct ProducerDocumentFile: FileDocument {
    static var readableContentTypes: [UTType] { [.thirteenYearsDocument, .thirteenYearsTemplate] }
    static var writableContentTypes: [UTType] { [.thirteenYearsDocument, .thirteenYearsTemplate] }

    var document: ProducerDocument
    var isTemplate: Bool

    init(_ document: ProducerDocument, isTemplate: Bool = false) {
        self.document = isTemplate ? document.asTemplate() : document
        self.isTemplate = isTemplate
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        document = try ProducerDocument.decoded(from: data)
        isTemplate = configuration.contentType == .thirteenYearsTemplate
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try document.encoded())
    }
}
#endif
