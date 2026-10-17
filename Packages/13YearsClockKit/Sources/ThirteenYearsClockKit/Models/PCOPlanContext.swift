// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct PCOPlanNoteInfo: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var category: String?
    public var content: String

    public init(id: String, category: String? = nil, content: String) {
        self.id = id
        self.category = category
        self.content = content
    }
}

public struct PCOPlanTimeInfo: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String?
    public var timeType: String
    public var startsAt: Date?
    public var endsAt: Date?

    public init(id: String, name: String? = nil, timeType: String = "service", startsAt: Date? = nil, endsAt: Date? = nil) {
        self.id = id
        self.name = name
        self.timeType = timeType
        self.startsAt = startsAt
        self.endsAt = endsAt
    }
}

public struct PCOPlanPersonInfo: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var personId: String?
    public var name: String
    public var teamName: String?
    public var positionName: String?
    public var status: String
    public var declinedPlanTimeIds: [String]

    public init(
        id: String,
        personId: String? = nil,
        name: String,
        teamName: String? = nil,
        positionName: String? = nil,
        status: String = "U",
        declinedPlanTimeIds: [String] = []
    ) {
        self.id = id
        self.personId = personId
        self.name = name
        self.teamName = teamName
        self.positionName = positionName
        self.status = status
        self.declinedPlanTimeIds = declinedPlanTimeIds
    }

    private enum CodingKeys: String, CodingKey {
        case id, personId, name, teamName, positionName, status, declinedPlanTimeIds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        personId = try container.decodeIfPresent(String.self, forKey: .personId)
        name = try container.decode(String.self, forKey: .name)
        teamName = try container.decodeIfPresent(String.self, forKey: .teamName)
        positionName = try container.decodeIfPresent(String.self, forKey: .positionName)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "U"
        declinedPlanTimeIds = try container.decodeIfPresent([String].self, forKey: .declinedPlanTimeIds) ?? []
    }
}

public struct PCONeededPositionInfo: Codable, Equatable, Hashable, Sendable {
    public var teamName: String?
    public var positionName: String?
    public var quantity: Int
    public var planTimeIds: [String]

    public init(teamName: String? = nil, positionName: String? = nil, quantity: Int = 1, planTimeIds: [String] = []) {
        self.teamName = teamName
        self.positionName = positionName
        self.quantity = quantity
        self.planTimeIds = planTimeIds
    }

    private enum CodingKeys: String, CodingKey {
        case teamName, positionName, quantity, planTimeIds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teamName = try container.decodeIfPresent(String.self, forKey: .teamName)
        positionName = try container.decodeIfPresent(String.self, forKey: .positionName)
        quantity = try container.decodeIfPresent(Int.self, forKey: .quantity) ?? 1
        planTimeIds = try container.decodeIfPresent([String].self, forKey: .planTimeIds) ?? []
    }
}

public struct PCOPlanContext: Codable, Equatable, Sendable {
    public var planId: String
    public var serviceTypeId: String
    public var title: String?
    public var seriesTitle: String?
    public var dates: String?
    public var totalLength: Int?
    public var planningCenterURL: String?
    public var notes: [PCOPlanNoteInfo]
    public var times: [PCOPlanTimeInfo]
    public var team: [PCOPlanPersonInfo]
    public var neededPositions: [PCONeededPositionInfo]
    public var fetchedAt: Date

    public init(
        planId: String,
        serviceTypeId: String,
        title: String? = nil,
        seriesTitle: String? = nil,
        dates: String? = nil,
        totalLength: Int? = nil,
        planningCenterURL: String? = nil,
        notes: [PCOPlanNoteInfo] = [],
        times: [PCOPlanTimeInfo] = [],
        team: [PCOPlanPersonInfo] = [],
        neededPositions: [PCONeededPositionInfo] = [],
        fetchedAt: Date = Date()
    ) {
        self.planId = planId
        self.serviceTypeId = serviceTypeId
        self.title = title
        self.seriesTitle = seriesTitle
        self.dates = dates
        self.totalLength = totalLength
        self.planningCenterURL = planningCenterURL
        self.notes = notes
        self.times = times
        self.team = team
        self.neededPositions = neededPositions
        self.fetchedAt = fetchedAt
    }

    private enum CodingKeys: String, CodingKey {
        case planId, serviceTypeId, title, seriesTitle, dates, totalLength, planningCenterURL
        case notes, times, team, neededPositions, fetchedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planId = try container.decode(String.self, forKey: .planId)
        serviceTypeId = try container.decode(String.self, forKey: .serviceTypeId)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        seriesTitle = try container.decodeIfPresent(String.self, forKey: .seriesTitle)
        dates = try container.decodeIfPresent(String.self, forKey: .dates)
        totalLength = try container.decodeIfPresent(Int.self, forKey: .totalLength)
        planningCenterURL = try container.decodeIfPresent(String.self, forKey: .planningCenterURL)
        notes = try container.decodeIfPresent([PCOPlanNoteInfo].self, forKey: .notes) ?? []
        times = try container.decodeIfPresent([PCOPlanTimeInfo].self, forKey: .times) ?? []
        team = try container.decodeIfPresent([PCOPlanPersonInfo].self, forKey: .team) ?? []
        neededPositions = try container.decodeIfPresent([PCONeededPositionInfo].self, forKey: .neededPositions) ?? []
        fetchedAt = try container.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? Date()
    }
}
