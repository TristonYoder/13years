// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

struct PendingPCOSignIn {
    let verifier: String
    let state: String
    let createdAt: Date
}

extension CueEngine {
    static let delegatedSignInLifetime: TimeInterval = 600

    public func beginDelegatedPCOSignIn() throws -> (authorizeURL: URL, state: String) {
        guard !isRemoteMirror else { throw RemoteLoadError.notMirror }
        guard !OAuthConfig.clientID.isEmpty else { throw OAuthError.missingClientID }
        let pkce = PKCEPair.generate()
        let state = PKCEPair.randomState()
        pendingPCOSignIn = PendingPCOSignIn(verifier: pkce.verifier, state: state, createdAt: pcoSignInClock())
        return (OAuthConfig.authorizeURL(codeChallenge: pkce.challenge, state: state), state)
    }

    public func completeDelegatedPCOSignIn(code: String, state: String) async throws {
        guard !isRemoteMirror else { throw RemoteLoadError.notMirror }
        guard let pending = pendingPCOSignIn else { throw OAuthError.noPendingSignIn }
        pendingPCOSignIn = nil
        guard pending.state == state else { throw OAuthError.stateMismatch }
        guard pcoSignInClock().timeIntervalSince(pending.createdAt) <= Self.delegatedSignInLifetime else {
            throw OAuthError.signInExpired
        }
        let tokens = try await pcoTokenExchange(code, pending.verifier)
        try await finishPCOSignIn(with: tokens)
    }

    func signInWithPCOThroughRemote() {
        guard let remote = remoteCommands else { return }
        Task {
            do {
                let data = try await remote.request(.pcoAuthorize)
                let grant = try ControlAPIJSON.decoder.decode(ControlAPIRequests.PCOAuthorization.self, from: data)
                guard let url = URL(string: grant.authorizeURL) else { throw OAuthError.missingAuthorizationCode }
                let callback = try await OAuthSignIn().authenticate(url: url)
                guard let code = OAuthSignIn.queryValue("code", in: callback) else { throw OAuthError.missingAuthorizationCode }
                let returnedState = OAuthSignIn.queryValue("state", in: callback) ?? grant.state
                remote.send(.pcoAuthorizeComplete(code: code, state: returnedState))
            } catch {
                AppLog.cue.error("CueEngine: remote PCO sign-in error: \(error.localizedDescription, privacy: .private)")
                if case OAuthError.userCancelled = error { return }
                self.pcoLastError = error.localizedDescription
            }
        }
    }
}
