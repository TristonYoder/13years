// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum PCOServicePosition: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case pre
    case during
    case post

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PCOServicePosition(rawValue: raw) ?? .during
    }
}

public struct PCOSongInfo: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var title: String?
    public var author: String?
    public var copyright: String?
    public var ccliNumber: Int?
    public var themes: [String]

    public init(id: String, title: String? = nil, author: String? = nil, copyright: String? = nil, ccliNumber: Int? = nil, themes: [String] = []) {
        self.id = id
        self.title = title
        self.author = author
        self.copyright = copyright
        self.ccliNumber = ccliNumber
        self.themes = themes
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, author, copyright, ccliNumber, themes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        copyright = try container.decodeIfPresent(String.self, forKey: .copyright)
        ccliNumber = try container.decodeIfPresent(Int.self, forKey: .ccliNumber)
        themes = try container.decodeIfPresent([String].self, forKey: .themes) ?? []
    }
}

public struct PCOArrangementInfo: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String?
    public var bpm: Double?
    public var meter: String?
    public var length: Int?
    public var sequence: [String]
    public var sequenceShort: [String]
    public var hasChordChart: Bool
    public var hasChords: Bool
    public var notes: String?

    public init(
        id: String,
        name: String? = nil,
        bpm: Double? = nil,
        meter: String? = nil,
        length: Int? = nil,
        sequence: [String] = [],
        sequenceShort: [String] = [],
        hasChordChart: Bool = false,
        hasChords: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.bpm = bpm
        self.meter = meter
        self.length = length
        self.sequence = sequence
        self.sequenceShort = sequenceShort
        self.hasChordChart = hasChordChart
        self.hasChords = hasChords
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, bpm, meter, length, sequence, sequenceShort, hasChordChart, hasChords, notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        bpm = try container.decodeIfPresent(Double.self, forKey: .bpm)
        meter = try container.decodeIfPresent(String.self, forKey: .meter)
        length = try container.decodeIfPresent(Int.self, forKey: .length)
        sequence = try container.decodeIfPresent([String].self, forKey: .sequence) ?? []
        sequenceShort = try container.decodeIfPresent([String].self, forKey: .sequenceShort) ?? []
        hasChordChart = try container.decodeIfPresent(Bool.self, forKey: .hasChordChart) ?? false
        hasChords = try container.decodeIfPresent(Bool.self, forKey: .hasChords) ?? false
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

public struct PCOKeyInfo: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String?
    public var startingKey: String?
    public var endingKey: String?
    public var alternateKeys: [String]

    public init(id: String, name: String? = nil, startingKey: String? = nil, endingKey: String? = nil, alternateKeys: [String] = []) {
        self.id = id
        self.name = name
        self.startingKey = startingKey
        self.endingKey = endingKey
        self.alternateKeys = alternateKeys
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, startingKey, endingKey, alternateKeys
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        startingKey = try container.decodeIfPresent(String.self, forKey: .startingKey)
        endingKey = try container.decodeIfPresent(String.self, forKey: .endingKey)
        alternateKeys = try container.decodeIfPresent([String].self, forKey: .alternateKeys) ?? []
    }
}

public struct PCOMediaInfo: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var title: String?
    public var mediaType: String?
    public var themes: [String]
    public var length: Int?
    public var thumbnailURL: String?

    public init(id: String, title: String? = nil, mediaType: String? = nil, themes: [String] = [], length: Int? = nil, thumbnailURL: String? = nil) {
        self.id = id
        self.title = title
        self.mediaType = mediaType
        self.themes = themes
        self.length = length
        self.thumbnailURL = thumbnailURL
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, mediaType, themes, length, thumbnailURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
        themes = try container.decodeIfPresent([String].self, forKey: .themes) ?? []
        length = try container.decodeIfPresent(Int.self, forKey: .length)
        thumbnailURL = try container.decodeIfPresent(String.self, forKey: .thumbnailURL)
    }
}

public struct PCOItemTimeInfo: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var planTimeId: String?
    public var length: Int?
    public var lengthOffset: Int?
    public var exclude: Bool
    public var liveStartAt: Date?
    public var liveEndAt: Date?

    public init(
        id: String,
        planTimeId: String? = nil,
        length: Int? = nil,
        lengthOffset: Int? = nil,
        exclude: Bool = false,
        liveStartAt: Date? = nil,
        liveEndAt: Date? = nil
    ) {
        self.id = id
        self.planTimeId = planTimeId
        self.length = length
        self.lengthOffset = lengthOffset
        self.exclude = exclude
        self.liveStartAt = liveStartAt
        self.liveEndAt = liveEndAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, planTimeId, length, lengthOffset, exclude, liveStartAt, liveEndAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        planTimeId = try container.decodeIfPresent(String.self, forKey: .planTimeId)
        length = try container.decodeIfPresent(Int.self, forKey: .length)
        lengthOffset = try container.decodeIfPresent(Int.self, forKey: .lengthOffset)
        exclude = try container.decodeIfPresent(Bool.self, forKey: .exclude) ?? false
        liveStartAt = try container.decodeIfPresent(Date.self, forKey: .liveStartAt)
        liveEndAt = try container.decodeIfPresent(Date.self, forKey: .liveEndAt)
    }
}

