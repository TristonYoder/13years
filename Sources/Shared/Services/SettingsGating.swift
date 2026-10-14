// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum SettingsGating {
    public static func isLocalControlAPIConfigurable(isRemoteSession: Bool) -> Bool {
        !isRemoteSession
    }
}
