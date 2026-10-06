// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public final class PlotipharClient: @unchecked Sendable {
    public static let apiBase = URL(string: "https://plotiphar.com")!

    private static let userAgent = "ThirteenYearsProducer/1 (+https://plotiphar.com)"

    public var sessionToken: String = ""

    public init() {}

    public struct PlotipharRole: Decodable, Sendable {
        public let id: String
        public let name: String
    }

    public struct PlotipharRoleAssignment: Decodable, Sendable {
        public let roleId: String
        public let personName: String
    }

    public struct PlotipharEvent: Decodable, Sendable {
        public let id: String
        public let pcoPlanId: String?
        public let roleAssignments: [PlotipharRoleAssignment]
    }

    public func fetchRoles() async throws -> [PlotipharRole] {
        try await get(path: "api/roles")
    }

    public func fetchEvents() async throws -> [PlotipharEvent] {
        try await get(path: "api/events")
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        guard !sessionToken.isEmpty else { throw PlotipharClientError.notAuthenticated }

        var request = URLRequest(url: Self.apiBase.appendingPathComponent(path))
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PlotipharClientError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PlotipharClientError.malformedResponse
        }
    }
}

public enum PlotipharClientError: Error, LocalizedError {
    case notAuthenticated
    case requestFailed(Int)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not paired with Plotiphar."
        case .requestFailed(let status):
            return "Plotiphar request failed (HTTP \(status))."
        case .malformedResponse:
            return "Plotiphar returned an unexpected response."
        }
    }
}
