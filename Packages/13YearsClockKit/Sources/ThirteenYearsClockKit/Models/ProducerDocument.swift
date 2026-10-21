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
        public var clockFormat: ClockFormat?
        public var runSheetLayout: RunSheetLayoutSettings?

        public var runSheetColumnWidths: [String: Double]? {
            get { runSheetLayout?.columnWidths }
            set {
                var layout = runSheetLayout ?? RunSheetLayoutSettings()
                layout.columnWidths = newValue
                runSheetLayout = layout.isDefault ? nil : layout
            }
        }

        public init(
            hourFormatThreshold: HourFormatThreshold,
            pcoDefaultServiceTypeId: String?,
            plotipharRelayHost: String,
            clockFormat: ClockFormat? = nil,
            runSheetLayout: RunSheetLayoutSettings? = nil
        ) {
            self.hourFormatThreshold = hourFormatThreshold
            self.pcoDefaultServiceTypeId = pcoDefaultServiceTypeId
            self.plotipharRelayHost = plotipharRelayHost
            self.clockFormat = clockFormat
            self.runSheetLayout = runSheetLayout
        }

        private enum CodingKeys: String, CodingKey {
            case hourFormatThreshold, pcoDefaultServiceTypeId, plotipharRelayHost, clockFormat, runSheetLayout, runSheetColumnWidths
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hourFormatThreshold = try container.decode(HourFormatThreshold.self, forKey: .hourFormatThreshold)
            pcoDefaultServiceTypeId = try container.decodeIfPresent(String.self, forKey: .pcoDefaultServiceTypeId)
            plotipharRelayHost = try container.decode(String.self, forKey: .plotipharRelayHost)
            clockFormat = try container.decodeIfPresent(ClockFormat.self, forKey: .clockFormat)
            if let layout = try container.decodeIfPresent(RunSheetLayoutSettings.self, forKey: .runSheetLayout) {
                runSheetLayout = layout
            } else if let widths = try container.decodeIfPresent([String: Double].self, forKey: .runSheetColumnWidths) {
                runSheetLayout = RunSheetLayoutSettings(columnWidths: widths)
            } else {
                runSheetLayout = nil
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(hourFormatThreshold, forKey: .hourFormatThreshold)
            try container.encodeIfPresent(pcoDefaultServiceTypeId, forKey: .pcoDefaultServiceTypeId)
            try container.encode(plotipharRelayHost, forKey: .plotipharRelayHost)
            try container.encodeIfPresent(clockFormat, forKey: .clockFormat)
            try container.encodeIfPresent(runSheetLayout, forKey: .runSheetLayout)
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
    public var eventTimes: [EventTime]
    public var liveEventTimeId: String?
    public var pcoPlanContext: PCOPlanContext?
    public var itemActuals: [ItemActual]?
    public var skippedItemIds: [String: [String]]?
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
        eventTimes: [EventTime] = [],
        liveEventTimeId: String? = nil,
        pcoPlanContext: PCOPlanContext? = nil,
        itemActuals: [ItemActual]? = nil,
        skippedItemIds: [String: [String]]? = nil,
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
        self.eventTimes = eventTimes
        self.liveEventTimeId = liveEventTimeId
        self.pcoPlanContext = pcoPlanContext
        self.itemActuals = itemActuals
        self.skippedItemIds = skippedItemIds
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
        template.liveEventTimeId = nil
        template.itemActuals = nil
        return template
    }

    public func normalizedForComparison() -> ProducerDocument {
        var copy = self
        copy.savedAt = .distantPast
        copy.roles = roles.map { role in
            var role = role
            role.state = .off
            role.lastUpdated = .distantPast
            return role
        }
        copy.selectedRoleIds = selectedRoleIds?.sorted()
        copy.pcoPlanContext?.fetchedAt = .distantPast
        copy.planItems = planItems.map { item in
            var item = item
            item.elapsedSeconds = 0
            item.isRunning = false
            return item
        }
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case version, savedAt, roles, selectedRoleIds, waypoints, serviceSchedules, planItems, activeItemIndex, eventTimes, liveEventTimeId, pcoPlanContext, itemActuals, skippedItemIds, settings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date()
        roles = try container.decodeIfPresent([RoleCue].self, forKey: .roles) ?? []
        selectedRoleIds = try container.decodeIfPresent([String].self, forKey: .selectedRoleIds)
        waypoints = try container.decodeIfPresent([Waypoint].self, forKey: .waypoints) ?? []
        serviceSchedules = try container.decodeIfPresent([ServiceSchedule].self, forKey: .serviceSchedules) ?? []
        planItems = try container.decodeIfPresent([PCOTimerItem].self, forKey: .planItems) ?? []
        activeItemIndex = try container.decodeIfPresent(Int.self, forKey: .activeItemIndex) ?? 0
        eventTimes = try container.decodeIfPresent([EventTime].self, forKey: .eventTimes) ?? []
        liveEventTimeId = try container.decodeIfPresent(String.self, forKey: .liveEventTimeId)
        pcoPlanContext = try container.decodeIfPresent(PCOPlanContext.self, forKey: .pcoPlanContext)
        itemActuals = try container.decodeIfPresent([ItemActual].self, forKey: .itemActuals)
        skippedItemIds = try container.decodeIfPresent([String: [String]].self, forKey: .skippedItemIds)
        settings = try container.decodeIfPresent(Settings.self, forKey: .settings)
            ?? Settings(hourFormatThreshold: .never, pcoDefaultServiceTypeId: nil, plotipharRelayHost: "", clockFormat: nil)
    }

    public enum LoadError: LocalizedError {
        case newerVersion(Int)
        case unreadable

        public var errorDescription: String? {
            switch self {
            case .newerVersion(let version):
                return "This document was saved by a newer version of 13 Years Producer (format \(version)). Update the app to open it."
            case .unreadable:
                return "This isn’t a valid 13 Years document, or it’s damaged."
            }
        }
    }

    public func migrated() -> ProducerDocument {
        self
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
        let document: ProducerDocument
        do {
            document = try decoder.decode(ProducerDocument.self, from: data)
        } catch is DecodingError {
            throw LoadError.unreadable
        }
        guard document.version <= currentVersion else { throw LoadError.newerVersion(document.version) }
        return document.migrated()
    }

    public func write(to url: URL) throws {
        try encoded().write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> ProducerDocument {
        try decoded(from: Data(contentsOf: url))
    }
}
