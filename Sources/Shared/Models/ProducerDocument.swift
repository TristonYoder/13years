// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct ProducerDocument: Codable, Equatable, Sendable {
    public static let fileExtension = "13years"
    public static let templateExtension = "13yearstemplate"
    public static let currentVersion = 1

    public struct Settings: Codable, Equatable, Sendable {
        public var hourFormatThreshold: HourFormatThreshold
        public var pcoDefaultServiceTypeId: String?
        public var plotipharRelayHost: String

        public init(
            hourFormatThreshold: HourFormatThreshold,
            pcoDefaultServiceTypeId: String?,
            plotipharRelayHost: String
        ) {
            self.hourFormatThreshold = hourFormatThreshold
            self.pcoDefaultServiceTypeId = pcoDefaultServiceTypeId
            self.plotipharRelayHost = plotipharRelayHost
        }
    }

    public var version: Int
    public var savedAt: Date
    public var roles: [RoleCue]
    public var selectedRoleIds: [String]?
    public var waypoints: [Waypoint]
    public var serviceSchedules: [ServiceSchedule]
    public var planItems: [PCOTimerItem]
    public var activeItemIndex: Int
    public var settings: Settings

    public init(
        version: Int = ProducerDocument.currentVersion,
        savedAt: Date = Date(),
        roles: [RoleCue],
        selectedRoleIds: [String]? = nil,
        waypoints: [Waypoint],
        serviceSchedules: [ServiceSchedule],
        planItems: [PCOTimerItem],
        activeItemIndex: Int,
        settings: Settings
    ) {
        self.version = version
        self.savedAt = savedAt
        self.roles = roles
        self.selectedRoleIds = selectedRoleIds
        self.waypoints = waypoints
        self.serviceSchedules = serviceSchedules
        self.planItems = planItems
        self.activeItemIndex = activeItemIndex
        self.settings = settings
    }

    public func asTemplate() -> ProducerDocument {
        var template = self
        template.savedAt = Date()
        template.roles = roles.map { role in
            var role = role
            role.state = .off
            return role
        }
        template.planItems = planItems.map { item in
            var item = item
            item.elapsedSeconds = 0
            item.isRunning = false
            return item
        }
        return template
    }

    public enum LoadError: LocalizedError {
        case newerVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .newerVersion(let version):
                return "This file was saved by a newer version of 13 Years Producer (format \(version))."
            }
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> ProducerDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ProducerDocument.self, from: data)
        guard document.version <= currentVersion else { throw LoadError.newerVersion(document.version) }
        return document
    }

    public func write(to url: URL) throws {
        try encoded().write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> ProducerDocument {
        try decoded(from: Data(contentsOf: url))
    }
}
