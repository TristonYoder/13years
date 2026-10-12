// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
import Network

public struct RemoteEndpoint: Equatable, Hashable, Sendable {
    public static let defaultPort = 13390

    public var host: String
    public var port: Int
    public var name: String

    public init(host: String, port: Int = RemoteEndpoint.defaultPort, name: String? = nil) {
        self.host = host
        self.port = port
        self.name = name ?? host
    }

    public var address: String {
        let hostPart = host.contains(":") ? "[\(host)]" : host
        return port == Self.defaultPort ? hostPart : "\(hostPart):\(port)"
    }

    public func url(scheme: String = "http", path: String = "") -> URL? {
        let hostPart = host.contains(":") ? "[\(host.replacingOccurrences(of: "%", with: "%25"))]" : host
        return URL(string: "\(scheme)://\(hostPart):\(port)\(path)")
    }

    public var socketURL: URL? { url(scheme: "ws", path: "/v1/socket") }

    public static func parse(_ text: String, name: String? = nil) -> RemoteEndpoint? {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["http://", "https://", "ws://", "wss://"] where rest.lowercased().hasPrefix(prefix) {
            rest = String(rest.dropFirst(prefix.count))
            break
        }
        if let slash = rest.firstIndex(of: "/") { rest = String(rest[..<slash]) }
        guard !rest.isEmpty, !rest.contains(where: { $0.isWhitespace }) else { return nil }

        let host: String
        var portText: String?

        if rest.hasPrefix("[") {
            guard let close = rest.firstIndex(of: "]") else { return nil }
            host = String(rest[rest.index(after: rest.startIndex)..<close])
            let tail = rest[rest.index(after: close)...]
            if !tail.isEmpty {
                guard tail.hasPrefix(":") else { return nil }
                portText = String(tail.dropFirst())
            }
            guard IPv6Address(host) != nil else { return nil }
        } else if rest.filter({ $0 == ":" }).count >= 2 {
            host = rest
            guard IPv6Address(host) != nil else { return nil }
        } else {
            if let colon = rest.firstIndex(of: ":") {
                host = String(rest[..<colon])
                portText = String(rest[rest.index(after: colon)...])
            } else {
                host = rest
            }
            guard isValidHostname(host) else { return nil }
        }

        var port = defaultPort
        if let portText {
            guard let parsed = Int(portText), (1...65535).contains(parsed) else { return nil }
            port = parsed
        }
        return RemoteEndpoint(host: host, port: port, name: name)
    }

    private static func isValidHostname(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        guard host.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.contains(where: \.isEmpty) else { return false }
        if host.allSatisfy({ $0.isNumber || $0 == "." }) {
            let parts = labels.compactMap { Int($0) }
            return parts.count == 4 && labels.count == 4 && parts.allSatisfy { (0...255).contains($0) }
        }
        return true
    }
}

public struct RemoteProducerHealth: Decodable, Equatable, Sendable {
    public var service: String
    public var version: String
    public var device: String
    public var role: String
    public var deviceId: String?

    public static let serviceName = "13 Years Control API"
}
