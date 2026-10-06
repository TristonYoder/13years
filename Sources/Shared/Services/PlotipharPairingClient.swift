// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public final class PlotipharPairingClient: @unchecked Sendable {
    public static let apiBase = URL(string: "https://plotiphar.com")!

    private static let userAgent = "ThirteenYearsProducer/1 (+https://plotiphar.com)"
    private static let deviceKind = "thirteenyears-producer"

    public init() {}

    public func startPairing(deviceName: String) async throws -> PlotipharPairingStart {
        let response = try await post(path: "api/auth/device/start", body: [
            "client": "output-device",
            "name": deviceName,
            "deviceKind": Self.deviceKind,
        ])

        guard
            let code = response["code"] as? String,
            let deviceToken = response["deviceToken"] as? String,
            let expiresAtString = response["expiresAt"] as? String,
            let expiresAt = Self.parseISO8601(expiresAtString)
        else {
            throw PlotipharPairingError.malformedResponse
        }

        return PlotipharPairingStart(code: code, expiresAt: expiresAt, deviceToken: deviceToken)
    }

    public func pollStatus(deviceToken: String) async throws -> PlotipharPairingStatus {
        let response = try await post(path: "api/auth/device/status", body: [
            "deviceToken": deviceToken,
        ])

        switch response["status"] as? String {
        case "approved":
            guard let sessionToken = response["sessionToken"] as? String else {
                throw PlotipharPairingError.malformedResponse
            }
            return .approved(sessionToken: sessionToken, screenId: response["screenId"] as? String)
        case "expired":
            return .expired
        default:
            return .pending
        }
    }

    static func parseISO8601(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }

    private func post(path: String, body: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: Self.apiBase.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PlotipharPairingError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlotipharPairingError.malformedResponse
        }
        return json
    }
}

public struct PlotipharPairingStart: Sendable {
    public let code: String
    public let expiresAt: Date
    public let deviceToken: String
}

public enum PlotipharPairingStatus: Sendable, Equatable {
    case pending
    case approved(sessionToken: String, screenId: String?)
    case expired
}

public enum PlotipharPairingError: Error, LocalizedError {
    case requestFailed(Int)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .requestFailed(let status):
            return "Plotiphar pairing request failed (HTTP \(status))."
        case .malformedResponse:
            return "Plotiphar returned an unexpected response."
        }
    }
}
