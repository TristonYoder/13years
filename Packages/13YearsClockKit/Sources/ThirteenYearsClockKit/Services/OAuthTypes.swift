// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public enum OAuthConfig {
    public static var clientID: String {
        if let bundled = Bundle.main.object(forInfoDictionaryKey: "PCOOAuthClientID") as? String, !bundled.isEmpty {
            return bundled
        }
        return ProcessInfo.processInfo.environment["THIRTEEN_PCO_CLIENT_ID"] ?? ""
    }
    public static let redirectURI = "thirteenyears://oauth/callback"
    public static let callbackScheme = "thirteenyears"
    public static let scope = "services"

    public static let authorizeURL = URL(string: "https://api.planningcenteronline.com/oauth/authorize")!
    public static let tokenURL = URL(string: "https://api.planningcenteronline.com/oauth/token")!

    public static func authorizeURL(codeChallenge: String, state: String? = nil) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
        ]
        if let state { items.append(URLQueryItem(name: "state", value: state)) }
        items.append(URLQueryItem(name: "code_challenge", value: codeChallenge))
        items.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        components.queryItems = items
        return components.url!
    }
}

public struct PKCEPair: Sendable {
    public let verifier: String
    public let challenge: String

    public static func randomState() -> String {
        randomURLSafeString(byteCount: 16)
    }

    public static func generate() -> PKCEPair {
        let verifier = randomURLSafeString(byteCount: 32)
        let challenge = base64URLEncode(Data(SHA256.hash(data: Data(verifier.utf8))))
        return PKCEPair(verifier: verifier, challenge: challenge)
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        #if canImport(Security)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        #else
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max, using: &generator) }
        #endif
        return base64URLEncode(Data(bytes))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public struct OAuthTokens: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool { Date() >= expiresAt }
}

public enum OAuthError: Error, LocalizedError {
    case userCancelled
    case missingAuthorizationCode
    case missingClientID
    case tokenRequestFailed(status: Int, body: String)
    case noPendingSignIn
    case stateMismatch
    case signInExpired

    public var errorDescription: String? {
        switch self {
        case .userCancelled: return "PCO Sign-in was cancelled."
        case .missingAuthorizationCode: return "Missing PCO authorization code."
        case .missingClientID: return "No Planning Center OAuth client ID is configured. Set PCO_OAUTH_CLIENT_ID in Config/Local.xcconfig, or THIRTEEN_PCO_CLIENT_ID on a headless host."
        case .tokenRequestFailed(let status, let body): return "PCO OAuth error HTTP \(status): \(body)"
        case .noPendingSignIn: return "No Planning Center sign-in is in progress. Start again."
        case .stateMismatch: return "The Planning Center sign-in response didn't match this request. Start again."
        case .signInExpired: return "The Planning Center sign-in took too long. Start again."
        }
    }
}
