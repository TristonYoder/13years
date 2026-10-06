// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

@main
struct ProducerIOSApp: App {
    @StateObject private var cueEngine = CueEngine(isMasterServer: true, hostsControlAPI: true)
    @StateObject private var splash = SplashCoordinator()

    init() {
        AppFonts.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ProducerRootView()
                .environmentObject(cueEngine)
                .splashScreen(isPresented: splash.isPresented)
                .task { splash.markReady() }
                .onAppear {
                    #if canImport(UIKit)
                    UIApplication.shared.isIdleTimerDisabled = true
                    #endif
                }
        }
    }
}
