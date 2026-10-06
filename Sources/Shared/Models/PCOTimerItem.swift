// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct PCOTimerItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var itemType: String
    public var sequence: Int
    public var lengthInSeconds: Int
    public var elapsedSeconds: Int
    public var isRunning: Bool
    public var servicePlanTitle: String?

    public var notes: [String: String]

    public var noteIds: [String: String]

    public var pcoServiceTypeId: String?
    public var pcoPlanId: String?

    public var isDurationActual: Bool

    public var waypointIds: [String]

    public init(
        id: String = UUID().uuidString,
        title: String,
        itemType: String = "Item",
        sequence: Int = 1,
        lengthInSeconds: Int = 300,
        elapsedSeconds: Int = 0,
        isRunning: Bool = false,
        servicePlanTitle: String? = nil,
        notes: [String: String] = [:],
        noteIds: [String: String] = [:],
        pcoServiceTypeId: String? = nil,
        pcoPlanId: String? = nil,
        isDurationActual: Bool = false,
        waypointIds: [String] = []
    ) {
        self.id = id
        self.title = title
        self.itemType = itemType
        self.sequence = sequence
        self.lengthInSeconds = lengthInSeconds
        self.elapsedSeconds = elapsedSeconds
        self.isRunning = isRunning
        self.servicePlanTitle = servicePlanTitle
        self.notes = notes
        self.noteIds = noteIds
        self.pcoServiceTypeId = pcoServiceTypeId
        self.pcoPlanId = pcoPlanId
        self.isDurationActual = isDurationActual
        self.waypointIds = waypointIds
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, itemType, sequence, lengthInSeconds, elapsedSeconds, isRunning
        case servicePlanTitle, notes, noteIds, pcoServiceTypeId, pcoPlanId, isDurationActual, waypointIds
        case tagIds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        itemType = try container.decode(String.self, forKey: .itemType)
        sequence = try container.decode(Int.self, forKey: .sequence)
        lengthInSeconds = try container.decode(Int.self, forKey: .lengthInSeconds)
        elapsedSeconds = try container.decode(Int.self, forKey: .elapsedSeconds)
        isRunning = try container.decode(Bool.self, forKey: .isRunning)
        servicePlanTitle = try container.decodeIfPresent(String.self, forKey: .servicePlanTitle)
        notes = try container.decodeIfPresent([String: String].self, forKey: .notes) ?? [:]
        noteIds = try container.decodeIfPresent([String: String].self, forKey: .noteIds) ?? [:]
        pcoServiceTypeId = try container.decodeIfPresent(String.self, forKey: .pcoServiceTypeId)
        pcoPlanId = try container.decodeIfPresent(String.self, forKey: .pcoPlanId)
        isDurationActual = try container.decodeIfPresent(Bool.self, forKey: .isDurationActual) ?? false
        waypointIds = try container.decodeIfPresent([String].self, forKey: .waypointIds)
            ?? container.decodeIfPresent([String].self, forKey: .tagIds)
            ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(itemType, forKey: .itemType)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(lengthInSeconds, forKey: .lengthInSeconds)
        try container.encode(elapsedSeconds, forKey: .elapsedSeconds)
        try container.encode(isRunning, forKey: .isRunning)
        try container.encodeIfPresent(servicePlanTitle, forKey: .servicePlanTitle)
        try container.encode(notes, forKey: .notes)
        try container.encode(noteIds, forKey: .noteIds)
        try container.encodeIfPresent(pcoServiceTypeId, forKey: .pcoServiceTypeId)
        try container.encodeIfPresent(pcoPlanId, forKey: .pcoPlanId)
        try container.encode(isDurationActual, forKey: .isDurationActual)
        try container.encode(waypointIds, forKey: .waypointIds)
    }

    public var isHeader: Bool {
        itemType.caseInsensitiveCompare("header") == .orderedSame
    }

    public var remainingSeconds: Int {
        lengthInSeconds - elapsedSeconds
    }

    public var isOvertime: Bool {
        elapsedSeconds > lengthInSeconds
    }

    public var formattedRemainingTime: String {
        let absSeconds = abs(remainingSeconds)
        let mins = absSeconds / 60
        let secs = absSeconds % 60
        let timeString = String(format: "%02d:%02d", mins, secs)
        return remainingSeconds < 0 ? "+\(timeString)" : timeString
    }

    public mutating func adjustRemainingTime(bySeconds delta: Int) {
        lengthInSeconds = max(0, lengthInSeconds + delta)
    }

    public mutating func setRemainingTime(seconds: Int) {
        lengthInSeconds = elapsedSeconds + max(0, seconds)
    }
}
