// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

enum DocumentBookmark {
    #if os(macOS)
    static let create: URL.BookmarkCreationOptions = .withSecurityScope
    static let resolve: URL.BookmarkResolutionOptions = .withSecurityScope
    #else
    static let create: URL.BookmarkCreationOptions = []
    static let resolve: URL.BookmarkResolutionOptions = []
    #endif

    static func make(for url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData(options: create, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolved(_ data: Data) throws -> (url: URL, bookmark: Data) {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: resolve, relativeTo: nil, bookmarkDataIsStale: &stale)
        guard stale, let fresh = try? make(for: url) else { return (url, data) }
        return (url, fresh)
    }
}

struct RecentEntry: Equatable {
    let url: URL
    let bookmark: Data

    static func == (lhs: RecentEntry, rhs: RecentEntry) -> Bool { lhs.url == rhs.url }
}

enum RecentAvailability: Equatable {
    case present
    case missing
    case unavailable
}

enum RecentDocuments {
    static let limit = 10
    static let defaultsKey = "recentDocumentBookmarks"

    static func updated<T: Equatable>(_ list: [T], adding item: T, limit: Int = RecentDocuments.limit) -> [T] {
        var result = list.filter { $0 != item }
        result.insert(item, at: 0)
        return Array(result.prefix(limit))
    }

    static func title(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    static func isFileNotFound(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError
        }
        if nsError.domain == NSPOSIXErrorDomain { return nsError.code == Int(ENOENT) }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isFileNotFound(underlying)
        }
        return false
    }

    static func availability(of url: URL, fileManager: FileManager = .default) -> RecentAvailability {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if fileManager.fileExists(atPath: url.path) { return .present }
        let parent = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .unavailable
        }
        let placeholder = parent.appendingPathComponent(".\(url.lastPathComponent).icloud")
        if fileManager.fileExists(atPath: placeholder.path) { return .unavailable }
        return .missing
    }

    static func load(defaults: UserDefaults) -> (entries: [RecentEntry], changed: Bool) {
        let stored = defaults.array(forKey: defaultsKey) as? [Data] ?? []
        var changed = false
        let entries: [RecentEntry] = stored.compactMap { data in
            guard let resolved = try? DocumentBookmark.resolved(data) else {
                changed = true
                return nil
            }
            if availability(of: resolved.url) == .missing {
                changed = true
                return nil
            }
            if resolved.bookmark != data { changed = true }
            return RecentEntry(url: resolved.url, bookmark: resolved.bookmark)
        }
        return (entries, changed)
    }

    static func persist(_ entries: [RecentEntry], defaults: UserDefaults) {
        defaults.set(entries.map(\.bookmark), forKey: defaultsKey)
    }

    static func pruned(_ entries: [RecentEntry]) -> [RecentEntry] {
        entries.filter { availability(of: $0.url) != .missing }
    }
}
