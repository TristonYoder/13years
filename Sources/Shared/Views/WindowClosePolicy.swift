// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

enum WindowClosePolicy: Equatable {
    case disconnectRemote
    case quitApp
    case closeNormally

    static func decide(isRemoteActive: Bool, isLauncherPresented: Bool) -> WindowClosePolicy {
        if isRemoteActive { return .disconnectRemote }
        if isLauncherPresented { return .quitApp }
        return .closeNormally
    }
}
