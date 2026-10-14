// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS) || os(iOS)
import SwiftUI
import UniformTypeIdentifiers

struct LaunchSettingsSection: View {
    @EnvironmentObject var preferences: LaunchPreferences
    @State private var isChoosingFile = false
    var recentRemoteHosts: [RecentItem] = RecentItems.load(defaults: .standard).items.filter { $0.kind == .remoteHost }

    private var fileTypes: [UTType] {
        [
            .thirteenYearsDocument,
            .thirteenYearsTemplate,
            UTType(filenameExtension: ProducerDocument.fileExtension),
            UTType(filenameExtension: ProducerDocument.templateExtension)
        ].compactMap { $0 }
    }

    var body: some View {
        Picker("When the app opens", selection: $preferences.behavior) {
            ForEach(LaunchBehavior.allCases) { behavior in
                Text(behavior.title).tag(behavior)
            }
        }

        if preferences.behavior == .connectRemote {
            if !recentRemoteHosts.isEmpty {
                Picker("Recent hosts", selection: $preferences.remoteAddress) {
                    Text("Choose…").tag("")
                    ForEach(recentRemoteHosts) { item in
                        if let endpoint = item.endpoint {
                            Text("\(item.title) — \(endpoint.address)").tag(endpoint.address)
                        }
                    }
                }
            }
            TextField("host or host:port", text: $preferences.remoteAddress)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            if preferences.action == .showLauncher {
                Text("Enter a valid host to connect on launch. Until then the start window opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("If it can’t be reached, the start window opens with the error.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    Text("No document chosen")
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

            if let error = preferences.bookmarkError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
#endif
