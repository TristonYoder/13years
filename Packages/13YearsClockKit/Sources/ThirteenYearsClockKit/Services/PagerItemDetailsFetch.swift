// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum PagerItemDetailsFetch {
    public static let maxResponseBytes = 512 * 1024
    public static let refreshInterval: TimeInterval = 30
    public static let retryInterval: TimeInterval = 5

    public static func url(host: String, port: Int, itemId: String) -> URL? {
        var trimmed = host.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") { trimmed = String(trimmed.dropFirst().dropLast()) }
        var zone: String?
        if let percent = trimmed.firstIndex(of: "%") {
            zone = String(trimmed[trimmed.index(after: percent)...])
            trimmed = String(trimmed[..<percent])
        }
        guard !trimmed.isEmpty, (1...65535).contains(port), !itemId.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        if trimmed.contains(":") {
            let scoped = zone.map { trimmed + "%25" + $0 } ?? trimmed
            components.percentEncodedHost = "[" + scoped + "]"
        } else {
            components.host = trimmed
        }
        components.port = port
        components.percentEncodedPath = "/v1/plan/items/" + encodePathSegment(itemId)
        return components.url
    }

    public static func source(fromResponse data: Data, expectedItemId: String) -> String? {
        guard data.count <= maxResponseBytes,
              let item = try? ControlAPIJSON.decoder.decode(PCOTimerItem.self, from: data),
              item.id == expectedItemId else { return nil }
        return item.itemDetailsSource(includingDescription: true)
    }

    private static func encodePathSegment(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
