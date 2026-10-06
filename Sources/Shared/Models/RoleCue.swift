// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct RoleCue: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var personName: String?
    public var state: CueState
    public var plotipharRoleId: String?
    public var lastUpdated: Date

    public var assignedNoteCategories: [String]

    public init(
        id: String = UUID().uuidString,
        name: String,
        personName: String? = nil,
        state: CueState = .off,
        plotipharRoleId: String? = nil,
        lastUpdated: Date = Date(),
        assignedNoteCategories: [String] = []
    ) {
        self.id = id
        self.name = name
        self.personName = personName
        self.state = state
        self.plotipharRoleId = plotipharRoleId
        self.lastUpdated = lastUpdated
        self.assignedNoteCategories = assignedNoteCategories
    }

    public static let defaultRoles: [RoleCue] = [
        RoleCue(id: "default", name: "Default")
    ]
}
