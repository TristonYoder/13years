// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum RelayHostPolicy {
    public static let defaultHost = "relay.13years.app"

    public static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        guard let components = components(for: trimmed) else { return nil }
        guard let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        return trimmed
    }

    public static func websocketURL(for raw: String) -> URL? {
        guard let host = normalized(raw), var components = components(for: host) else { return nil }
        components.scheme = "wss"
        if components.path.isEmpty || components.path == "/" {
            components.path = "/relay"
        }
        return components.url
    }

    private static func components(for value: String) -> URLComponents? {
        if let range = value.range(of: "://") {
            let scheme = value[..<range.lowerBound].lowercased()
            guard scheme == "wss" || scheme == "https" else { return nil }
            return URLComponents(string: value)
        }
        return URLComponents(string: "wss://" + value)
    }
}
