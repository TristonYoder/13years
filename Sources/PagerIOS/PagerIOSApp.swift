// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

@main
struct PagerIOSApp: App {
    @StateObject private var cueEngine = CueEngine(isMasterServer: false)

    init() {
        AppFonts.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            PagerRootView()
                .environmentObject(cueEngine)
                .onAppear {
                    @MainActor in
                    WatchProducerBridge.attach(to: cueEngine)
                    #if canImport(UIKit)
                    UIApplication.shared.isIdleTimerDisabled = true
                    #endif
                }
        }
    }
}
