// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct LaunchSettingsSection: View {
    @EnvironmentObject var preferences: LaunchPreferences
    @State private var isChoosingFile = false

    private var fileTypes: [UTType] {
        [ProducerDocument.fileExtension, ProducerDocument.templateExtension]
            .map { UTType(filenameExtension: $0) ?? .json }
    }

    var body: some View {
        Picker("When the app opens", selection: $preferences.behavior) {
            ForEach(LaunchBehavior.allCases) { behavior in
                Text(behavior.title).tag(behavior)
            }
        }

        if preferences.behavior == .openFile {
            HStack {
                if let url = preferences.fileURL {
                    Image(systemName: preferences.isTemplate ? "doc.on.doc.fill" : "doc.text.fill")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(url.deletingPathExtension().lastPathComponent)
                        Text(preferences.isTemplate ? "Template — opens as a new untitled document" : "Document")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No file chosen")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(preferences.fileURL == nil ? "Choose…" : "Change…") { isChoosingFile = true }
                if preferences.fileURL != nil {
                    Button("Clear", role: .destructive) { preferences.clearFile() }
                }
            }
            .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: fileTypes) { result in
                if case .success(let url) = result { preferences.setFile(url) }
            }
        }
    }
}
#endif
