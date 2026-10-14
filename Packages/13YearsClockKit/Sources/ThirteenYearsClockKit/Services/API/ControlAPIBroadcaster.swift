// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum ControlAPIBroadcastAudience: Sendable {
    case all
    case legacy
    case v2
}

public protocol ControlAPIBroadcaster: AnyObject {
    func broadcast(_ text: String, to audience: ControlAPIBroadcastAudience)
}
