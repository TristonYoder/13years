// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum ItemTrigger: String, Codable, Equatable, Sendable, CaseIterable {
    case follow
    case go
}
