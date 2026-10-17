// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum ContentLimits {
    public static let name = 100
    public static let title = 200
    public static let messageText = 2000
    public static let noteValue = 4000
    public static let maxRoles = 64
    public static let maxPlanItems = 500
    public static let maxWaypoints = 200
    public static let maxSchedules = 100
    public static let maxNoteCategories = 64
    public static let identifier = 200
    public static let maxDetailListEntries = 64
    public static let sequenceToken = 16
}

public enum NetworkLimits {
    public static let maxTotalClients = 32
    public static let maxClientsPerRemoteIP = 8
    public static let httpRequestDeadline: TimeInterval = 10
    public static let unupgradedConnectionDeadline: TimeInterval = 30
    public static let lanSilentConnectionTimeout: TimeInterval = 60
    public static let lanIdleTimeout: TimeInterval = 120
}

public struct ConnectionAdmission: Sendable {
    public let maxTotal: Int
    public let maxPerIP: Int
    private var perIP: [String: Int] = [:]
    private var total = 0

    public init(maxTotal: Int = NetworkLimits.maxTotalClients, maxPerIP: Int = NetworkLimits.maxClientsPerRemoteIP) {
        self.maxTotal = maxTotal
        self.maxPerIP = maxPerIP
    }

    public var count: Int { total }

    public mutating func admit(ip: String) -> Bool {
        guard total < maxTotal, perIP[ip, default: 0] < maxPerIP else { return false }
        total += 1
        perIP[ip, default: 0] += 1
        return true
    }

    public mutating func release(ip: String) {
        guard let current = perIP[ip], current > 0 else { return }
        total -= 1
        if current == 1 { perIP.removeValue(forKey: ip) } else { perIP[ip] = current - 1 }
    }
}

public struct ConnectionDeadlines: Sendable {
    public let acceptedAt: Date
    public var requestStartedAt: Date?
    public var lastReceivedAt: Date
    public var isUpgraded = false
    public var hasReceivedFrame = false

    public init(acceptedAt: Date) {
        self.acceptedAt = acceptedAt
        self.lastReceivedAt = acceptedAt
    }

    public func httpExpired(now: Date) -> Bool {
        guard !isUpgraded, let requestStartedAt else { return false }
        return now.timeIntervalSince(requestStartedAt) > NetworkLimits.httpRequestDeadline
    }

    public func unupgradedExpired(now: Date) -> Bool {
        guard !isUpgraded else { return false }
        return now.timeIntervalSince(lastReceivedAt) > NetworkLimits.unupgradedConnectionDeadline
    }

    public func lanExpired(now: Date) -> Bool {
        let idle = now.timeIntervalSince(lastReceivedAt)
        return idle > (hasReceivedFrame ? NetworkLimits.lanIdleTimeout : NetworkLimits.lanSilentConnectionTimeout)
    }
}

public enum ContentValidation {
    public static func tooLong(_ value: String, limit: Int, field: String) -> (message: String, detail: String)? {
        value.count > limit ? ("\(field) is too long", "At most \(limit) characters.") : nil
    }
}
