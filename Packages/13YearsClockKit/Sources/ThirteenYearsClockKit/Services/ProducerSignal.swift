// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum ProducerSignal: String, Equatable, Sendable {
    case live
    case stale
    case lost

    public static let staleAfter: TimeInterval = 5
    public static let lostAfter: TimeInterval = 20
    public static let legacyStaleAfter: TimeInterval = 8

    public init(silence: TimeInterval?, staleAfter: TimeInterval = ProducerSignal.staleAfter) {
        guard let silence else {
            self = .lost
            return
        }
        if silence >= Self.lostAfter {
            self = .lost
        } else if silence >= staleAfter {
            self = .stale
        } else {
            self = .live
        }
    }
}
