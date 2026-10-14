// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum PlotipharAssignmentSyncStatus: Equatable, Sendable {
    case notSynced
    case notPaired
    case noMatchingEvent
    case synced(eventId: String)
    case error(String)
}
