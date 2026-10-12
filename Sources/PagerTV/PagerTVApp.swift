// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

@main
struct PagerTVApp: App {
    @StateObject private var cueEngine = CueEngine(isMasterServer: false)
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppFonts.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            PagerRootView()
                .environmentObject(cueEngine)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { cueEngine.deviceDidBecomeActive() }
                }
        }
    }
}