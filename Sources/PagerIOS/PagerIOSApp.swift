// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

@main
struct PagerIOSApp: App {
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
