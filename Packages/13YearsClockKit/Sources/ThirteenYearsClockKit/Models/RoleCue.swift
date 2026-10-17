// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct RoleCue: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var personName: String?
    public var clockFormat: ClockFormat?
    public var state: CueState
    public var plotipharRoleId: String?
    public var pcoTeamPosition: String?
    public var lastUpdated: Date

    public var assignedNoteCategories: [String]
    public var pagerFields: [PagerItemField]?

    public init(
        id: String = UUID().uuidString,
        name: String,
        personName: String? = nil,
        clockFormat: ClockFormat? = nil,
        state: CueState = .off,
        plotipharRoleId: String? = nil,
        pcoTeamPosition: String? = nil,
        lastUpdated: Date = Date(),
        assignedNoteCategories: [String] = [],
        pagerFields: [PagerItemField]? = nil
    ) {
        self.id = id
        self.name = name
        self.personName = personName
        self.clockFormat = clockFormat
        self.state = state
        self.plotipharRoleId = plotipharRoleId
        self.pcoTeamPosition = pcoTeamPosition
        self.lastUpdated = lastUpdated
        self.assignedNoteCategories = assignedNoteCategories
        self.pagerFields = pagerFields
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, personName, clockFormat, state, plotipharRoleId, pcoTeamPosition, lastUpdated
        case assignedNoteCategories, pagerFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        personName = try container.decodeIfPresent(String.self, forKey: .personName)
        clockFormat = try? container.decodeIfPresent(ClockFormat.self, forKey: .clockFormat)
        state = try container.decode(CueState.self, forKey: .state)
        plotipharRoleId = try container.decodeIfPresent(String.self, forKey: .plotipharRoleId)
        pcoTeamPosition = try container.decodeIfPresent(String.self, forKey: .pcoTeamPosition)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        assignedNoteCategories = try container.decode([String].self, forKey: .assignedNoteCategories)
        pagerFields = (try? container.decodeIfPresent([String].self, forKey: .pagerFields)).map(PagerItemField.decodeTolerant)
    }

    public static let defaultRoles: [RoleCue] = [
        RoleCue(id: "default", name: "Default")
    ]
}
