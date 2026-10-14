// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum SyncHash {
    public static let unitSeparator = "\u{1F}"
    public static let recordSeparator = "\u{1E}"

    private static let offsetBasis: UInt64 = 0xcbf29ce484222325
    private static let prime: UInt64 = 0x100000001b3

    public static func fnv1a64(_ canonical: String) -> String {
        var hash = offsetBasis
        for byte in canonical.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        let hex = String(hash, radix: 16, uppercase: false)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    public enum Section: String, Codable, Sendable, CaseIterable {
        case roles
        case timer
        case plan
        case messages
    }

    public struct Hashes: Codable, Equatable, Sendable {
        public var roles: String
        public var timer: String
        public var plan: String?
        public var messages: String

        public init(roles: String, timer: String, plan: String? = nil, messages: String) {
            self.roles = roles
            self.timer = timer
            self.plan = plan
            self.messages = messages
        }

        public func mismatches(against remote: Hashes) -> [Section] {
            var result: [Section] = []
            if roles != remote.roles { result.append(.roles) }
            if timer != remote.timer { result.append(.timer) }
            if messages != remote.messages { result.append(.messages) }
            if let plan, let remotePlan = remote.plan, plan != remotePlan { result.append(.plan) }
            return result
        }
    }

    public static func rolesCanonical(_ roles: [RoleCue]) -> String {
        var result = ""
        for role in roles {
            result += role.id + unitSeparator + role.name + unitSeparator + role.state.rawValue + recordSeparator
        }
        return result
    }

    public static func timerCanonical(_ anchor: TimerAnchor?) -> String {
        guard let anchor else { return "none" }
        let fields: [String] = [
            anchor.itemId,
            String(anchor.lengthInSeconds),
            anchor.isRunning ? "1" : "0",
            anchor.isDurationActual ? "1" : "0",
            String(anchor.elapsedMs),
            String(anchor.anchorMs),
        ]
        return fields.joined(separator: unitSeparator)
    }

    public static let digestMessageLimit = 16

    public static func messagesCanonical(ids: [String]) -> String {
        ids.joined(separator: recordSeparator)
    }

    public static func messageIdsNewestFirst(_ messages: [InterTeamMessage]) -> [String] {
        Array(sortedNewestFirst(messages).prefix(digestMessageLimit)).map(\.id)
    }

    public static func sortedNewestFirst(_ messages: [InterTeamMessage]) -> [InterTeamMessage] {
        messages.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp > $1.timestamp }
            return Array($0.id.utf8).lexicographicallyPrecedes(Array($1.id.utf8))
        }
    }

    public static func planCanonical(items: [PCOTimerItem], activeItemIndex: Int) -> String {
        var result = ""
        for item in items {
            result += item.id + unitSeparator + item.title + unitSeparator + String(item.lengthInSeconds)
                + unitSeparator + (item.isDurationActual ? "1" : "0") + recordSeparator
        }
        return result + String(activeItemIndex)
    }

    public static func roles(_ roles: [RoleCue]) -> String {
        fnv1a64(rolesCanonical(roles))
    }

    public static func timer(_ anchor: TimerAnchor?) -> String {
        fnv1a64(timerCanonical(anchor))
    }

    public static func messages(_ messages: [InterTeamMessage]) -> String {
        fnv1a64(messagesCanonical(ids: messageIdsNewestFirst(messages)))
    }

    public static func messages(ids: [String]) -> String {
        fnv1a64(messagesCanonical(ids: ids))
    }

    public static func plan(items: [PCOTimerItem], activeItemIndex: Int) -> String {
        fnv1a64(planCanonical(items: items, activeItemIndex: activeItemIndex))
    }
}
