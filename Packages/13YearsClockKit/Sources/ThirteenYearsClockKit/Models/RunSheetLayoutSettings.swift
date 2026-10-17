// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct RunSheetLayoutSettings: Codable, Equatable, Sendable {
    public var columnOrder: [String]?
    public var hiddenColumns: [String]?
    public var columnWidths: [String: Double]?
    public var nowNextPaneWidth: Double?
    public var nowNextSplit: Double?
    public var highlightedColumns: [String]?

    public static let defaultHiddenColumns = ["number", "type", "bpm", "meter", "arrangement", "description", "pco-actual"]

    public init(
        columnOrder: [String]? = nil,
        hiddenColumns: [String]? = nil,
        columnWidths: [String: Double]? = nil,
        nowNextPaneWidth: Double? = nil,
        nowNextSplit: Double? = nil,
        highlightedColumns: [String]? = nil
    ) {
        self.columnOrder = columnOrder
        self.hiddenColumns = hiddenColumns
        self.columnWidths = columnWidths
        self.nowNextPaneWidth = nowNextPaneWidth
        self.nowNextSplit = nowNextSplit
        self.highlightedColumns = highlightedColumns
    }

    public static func noteColumnId(_ category: String) -> String { "note-\(category)" }

    public var isDefault: Bool { self == RunSheetLayoutSettings() }

    public var hiddenSet: Set<String> {
        Set(hiddenColumns ?? Self.defaultHiddenColumns)
    }

    public var highlightedSet: Set<String> {
        Set(highlightedColumns ?? [])
    }

    public func orderedIds(defaultOrder: [String]) -> [String] {
        Self.normalizedOrder(columnOrder, defaultOrder: defaultOrder)
    }

    public static func normalizedOrder(_ saved: [String]?, defaultOrder: [String]) -> [String] {
        let known = Set(defaultOrder)
        var seen = Set<String>()
        var result: [String] = []
        for id in saved ?? [] where known.contains(id) && seen.insert(id).inserted {
            result.append(id)
        }
        for id in defaultOrder where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }
}
