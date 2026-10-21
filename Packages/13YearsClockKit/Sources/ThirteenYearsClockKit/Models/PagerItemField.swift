// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum PagerItemField: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case key
    case bpm
    case meter
    case arrangement
    case sequence
    case description
    case mediaType
    case servicePosition
    case startTime
    case leader
    case type
    case length
    case itemDetails

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .key: return "Key"
        case .bpm: return "BPM"
        case .meter: return "Meter"
        case .arrangement: return "Arrangement"
        case .sequence: return "Sequence"
        case .description: return "Description"
        case .mediaType: return "Media type"
        case .servicePosition: return "Pre/post-service"
        case .startTime: return "Start time"
        case .leader: return "Leader"
        case .type: return "Type"
        case .length: return "Length"
        case .itemDetails: return "Item details"
        }
    }

    public var isLineSegment: Bool { self != .itemDetails }

    public static func ordered(_ fields: [PagerItemField]) -> [PagerItemField] {
        var seen = Set<PagerItemField>()
        return fields.filter { seen.insert($0).inserted }
    }

    public static func normalized(_ fields: [PagerItemField]) -> [PagerItemField] {
        let wanted = Set(fields)
        return allCases.filter { wanted.contains($0) }
    }

    public static func decodeTolerant(_ raw: [String]) -> [PagerItemField] {
        ordered(raw.compactMap(PagerItemField.init(rawValue:)))
    }
}

public enum RolePagerItem: Hashable, Identifiable, Sendable, Codable {
    case field(PagerItemField)
    case note(String)

    public static let fieldPrefix = "field:"
    public static let notePrefix = "note:"

    public var id: String { token }

    public var token: String {
        switch self {
        case .field(let field): return Self.fieldPrefix + field.rawValue
        case .note(let category): return Self.notePrefix + category
        }
    }

    public init?(token: String) {
        if token.hasPrefix(Self.fieldPrefix) {
            guard let field = PagerItemField(rawValue: String(token.dropFirst(Self.fieldPrefix.count))) else { return nil }
            self = .field(field)
        } else if token.hasPrefix(Self.notePrefix) {
            let category = String(token.dropFirst(Self.notePrefix.count))
            guard !category.isEmpty else { return nil }
            self = .note(category)
        } else {
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let item = RolePagerItem(token: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown pager item \(raw)"))
        }
        self = item
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(token)
    }

    public var label: String {
        switch self {
        case .field(let field): return field.label
        case .note(let category): return category
        }
    }

    public var field: PagerItemField? {
        if case .field(let field) = self { return field }
        return nil
    }

    public var noteCategory: String? {
        if case .note(let category) = self { return category }
        return nil
    }

    public static func decodeTolerant(_ raw: [String]) -> [RolePagerItem] {
        ordered(raw.compactMap(RolePagerItem.init(token:)))
    }

    public static func ordered(_ items: [RolePagerItem]) -> [RolePagerItem] {
        var seen = Set<RolePagerItem>()
        return items.filter { seen.insert($0).inserted }
    }

    public static func legacy(fields: [PagerItemField]?, notes: [String]) -> [RolePagerItem]? {
        if fields == nil && notes.isEmpty { return nil }
        let fieldItems = PagerItemField.ordered(fields ?? []).map(RolePagerItem.field)
        return ordered(fieldItems + notes.map(RolePagerItem.note))
    }

    public static func inserting(_ item: RolePagerItem, into items: [RolePagerItem], at index: Int? = nil) -> [RolePagerItem] {
        var list = items.filter { $0 != item }
        let position = min(max(index ?? list.count, 0), list.count)
        list.insert(item, at: position)
        return list
    }

    public static func moving(_ item: RolePagerItem, in items: [RolePagerItem], toIndex index: Int) -> [RolePagerItem] {
        guard items.contains(item) else { return items }
        return inserting(item, into: items, at: index)
    }

    public static func dropping(_ item: RolePagerItem, into items: [RolePagerItem], before index: Int?) -> [RolePagerItem] {
        guard let index else { return inserting(item, into: items) }
        var target = min(max(index, 0), items.count)
        if let existing = items.firstIndex(of: item), existing < target { target -= 1 }
        return inserting(item, into: items, at: target)
    }

    public static func shifting(_ item: RolePagerItem, in items: [RolePagerItem], by offset: Int) -> [RolePagerItem] {
        guard let index = items.firstIndex(of: item) else { return items }
        let target = min(max(index + offset, 0), items.count - 1)
        return inserting(item, into: items, at: target)
    }

    public static func removing(_ item: RolePagerItem, from items: [RolePagerItem]) -> [RolePagerItem] {
        items.filter { $0 != item }
    }
}
