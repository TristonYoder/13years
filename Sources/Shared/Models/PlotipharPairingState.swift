// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum PlotipharPairingState: Equatable, Sendable {
    case idle
    case starting
    case waitingApproval(code: String, expiresAt: Date)
    case approved
    case expired
    case error(String)
}
