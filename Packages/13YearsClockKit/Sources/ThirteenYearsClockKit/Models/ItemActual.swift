// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct ItemActual: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var itemId: String
    public var eventTimeId: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var lengthSeconds: Int?

    public var id: String { "\(itemId)\u{1F}\(eventTimeId ?? Self.adhocKey)" }

    public static let adhocKey = "adhoc"
    public static let rehearsalKey = "rehearsal"

    public init(itemId: String, eventTimeId: String?, startedAt: Date, endedAt: Date? = nil, lengthSeconds: Int? = nil) {
        self.itemId = itemId
        self.eventTimeId = eventTimeId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lengthSeconds = lengthSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case itemId, eventTimeId, startedAt, endedAt, lengthSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemId = try container.decode(String.self, forKey: .itemId)
        eventTimeId = try container.decodeIfPresent(String.self, forKey: .eventTimeId)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        lengthSeconds = try container.decodeIfPresent(Int.self, forKey: .lengthSeconds)
    }
}

public enum ItemActuals {
    public static func skipsKey(eventTimeId: String?) -> String {
        eventTimeId ?? ItemActual.adhocKey
    }

    public static func sortedSkips(_ skips: [String: Set<String>]) -> [String: [String]]? {
        let mapped = skips.compactMapValues { $0.isEmpty ? nil : $0.sorted() }
        return mapped.isEmpty ? nil : mapped
    }

    public static func skips(from stored: [String: [String]]?, validItemIds: Set<String>) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for (key, ids) in stored ?? [:] {
            let kept = Set(ids).intersection(validItemIds)
            if !kept.isEmpty { result[key] = kept }
        }
        return result
    }

    public static func pruned(_ actuals: [ItemActual], validItemIds: Set<String>) -> [ItemActual] {
        actuals.filter { validItemIds.contains($0.itemId) }
    }
}
