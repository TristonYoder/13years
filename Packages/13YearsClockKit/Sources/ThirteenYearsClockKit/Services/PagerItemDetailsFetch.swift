// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum PagerItemDetailsFetch {
    public static let maxResponseBytes = 512 * 1024
    public static let refreshInterval: TimeInterval = 30
    public static let retryInterval: TimeInterval = 5

    public static func url(host: String, port: Int, itemId: String) -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, (1...65535).contains(port), !itemId.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = trimmed.contains(":") && !trimmed.hasPrefix("[") ? "[" + trimmed + "]" : trimmed
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
