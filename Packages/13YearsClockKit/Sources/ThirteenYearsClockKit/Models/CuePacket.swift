// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct CueDelta: Codable, Equatable, Sendable {
    public var id: String
    public var state: CueState
    public var lastUpdated: Date

    public init(id: String, state: CueState, lastUpdated: Date) {
        self.id = id
        self.state = state
        self.lastUpdated = lastUpdated
    }
}

public struct CueNextItem: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var itemType: String
    public var lengthInSeconds: Int
    public var notes: [String: String]

    public init(id: String, title: String, itemType: String, lengthInSeconds: Int, notes: [String: String]) {
        self.id = id
        self.title = title
        self.itemType = itemType
        self.lengthInSeconds = lengthInSeconds
        self.notes = notes
    }

    public init(item: PCOTimerItem, noteCategories: Set<String>) {
        self.init(
            id: item.id,
            title: item.title,
            itemType: item.itemType,
            lengthInSeconds: item.lengthInSeconds,
            notes: item.notes.filter { noteCategories.contains($0.key) }
        )
    }

    public var timerItem: PCOTimerItem {
        PCOTimerItem(id: id, title: title, itemType: itemType, lengthInSeconds: lengthInSeconds, notes: notes)
    }
}

public struct CuePacket: Codable, Sendable {
    public enum PacketType: String, Codable, Sendable {
        case cueUpdate = "CUE_UPDATE"
        case timerUpdate = "TIMER_UPDATE"
        case messageBroadcast = "MESSAGE"
        case ping = "PING"
        case pong = "PONG"
        case clearMessages = "CLEAR_MESSAGES"
        case sync = "SYNC"
        case syncReply = "SYNC_REPLY"
        case timerAnchor = "TIMER_ANCHOR"
        case cueDelta = "CUE_DELTA"
        case digest = "DIGEST"
    }

    public static let protocolVersion = 2

    public var type: PacketType
    public var timestamp: Double
    public var senderId: String
    public var roleCues: [RoleCue]?
    public var timerItem: PCOTimerItem?
    public var nextItem: CueNextItem?
    public var message: InterTeamMessage?
    public var messages: [InterTeamMessage]?
    public var proto: Int?
    public var t0: Int?
    public var t1: Int?
    public var t2: Int?
    public var rev: Int?
    public var anchor: TimerAnchor?
    public var cueDeltas: [CueDelta]?
    public var digestMs: Int?
    public var hashes: SyncHash.Hashes?
    public var epoch: Int?
    public var to: String?
    public var receivedAtMs: Double?
    public var utcOffsetSeconds: Int?
    public private(set) var anchorRejected = false

    private enum CodingKeys: String, CodingKey {
        case type, timestamp, senderId, roleCues, timerItem, nextItem, message, messages
        case proto, t0, t1, t2, rev, anchor, cueDeltas, digestMs, hashes, epoch, to, utcOffsetSeconds
    }

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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(PacketType.self, forKey: .type)
        timestamp = try container.decodeIfPresent(Double.self, forKey: .timestamp) ?? Date().timeIntervalSince1970
        senderId = try container.decode(String.self, forKey: .senderId)
        roleCues = try container.decodeIfPresent([RoleCue].self, forKey: .roleCues)
        timerItem = try container.decodeIfPresent(PCOTimerItem.self, forKey: .timerItem)
        nextItem = try? container.decodeIfPresent(CueNextItem.self, forKey: .nextItem)
        message = try container.decodeIfPresent(InterTeamMessage.self, forKey: .message)
        messages = try container.decodeIfPresent([InterTeamMessage].self, forKey: .messages)
        proto = try container.decodeIfPresent(Int.self, forKey: .proto)
        t0 = try container.decodeIfPresent(Int.self, forKey: .t0)
        t1 = try container.decodeIfPresent(Int.self, forKey: .t1)
        t2 = try container.decodeIfPresent(Int.self, forKey: .t2)
        rev = try container.decodeIfPresent(Int.self, forKey: .rev)
        if container.contains(.anchor), !((try? container.decodeNil(forKey: .anchor)) ?? false) {
            if let decoded = try? container.decode(TimerAnchor.self, forKey: .anchor), decoded.isWithinBounds {
                anchor = decoded
            } else {
                anchorRejected = true
            }
        }
        cueDeltas = try container.decodeIfPresent([CueDelta].self, forKey: .cueDeltas)
        digestMs = try container.decodeIfPresent(Int.self, forKey: .digestMs)
        hashes = try container.decodeIfPresent(SyncHash.Hashes.self, forKey: .hashes)
        epoch = try container.decodeIfPresent(Int.self, forKey: .epoch)
        to = try container.decodeIfPresent(String.self, forKey: .to)
        utcOffsetSeconds = try? container.decodeIfPresent(Int.self, forKey: .utcOffsetSeconds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(senderId, forKey: .senderId)
        try container.encodeIfPresent(roleCues, forKey: .roleCues)
        try container.encodeIfPresent(timerItem, forKey: .timerItem)
        try container.encodeIfPresent(nextItem, forKey: .nextItem)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(messages, forKey: .messages)
        try container.encodeIfPresent(proto, forKey: .proto)
        try container.encodeIfPresent(t0, forKey: .t0)
        try container.encodeIfPresent(t1, forKey: .t1)
        try container.encodeIfPresent(t2, forKey: .t2)
        try container.encodeIfPresent(rev, forKey: .rev)
        if type == .timerAnchor {
            if let anchor { try container.encode(anchor, forKey: .anchor) } else { try container.encodeNil(forKey: .anchor) }
        } else {
            try container.encodeIfPresent(anchor, forKey: .anchor)
        }
        try container.encodeIfPresent(cueDeltas, forKey: .cueDeltas)
        try container.encodeIfPresent(digestMs, forKey: .digestMs)
        try container.encodeIfPresent(hashes, forKey: .hashes)
        try container.encodeIfPresent(epoch, forKey: .epoch)
        try container.encodeIfPresent(to, forKey: .to)
        try container.encodeIfPresent(utcOffsetSeconds, forKey: .utcOffsetSeconds)
    }

    public func encode() -> Data? {
        var packet = self
        if packet.type == .syncReply, packet.t2 == nil {
            packet.t2 = Int(SyncClock.nowMs().rounded())
        }
        return try? JSONEncoder().encode(packet)
    }

    public static func decode(from data: Data) -> CuePacket? {
        let receivedAt = SyncClock.nowMs()
        guard var packet = try? JSONDecoder().decode(CuePacket.self, from: data) else { return nil }
        packet.receivedAtMs = receivedAt
        return packet
    }
}

public enum SyncClock {
    public static func nowMs() -> Double {
        Date().timeIntervalSince1970 * 1000
    }
}
