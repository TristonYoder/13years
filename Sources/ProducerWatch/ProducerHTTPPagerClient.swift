// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct ProducerHTTPPagerClient: Sendable {
    public static let defaultPort = 13390

    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    public enum ClientError: LocalizedError {
        case invalidURL
        case badStatus(Int)
        case emptyResponse

        public var errorDescription: String? {
            switch self {
            case .invalidURL: return "Producer address isn't a valid host/IP."
            case .badStatus(let status): return "Producer replied with HTTP \(status)."
            case .emptyResponse: return "Producer returned an empty response."
            }
        }
    }

    public func fetchState() async throws -> ControlAPIState {
        let data = try await request("GET", path: "v1/state")
        return try ControlAPIJSON.decoder.decode(ControlAPIState.self, from: data)
    }

    public func sendMessage(text: String, targetRoleId: String?, senderRoleId: String?) async throws {
        let body = try ControlAPIJSON.encoder.encode(
            ControlAPIRequests.MessageBody(
                text: text,
                targetRoleId: targetRoleId,
                senderRoleId: senderRoleId,
                isHighPriority: nil
            )
        )
        _ = try await request("POST", path: "v1/messages", body: body)
    }

    private func request(_ method: String, path: String, body: Data? = nil) async throws -> Data {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/" + path
        guard let url = components.url else { throw ClientError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 4
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else { throw ClientError.badStatus(http.statusCode) }
        return data
    }
}