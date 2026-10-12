// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct PagerURLBuilder: Equatable, Sendable {
    public enum Layout: String, CaseIterable, Identifiable, Sendable {
        case auto
        case landscape
        case portrait
        case lowerThird = "lowerthird"

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .auto: return "Auto"
            case .landscape: return "Landscape"
            case .portrait: return "Portrait"
            case .lowerThird: return "Lower third"
            }
        }
    }

    public enum CueDisplay: String, CaseIterable, Identifiable, Sendable {
        case viewerChoice
        case outline
        case full

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .viewerChoice: return "Viewer's choice"
            case .outline: return "Outline"
            case .full: return "Full screen colour"
            }
        }
    }

    public var host: String
    public var port: Int
    public var role: String?
    public var layout: Layout
    public var cue: CueDisplay
    public var showSettings: Bool
    public var showMessages: Bool

    public init(
        host: String,
        port: Int = RemoteEndpoint.defaultPort,
        role: String? = nil,
        layout: Layout = .auto,
        cue: CueDisplay = .viewerChoice,
        showSettings: Bool = true,
        showMessages: Bool = true
    ) {
        self.host = host
        self.port = port
        self.role = role
        self.layout = layout
        self.cue = cue
        self.showSettings = showSettings
        self.showMessages = showMessages
    }

    public var urlString: String {
        var items: [String] = []
        if let role, !role.isEmpty { items.append("role=" + Self.encode(role)) }
        if layout != .auto { items.append("layout=" + layout.rawValue) }
        switch cue {
        case .viewerChoice: break
        case .outline: items.append("cue=outline")
        case .full: items.append("cue=full")
        }
        if !showSettings { items.append("settings=0") }
        if !showMessages { items.append("messages=0") }
        let query = items.isEmpty ? "" : "?" + items.joined(separator: "&")
        return base + WebPager.path + query
    }

    public var url: URL? { URL(string: urlString) }

    private var base: String {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        let bare = trimmed.hasPrefix("[") && trimmed.hasSuffix("]") ? String(trimmed.dropFirst().dropLast()) : trimmed
        let hostPart = bare.contains(":") ? "[\(bare.replacingOccurrences(of: "%", with: "%25"))]" : bare
        return "http://\(hostPart):\(port)"
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}
