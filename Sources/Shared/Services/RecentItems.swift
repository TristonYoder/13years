// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

enum RecentKind: String, Codable, Equatable {
    case document
    case template
    case remoteHost
}

struct RecentItem: Codable, Equatable, Identifiable {
    var kind: RecentKind
    var bookmark: Data?
    var host: String?
    var port: Int?
    var name: String?
    var lastUsed: Date
    var url: URL?

    private enum CodingKeys: String, CodingKey {
        case kind, bookmark, host, port, name, lastUsed
    }

    init(kind: RecentKind, bookmark: Data? = nil, url: URL? = nil, host: String? = nil, port: Int? = nil, name: String? = nil, lastUsed: Date = Date()) {
        self.kind = kind
        self.bookmark = bookmark
        self.url = url
        self.host = host
        self.port = port
        self.name = name
        self.lastUsed = lastUsed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(RecentKind.self, forKey: .kind) ?? .document
        bookmark = try container.decodeIfPresent(Data.self, forKey: .bookmark)
        host = try container.decodeIfPresent(String.self, forKey: .host)
        port = try container.decodeIfPresent(Int.self, forKey: .port)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        lastUsed = try container.decodeIfPresent(Date.self, forKey: .lastUsed) ?? .distantPast
    }

    static func file(_ url: URL, bookmark: Data, kind: RecentKind = .document, lastUsed: Date = Date()) -> RecentItem {
        RecentItem(kind: kind, bookmark: bookmark, url: url, lastUsed: lastUsed)
    }

    static func remote(_ endpoint: RemoteEndpoint, name: String? = nil, lastUsed: Date = Date()) -> RecentItem {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = (trimmed?.isEmpty == false ? trimmed : nil) ?? endpoint.name
        return RecentItem(kind: .remoteHost, host: endpoint.host, port: endpoint.port, name: label, lastUsed: lastUsed)
    }

    var id: String { identity }

    var identity: String {
        switch kind {
        case .remoteHost:
            return "remote|\((host ?? "").lowercased()):\(port ?? RemoteEndpoint.defaultPort)"
        case .document, .template:
            return "\(kind.rawValue)|\(url?.standardizedFileURL.path ?? bookmark?.base64EncodedString() ?? "")"
        }
    }

    var endpoint: RemoteEndpoint? {
        guard kind == .remoteHost, let host else { return nil }
        return RemoteEndpoint(host: host, port: port ?? RemoteEndpoint.defaultPort, name: name)
    }

    var title: String {
        switch kind {
        case .remoteHost: return name ?? endpoint?.address ?? ""
        case .document, .template: return url.map { RecentDocuments.title(for: $0) } ?? ""
        }
    }

    var subtitle: String {
        switch kind {
        case .remoteHost: return endpoint?.address ?? ""
        case .template: return "Template"
        case .document: return url.map { ($0.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath } ?? ""
        }
    }

    var systemImage: String {
        switch kind {
        case .document: return "doc.text.fill"
        case .template: return "doc.on.doc"
        case .remoteHost: return "antenna.radiowaves.left.and.right"
        }
    }

    var isFile: Bool { kind != .remoteHost }
}

enum RecentItems {
    static let limit = 15
    static let defaultsKey = "recentItems"

    static func updated(_ list: [RecentItem], adding item: RecentItem, limit: Int = RecentItems.limit) -> [RecentItem] {
        var result = list.filter { $0.identity != item.identity }
        result.append(item)
        return Array(sorted(result).prefix(limit))
    }

    static func sorted(_ list: [RecentItem]) -> [RecentItem] {
        list.enumerated()
            .sorted { lhs, rhs in
                lhs.element.lastUsed == rhs.element.lastUsed ? lhs.offset < rhs.offset : lhs.element.lastUsed > rhs.element.lastUsed
            }
            .map(\.element)
    }

    static func load(defaults: UserDefaults) -> (items: [RecentItem], changed: Bool) {
        var changed = false
        var decoded: [RecentItem]
        if let data = defaults.data(forKey: RecentItems.defaultsKey),
           let stored = try? JSONDecoder().decode([RecentItem].self, from: data) {
            decoded = stored
        } else {
            let legacy = defaults.array(forKey: RecentDocuments.defaultsKey) as? [Data] ?? []
            let count = legacy.count
            decoded = legacy.enumerated().map { index, bookmark in
                RecentItem(kind: .document, bookmark: bookmark, lastUsed: Date(timeIntervalSince1970: TimeInterval(count - index)))
            }
            changed = !legacy.isEmpty
        }
        var items: [RecentItem] = []
        for var item in decoded {
            guard item.isFile else {
                items.append(item)
                continue
            }
            guard let bookmark = item.bookmark, let resolved = try? DocumentBookmark.resolved(bookmark) else {
                changed = true
                continue
            }
            if RecentDocuments.availability(of: resolved.url) == .missing {
                changed = true
                continue
            }
            if resolved.bookmark != bookmark { changed = true }
            item.bookmark = resolved.bookmark
            item.url = resolved.url
            items.append(item)
        }
        var seen = Set<String>()
        let unique = sorted(items).filter { seen.insert($0.identity).inserted }
        let capped = Array(unique.prefix(limit))
        if capped.count != items.count { changed = true }
        return (capped, changed)
    }

    static func persist(_ items: [RecentItem], defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: defaultsKey)
        }
        defaults.set(items.filter { $0.kind == .document }.compactMap(\.bookmark), forKey: RecentDocuments.defaultsKey)
    }

    static func pruned(_ items: [RecentItem]) -> [RecentItem] {
        items.filter { item in
            guard item.isFile, let url = item.url else { return true }
            return RecentDocuments.availability(of: url) != .missing
        }
    }
}
