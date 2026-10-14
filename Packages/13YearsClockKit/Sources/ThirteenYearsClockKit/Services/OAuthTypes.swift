// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
import CryptoKit

public enum OAuthConfig {
    public static var clientID: String {
        Bundle.main.object(forInfoDictionaryKey: "PCOOAuthClientID") as? String ?? ""
    }
    public static let redirectURI = "thirteenyears://oauth/callback"
    public static let callbackScheme = "thirteenyears"
    public static let scope = "services"

    public static let authorizeURL = URL(string: "https://api.planningcenteronline.com/oauth/authorize")!
    public static let tokenURL = URL(string: "https://api.planningcenteronline.com/oauth/token")!
}

public struct PKCEPair: Sendable {
    public let verifier: String
    public let challenge: String

    public static func generate() -> PKCEPair {
        let verifier = randomURLSafeString(byteCount: 32)
        let challenge = base64URLEncode(Data(SHA256.hash(data: Data(verifier.utf8))))
        return PKCEPair(verifier: verifier, challenge: challenge)
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
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

    public var errorDescription: String? {
        switch self {
        case .userCancelled: return "PCO Sign-in was cancelled."
        case .missingAuthorizationCode: return "Missing PCO authorization code."
        case .missingClientID: return "No Planning Center OAuth client ID is configured. Set PCO_OAUTH_CLIENT_ID in Config/Local.xcconfig."
        case .tokenRequestFailed(let status, let body): return "PCO OAuth error HTTP \(status): \(body)"
        }
    }
}