public struct PCOItemDetails: Codable, Equatable, Hashable, Sendable {
    public static let broadcastDescriptionLimit = 140

    public var description: String?
    public var htmlDetails: String?
    public var servicePosition: PCOServicePosition
    public var keyName: String?
    public var song: PCOSongInfo?
    public var arrangement: PCOArrangementInfo?
    public var key: PCOKeyInfo?
    public var customSequence: [String]
    public var customSequenceShort: [String]
    public var media: PCOMediaInfo?
    public var itemTimes: [PCOItemTimeInfo]

    public init(
        description: String? = nil,
        htmlDetails: String? = nil,
        servicePosition: PCOServicePosition = .during,
        keyName: String? = nil,
        song: PCOSongInfo? = nil,
        arrangement: PCOArrangementInfo? = nil,
        key: PCOKeyInfo? = nil,
        customSequence: [String] = [],
        customSequenceShort: [String] = [],
        media: PCOMediaInfo? = nil,
        itemTimes: [PCOItemTimeInfo] = []
    ) {
        self.description = description
        self.htmlDetails = htmlDetails
        self.servicePosition = servicePosition
        self.keyName = keyName
        self.song = song
        self.arrangement = arrangement
        self.key = key
        self.customSequence = customSequence
        self.customSequenceShort = customSequenceShort
        self.media = media
        self.itemTimes = itemTimes
    }

    private enum CodingKeys: String, CodingKey {
        case description, htmlDetails, servicePosition, keyName, song, arrangement, key
        case customSequence, customSequenceShort, media, itemTimes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        htmlDetails = try container.decodeIfPresent(String.self, forKey: .htmlDetails)
        servicePosition = try container.decodeIfPresent(PCOServicePosition.self, forKey: .servicePosition) ?? .during
        keyName = try container.decodeIfPresent(String.self, forKey: .keyName)
        song = try container.decodeIfPresent(PCOSongInfo.self, forKey: .song)
        arrangement = try container.decodeIfPresent(PCOArrangementInfo.self, forKey: .arrangement)
        key = try container.decodeIfPresent(PCOKeyInfo.self, forKey: .key)
        customSequence = try container.decodeIfPresent([String].self, forKey: .customSequence) ?? []
        customSequenceShort = try container.decodeIfPresent([String].self, forKey: .customSequenceShort) ?? []
        media = try container.decodeIfPresent(PCOMediaInfo.self, forKey: .media)
        itemTimes = try container.decodeIfPresent([PCOItemTimeInfo].self, forKey: .itemTimes) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(htmlDetails, forKey: .htmlDetails)
        try container.encode(servicePosition, forKey: .servicePosition)
        try container.encodeIfPresent(keyName, forKey: .keyName)
        try container.encodeIfPresent(song, forKey: .song)
        try container.encodeIfPresent(arrangement, forKey: .arrangement)
        try container.encodeIfPresent(key, forKey: .key)
        try container.encode(customSequence, forKey: .customSequence)
        try container.encode(customSequenceShort, forKey: .customSequenceShort)
        try container.encodeIfPresent(media, forKey: .media)
        try container.encode(itemTimes, forKey: .itemTimes)
    }

    public var effectiveSequenceShort: [String] {
        customSequenceShort.isEmpty ? (arrangement?.sequenceShort ?? []) : customSequenceShort
    }

    public var displayKey: String? {
        [key?.startingKey, keyName, key?.name]
            .compactMap { $0 }
            .first { !$0.isEmpty }
    }

    public func itemTime(forPlanTimeId planTimeId: String?) -> PCOItemTimeInfo? {
        guard let planTimeId else { return nil }
        return itemTimes.first { $0.planTimeId == planTimeId }
    }

    public func isExcluded(fromPlanTimeId planTimeId: String?) -> Bool {
        itemTime(forPlanTimeId: planTimeId)?.exclude ?? false
    }

    public var broadcastTrimmed: PCOItemDetails {
        var slim = PCOItemDetails(servicePosition: servicePosition, keyName: keyName)
        if let description, !description.isEmpty {
            slim.description = String(description.prefix(Self.broadcastDescriptionLimit))
        }
        if let key {
            slim.key = PCOKeyInfo(id: key.id, name: key.name, startingKey: key.startingKey)
        }
        if let arrangement {
            slim.arrangement = PCOArrangementInfo(id: arrangement.id, name: arrangement.name, bpm: arrangement.bpm, meter: arrangement.meter, sequenceShort: arrangement.sequenceShort)
        }
        slim.customSequenceShort = customSequenceShort
        if let media {
            slim.media = PCOMediaInfo(id: media.id, mediaType: media.mediaType)
        }
        return slim
    }
}
