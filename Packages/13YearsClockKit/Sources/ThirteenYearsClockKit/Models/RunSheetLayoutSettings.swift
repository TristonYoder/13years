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
    public var sidePaneTab: String?
    public var detailsTextScale: Double?
    public var detailsUnpinned: Bool?

    public static let detailsTabId = "details"
    public static let detailsTextScaleRange: ClosedRange<Double> = 0.8...2.0
    public static let detailsTextScaleStep = 0.1

    public var showsDetailsTab: Bool { sidePaneTab == Self.detailsTabId }
    public var followsLiveItem: Bool { detailsUnpinned != true }
    public var effectiveDetailsTextScale: Double {
        min(max(detailsTextScale ?? 1.0, Self.detailsTextScaleRange.lowerBound), Self.detailsTextScaleRange.upperBound)
    }

    public static let defaultHiddenColumns = ["number", "type", "bpm", "meter", "arrangement", "description", "pco-actual"]

    public init(
        columnOrder: [String]? = nil,
        hiddenColumns: [String]? = nil,
        columnWidths: [String: Double]? = nil,
        nowNextPaneWidth: Double? = nil,
        nowNextSplit: Double? = nil,
        highlightedColumns: [String]? = nil,
        sidePaneTab: String? = nil,
        detailsTextScale: Double? = nil,
        detailsUnpinned: Bool? = nil
    ) {
        self.columnOrder = columnOrder
        self.hiddenColumns = hiddenColumns
        self.columnWidths = columnWidths
        self.nowNextPaneWidth = nowNextPaneWidth
        self.nowNextSplit = nowNextSplit
        self.highlightedColumns = highlightedColumns
        self.sidePaneTab = sidePaneTab
        self.detailsTextScale = detailsTextScale
        self.detailsUnpinned = detailsUnpinned
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
