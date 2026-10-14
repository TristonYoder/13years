// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct Waypoint: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public var name: String

    public init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }

    public static let symbolName = "signpost.right"

    public var slug: String { Self.slug(for: name) }

    public static func slug(for raw: String) -> String {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = ""
        result.reserveCapacity(lowered.count)
        var lastWasDash = false
        for scalar in lowered.unicodeScalars {
            if ("a"..."z").contains(Character(scalar)) || ("0"..."9").contains(Character(scalar)) {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
        }
        while result.hasPrefix("-") { result.removeFirst() }
        while result.hasSuffix("-") { result.removeLast() }
        return result
    }

    public func matches(_ raw: String) -> Bool {
        if raw == id { return true }
        if raw.caseInsensitiveCompare(name) == .orderedSame { return true }
        let rawSlug = Self.slug(for: raw)
        return !rawSlug.isEmpty && rawSlug == slug
    }
}
