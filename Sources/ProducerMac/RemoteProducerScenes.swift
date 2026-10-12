// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

struct RemoteWindowFocusKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var isRemoteProducerWindow: Bool? {
        get { self[RemoteWindowFocusKey.self] }
        set { self[RemoteWindowFocusKey.self] = newValue }
    }
}

enum RemoteWindowIDs {
    static let connect = "connect"
    static let remote = "remote"
    static let connectTitle = "Connect To…"
    static let remoteTitlePrefix = "Remote:"

    static func isAuxiliary(title: String) -> Bool {
        title == connectTitle || title.hasPrefix(remoteTitlePrefix)
    }
}

struct MacConnectWindow: View {
    @ObservedObject var hub: RemoteProducerHub
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ConnectToView(
            onConnected: { session in
                hub.activate(session)
                openWindow(id: RemoteWindowIDs.remote)
                dismissWindow(id: RemoteWindowIDs.connect)
            },
            onCancel: { dismissWindow(id: RemoteWindowIDs.connect) }
        )
    }
}

struct MacRemoteWindow: View {
    @ObservedObject var hub: RemoteProducerHub
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if let session = hub.session {
                RemoteProducerContainerView(session: session) {
                    hub.disconnect()
                    dismissWindow(id: RemoteWindowIDs.remote)
                }
                .navigationTitle("\(RemoteWindowIDs.remoteTitlePrefix) \(session.displayName)")
            } else {
                Text("Not connected")
                    .foregroundStyle(.secondary)
                    .navigationTitle("\(RemoteWindowIDs.remoteTitlePrefix) Not Connected")
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .focusedSceneValue(\.isRemoteProducerWindow, true)
        .onChange(of: hub.session == nil) { _, isGone in
            if isGone { dismissWindow(id: RemoteWindowIDs.remote) }
        }
        .onDisappear { hub.disconnect() }
    }
}

struct MacFileCommands: Commands {
    @ObservedObject var documents: DocumentController
    let engine: CueEngine
    let flashingWindow: PagerFlashingWindowController
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.isRemoteProducerWindow) private var isRemoteFrontmost

    private var isLocalDisabled: Bool { isRemoteFrontmost == true }
    private var isDocumentActionsEnabled: Bool { !documents.isLauncherPresented && !isLocalDisabled }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Document…") { documents.newDocument(engine) }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(isLocalDisabled)
            Button("New from Template…") { documents.newFromTemplate(engine) }
                .disabled(isLocalDisabled)
            Button("Open…") { documents.open(engine) }
                .keyboardShortcut("o")
                .disabled(isLocalDisabled)
            Menu("Open Recent") {
                ForEach(documents.recentURLs, id: \.self) { url in
                    Button(RecentDocuments.title(for: url)) { documents.openRecent(url, in: engine) }
                }
                if !documents.recentURLs.isEmpty { Divider() }
                Button("Clear Menu") { documents.clearRecents() }
                    .disabled(documents.recentURLs.isEmpty)
            }
            .disabled(!isDocumentActionsEnabled)
            Button(RemoteWindowIDs.connectTitle) { openWindow(id: RemoteWindowIDs.connect) }
                .keyboardShortcut("k", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { documents.save(engine) }
                .keyboardShortcut("s")
                .disabled(!isDocumentActionsEnabled)
            Button("Save As…") { documents.saveAs(engine) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!isDocumentActionsEnabled)
            Button("Revert to Last Save") { documents.revert(engine) }
                .disabled(!documents.canRevert || !isDocumentActionsEnabled)
            Button("Save as Template…") { documents.saveAsTemplate(engine) }
                .disabled(!isDocumentActionsEnabled)
        }
        CommandGroup(after: .newItem) {
            Button("Flash a Pager…") {
                flashingWindow.present(cueEngine: engine)
            }
            .keyboardShortcut("F", modifiers: [.command, .shift])
            .disabled(isLocalDisabled)
        }
    }
}
