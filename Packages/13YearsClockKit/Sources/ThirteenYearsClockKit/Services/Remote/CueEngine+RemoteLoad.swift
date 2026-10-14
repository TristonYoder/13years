// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum RemoteLoadError: LocalizedError, Equatable {
    case notMirror
    case tooLarge(bytes: Int)

    public var errorDescription: String? {
        switch self {
        case .notMirror:
            return "This Producer isn't connected to a remote one."
        case .tooLarge(let bytes):
            let megabytes = String(format: "%.1f", Double(bytes) / 1_048_576)
            return "This is too large to send to the remote Producer (\(megabytes) MB; the limit is 1 MB)."
        }
    }
}

extension CueEngine {
    public func loadDocumentIntoRemote(_ document: ProducerDocument) throws {
        try sendLoad(ControlAPIRequests.DocumentLoadBody(document: document))
    }

    func sendLoad(_ body: ControlAPIRequests.DocumentLoadBody) throws {
        guard isRemoteMirror else { throw RemoteLoadError.notMirror }
        let data = try ControlAPIJSON.encoder.encode(body)
        guard data.count <= HTTPMessageParser.maxBodyBytes else { throw RemoteLoadError.tooLarge(bytes: data.count) }
        remoteCommands?.send(.loadDocument(body: data))
    }

    @discardableResult
    func loadPlanIntoRemote(title: String?, items: [PCOTimerItem]) -> Bool {
        do {
            try sendLoad(ControlAPIRequests.DocumentLoadBody(title: title, items: items))
            return true
        } catch {
            pcoLastError = error.localizedDescription
            return false
        }
    }
}
