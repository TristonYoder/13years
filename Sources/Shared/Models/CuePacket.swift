// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct CuePacket: Codable, Sendable {
    public enum PacketType: String, Codable, Sendable {
        case cueUpdate = "CUE_UPDATE"
        case timerUpdate = "TIMER_UPDATE"
        case messageBroadcast = "MESSAGE"
        case ping = "PING"
        case pong = "PONG"
        case clearMessages = "CLEAR_MESSAGES"
    }

    public var type: PacketType
    public var timestamp: Double
    public var senderId: String
    public var roleCues: [RoleCue]?
    public var timerItem: PCOTimerItem?
    public var message: InterTeamMessage?
    public var messages: [InterTeamMessage]?

    public init(
        type: PacketType,
        senderId: String,
        roleCues: [RoleCue]? = nil,
        timerItem: PCOTimerItem? = nil,
        message: InterTeamMessage? = nil,
        messages: [InterTeamMessage]? = nil,
        timestamp: Double = Date().timeIntervalSince1970
    ) {
        self.type = type
        self.senderId = senderId
        self.roleCues = roleCues
        self.timerItem = timerItem
        self.message = message
        self.messages = messages
        self.timestamp = timestamp
    }

    public func encode() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func decode(from data: Data) -> CuePacket? {
        try? JSONDecoder().decode(CuePacket.self, from: data)
    }
}
