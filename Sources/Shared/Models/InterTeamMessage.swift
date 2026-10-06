// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct InterTeamMessage: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var sender: String
    public var targetRoleId: String?
    public var senderRoleId: String?
    public var text: String
    public var timestamp: Date
    public var isHighPriority: Bool

    public init(
        id: String = UUID().uuidString,
        sender: String = "Producer",
        targetRoleId: String? = nil,
        senderRoleId: String? = nil,
        text: String,
        timestamp: Date = Date(),
        isHighPriority: Bool = false
    ) {
        self.id = id
        self.sender = sender
        self.targetRoleId = targetRoleId
        self.senderRoleId = senderRoleId
        self.text = text
        self.timestamp = timestamp
        self.isHighPriority = isHighPriority
    }
}
