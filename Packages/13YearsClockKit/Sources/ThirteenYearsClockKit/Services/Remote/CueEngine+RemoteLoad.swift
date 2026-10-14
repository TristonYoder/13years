// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif

public enum RemoteLoadError: LocalizedError, Equatable {
    case notMirror
    case tooLarge(bytes: Int)
    case notSignedIn

    public var errorDescription: String? {
        switch self {
        case .notMirror:
            return "This Producer isn't connected to a remote one."
        case .tooLarge(let bytes):
            let megabytes = String(format: "%.1f", Double(bytes) / 1_048_576)
            return "This is too large to send to the remote Producer (\(megabytes) MB; the limit is 1 MB)."
        case .notSignedIn:
            return "Sign in to Planning Center on this device first."
        }
    }
}

extension CueEngine {
    var pcoBrowseClient: PCOClient {
        guard isRemoteMirror else { return pcoClient }
        return PCOClient(tokens: localPCOAuthority?.pcoOAuthTokens)
    }

    func bindLocalPCOAuthority() {
        localPCOObservers = []
        guard isRemoteMirror, let authority = localPCOAuthority else { return }
        localPCOObservers = [
            authority.$isPCOConnected.sink { [weak self] connected in
                guard let self else { return }
                if self.isPCOConnected != connected { self.isPCOConnected = connected }
                if !connected {
                    self.pcoServiceTypes = []
                    self.pcoPlans = []
                    self.pcoSelectedServiceTypeId = nil
                }
            },
            authority.$pcoUserName.sink { [weak self] name in
                guard let self, self.pcoUserName != name else { return }
                self.pcoUserName = name
            }
        ]
    }

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
    func loadPlanIntoRemote(title: String?, items: [PCOTimerItem], pco: ControlAPIRequests.DocumentLoadBody.PCOContext? = nil) -> Bool {
        do {
            try sendLoad(ControlAPIRequests.DocumentLoadBody(title: title, items: items, pco: pco))
            return true
        } catch {
            pcoLastError = error.localizedDescription
            return false
        }
    }

    func fetchPCOPlanForRemote(serviceTypeId: String, planId: String) {
        guard let tokens = localPCOAuthority?.pcoOAuthTokens else {
            pcoLastError = RemoteLoadError.notSignedIn.localizedDescription
            return
        }
        let client = PCOClient(tokens: tokens)
        Task {
            do {
                let (title, items) = try await client.fetchPlanItems(serviceTypeId: serviceTypeId, planId: planId)
                let categories = (try? await client.fetchItemNoteCategories(serviceTypeId: serviceTypeId, planId: planId)) ?? []
                pcoLastError = nil
                guard !items.isEmpty else { return }
                let context = ControlAPIRequests.DocumentLoadBody.PCOContext(
                    serviceTypeId: serviceTypeId,
                    planId: planId,
                    noteCategories: categories.map { .init(id: $0.id, name: $0.name) }
                )
                loadPlanIntoRemote(title: title, items: items, pco: context)
            } catch {
                pcoLastError = error.localizedDescription
                AppLog.cue.error("CueEngine: PCO sync for remote error: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    func loadNextServiceForRemote() {
        guard let serviceTypeId = currentPCOServiceTypeId, let planId = currentPCOPlanId else { return }
        guard let tokens = localPCOAuthority?.pcoOAuthTokens else {
            pcoLastError = RemoteLoadError.notSignedIn.localizedDescription
            return
        }
        let client = PCOClient(tokens: tokens)
        Task {
            do {
                guard let nextPlanId = try await client.fetchNextPlanId(serviceTypeId: serviceTypeId, planId: planId) else {
                    pcoLastError = "No next service scheduled yet in Planning Center."
                    return
                }
                pcoLastError = nil
                fetchPCOPlanForRemote(serviceTypeId: serviceTypeId, planId: nextPlanId)
            } catch {
                pcoLastError = error.localizedDescription
            }
        }
    }
}
