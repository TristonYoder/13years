// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(AuthenticationServices)
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import AuthenticationServices

public final class OAuthSignIn: NSObject, @unchecked Sendable {
    #if os(iOS) || os(macOS)
    private nonisolated(unsafe) let anchor: ASPresentationAnchor
    #endif

    @MainActor
    public override init() {
        #if os(iOS) || os(macOS)
        anchor = Self.resolveAnchor()
        #endif
        super.init()
    }

    #if os(iOS) || os(macOS)
    @MainActor
    private static func resolveAnchor() -> ASPresentationAnchor {
        #if canImport(AppKit)
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #elseif canImport(UIKit)
        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
        #endif
    }
    #endif

    public nonisolated func signIn() async throws -> OAuthTokens {
        guard !OAuthConfig.clientID.isEmpty else { throw OAuthError.missingClientID }
        let pkce = PKCEPair.generate()
        let code = try await authorize(pkce: pkce)
        return try await OAuthTokenExchange.exchange(code: code, verifier: pkce.verifier)
    }

    private nonisolated func authorize(pkce: PKCEPair) async throws -> String {
        let callback = try await authenticate(url: OAuthConfig.authorizeURL(codeChallenge: pkce.challenge))
        guard let code = Self.queryValue("code", in: callback) else { throw OAuthError.missingAuthorizationCode }
        return code
    }

    public nonisolated func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: OAuthConfig.callbackScheme
            ) { callbackURL, error in
                continuation.resume(with: Self.result(from: callbackURL, error: error))
            }
            #if os(iOS) || os(macOS)
            session.presentationContextProvider = self
            #endif
            session.start()
        }
    }

    public nonisolated static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == name })?.value
    }

    private nonisolated static func result(from callbackURL: URL?, error: Error?) -> Result<URL, Error> {
        if let error {
            if case ASWebAuthenticationSessionError.canceledLogin = error {
                return .failure(OAuthError.userCancelled)
            }
            return .failure(error)
        }
        guard let callbackURL else { return .failure(OAuthError.missingAuthorizationCode) }
        return .success(callbackURL)
    }
}

#if os(iOS) || os(macOS)
extension OAuthSignIn: ASWebAuthenticationPresentationContextProviding {
    public nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
#endif
#else
public struct OAuthSignInUnavailableError: Error, LocalizedError {
    public var errorDescription: String? { "Interactive OAuth sign-in is not available on this platform." }
}

public final class OAuthSignIn: NSObject, @unchecked Sendable {
    public override init() {
        super.init()
    }

    public nonisolated func signIn() async throws -> OAuthTokens {
        throw OAuthSignInUnavailableError()
    }

    public nonisolated func authenticate(url: URL) async throws -> URL {
        throw OAuthSignInUnavailableError()
    }

    public nonisolated static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == name })?.value
    }
}
#endif

public enum OAuthTokenExchange {
    public static func exchange(code: String, verifier: String) async throws -> OAuthTokens {
        try await requestToken(formBody: [
            "grant_type": "authorization_code",
            "client_id": OAuthConfig.clientID,
            "code": code,
            "redirect_uri": OAuthConfig.redirectURI,
            "code_verifier": verifier,
        ])
    }

    public static func refresh(_ refreshToken: String) async throws -> OAuthTokens {
        try await requestToken(formBody: [
            "grant_type": "refresh_token",
            "client_id": OAuthConfig.clientID,
            "refresh_token": refreshToken,
        ])
    }

    private static func requestToken(formBody: [String: String]) async throws -> OAuthTokens {
        var request = URLRequest(url: OAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoding.encode(formBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw OAuthError.tokenRequestFailed(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try TokenResponse.decode(data)
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }

    static func decode(_ data: Data) throws -> OAuthTokens {
        let wire = try JSONDecoder().decode(TokenResponse.self, from: data)
        return OAuthTokens(
            accessToken: wire.accessToken,
            refreshToken: wire.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(wire.expiresIn))
        )
    }
}

private enum FormEncoding {
    static func encode(_ fields: [String: String]) -> Data {
        fields
            .map { "\($0.key)=\(percentEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }

    private static func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
    }

    private static let allowedCharacters: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+")
        return set
    }()
}
