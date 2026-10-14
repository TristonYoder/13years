// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI
import AppKit

struct MacFileCommands: Commands {
    @ObservedObject var documents: DocumentController
    @ObservedObject var hub: RemoteProducerHub
    let engine: CueEngine
    let flashingWindow: PagerFlashingWindowController

    private var isLocalDisabled: Bool { hub.isRemoteActive }
    private var isDocumentActionsEnabled: Bool { !documents.isLauncherPresented && !isLocalDisabled }
    private var isOpenEnabled: Bool { hub.isRemoteActive || !documents.isLauncherPresented }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Document…") { documents.newDocument(engine) }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(isLocalDisabled)
            Button("New from Template…") { documents.newFromTemplate(engine) }
            Button("Open…") { documents.open(engine) }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(documents.recentURLs, id: \.self) { url in
                    Button(RecentDocuments.title(for: url)) { documents.openRecent(url, in: engine) }
                }
                if !documents.recentURLs.isEmpty { Divider() }
                Button("Clear Menu") { documents.clearRecents() }
                    .disabled(documents.recentURLs.isEmpty)
            }
            .disabled(!isOpenEnabled)
            Button("Connect To…") { hub.isConnectPresented = true }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Disconnect") { hub.disconnect() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!hub.isRemoteActive)
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

struct RemoteMenuBarItems: View {
    @ObservedObject var session: RemoteProducerSession

    var body: some View {
        Text("Remote: \(session.displayName)")
        Button("Standby Selected (Yellow)") { session.engine.setCueForSelectedRoles(.standby) }
            .disabled(!session.isLive)
        Button("GO Selected (Green)") { session.engine.setCueForSelectedRoles(.go) }
            .disabled(!session.isLive)
        Button("Clear All Cues") { session.engine.clearAllCues() }
            .disabled(!session.isLive)
        Divider()
        Text("Local")
    }
}

final class WindowCloseInterceptor: NSObject, NSWindowDelegate {
    weak var original: NSWindowDelegate?
    var decide: () -> WindowClosePolicy = { .closeNormally }
    var disconnect: () -> Void = {}

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        switch decide() {
        case .disconnectRemote:
            disconnect()
            return false
        case .quitApp:
            NSApp.terminate(nil)
            return false
        case .closeNormally:
            return original?.windowShouldClose?(sender) ?? true
        }
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if original?.responds(to: selector) == true { return original }
        return super.forwardingTarget(for: selector)
    }
}

struct WindowCloseHandler: NSViewRepresentable {
    let decide: () -> WindowClosePolicy
    let disconnect: () -> Void

    func makeCoordinator() -> WindowCloseInterceptor { WindowCloseInterceptor() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        install(on: view, interceptor: context.coordinator)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        install(on: view, interceptor: context.coordinator)
    }

    private func install(on view: NSView, interceptor: WindowCloseInterceptor) {
        interceptor.decide = decide
        interceptor.disconnect = disconnect
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window, window.delegate !== interceptor else { return }
            interceptor.original = window.delegate
            window.delegate = interceptor
        }
    }
}
