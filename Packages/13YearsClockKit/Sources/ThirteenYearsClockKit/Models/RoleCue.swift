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

    public var pagerItems: [RolePagerItem]?

    public var assignedNoteCategories: [String] {
        get { (pagerItems ?? []).compactMap(\.noteCategory) }
        set { pagerItems = Self.replacing(pagerItems, matching: { $0.noteCategory != nil }, with: RolePagerItem.ordered(newValue.map(RolePagerItem.note))) }
    }

    public var pagerFields: [PagerItemField]? {
        get { pagerItems.map { $0.compactMap(\.field) } }
        set {
            guard let newValue else {
                pagerItems = pagerItems.flatMap { items in
                    let kept = items.filter { $0.field == nil }
                    return kept.isEmpty ? nil : kept
                }
                return
            }
            pagerItems = Self.replacing(pagerItems, matching: { $0.field != nil }, with: PagerItemField.ordered(newValue).map(RolePagerItem.field))
        }
    }

    public var orderedPagerFields: [PagerItemField] { pagerFields ?? [] }

    static func replacing(_ items: [RolePagerItem]?, matching isSlot: (RolePagerItem) -> Bool, with replacements: [RolePagerItem]) -> [RolePagerItem]? {
        guard let items else { return replacements.isEmpty ? nil : replacements }
        var queue = replacements[...]
        var result: [RolePagerItem] = []
        for item in items {
            if isSlot(item) {
                if let next = queue.popFirst() { result.append(next) }
            } else {
                result.append(item)
            }
        }
        result.append(contentsOf: queue)
        return result
    }

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
        pagerFields: [PagerItemField]? = nil,
        pagerItems: [RolePagerItem]? = nil
    ) {
        self.id = id
        self.name = name
        self.personName = personName
        self.clockFormat = clockFormat
        self.state = state
        self.plotipharRoleId = plotipharRoleId
        self.pcoTeamPosition = pcoTeamPosition
        self.lastUpdated = lastUpdated
        self.pagerItems = pagerItems.map(RolePagerItem.ordered) ?? RolePagerItem.legacy(fields: pagerFields, notes: assignedNoteCategories)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, personName, clockFormat, state, plotipharRoleId, pcoTeamPosition, lastUpdated
        case assignedNoteCategories, pagerFields, pagerItems
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
        if let raw = try? container.decodeIfPresent([String].self, forKey: .pagerItems) {
            pagerItems = RolePagerItem.decodeTolerant(raw)
        } else {
            let notes = try container.decode([String].self, forKey: .assignedNoteCategories)
            let fields = (try? container.decodeIfPresent([String].self, forKey: .pagerFields)).map(PagerItemField.decodeTolerant)
            pagerItems = RolePagerItem.legacy(fields: fields, notes: notes)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(personName, forKey: .personName)
        try container.encodeIfPresent(clockFormat, forKey: .clockFormat)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(plotipharRoleId, forKey: .plotipharRoleId)
        try container.encodeIfPresent(pcoTeamPosition, forKey: .pcoTeamPosition)
        try container.encode(lastUpdated, forKey: .lastUpdated)
        try container.encode(assignedNoteCategories, forKey: .assignedNoteCategories)
        try container.encodeIfPresent(pagerFields?.map(\.rawValue), forKey: .pagerFields)
        try container.encodeIfPresent(pagerItems?.map(\.token), forKey: .pagerItems)
    }

    public static let defaultRoles: [RoleCue] = [
        RoleCue(id: "default", name: "Default")
    ]
}
