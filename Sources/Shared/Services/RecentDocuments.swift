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
}

enum RecentDocuments {
    static let limit = 10

    static func updated<T: Equatable>(_ list: [T], adding item: T, limit: Int = RecentDocuments.limit) -> [T] {
        var result = list.filter { $0 != item }
        result.insert(item, at: 0)
        return Array(result.prefix(limit))
    }
}
