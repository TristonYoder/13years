// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

@main
struct PagerIOSApp: App {
    @StateObject private var cueEngine = CueEngine(isMasterServer: false, startsNetworking: !ScreenshotTourOptions.isActive)
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ScreenshotTour.prepareProcess()
        AppFonts.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            PagerRootView()
                .environmentObject(cueEngine)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && !ScreenshotTourOptions.isActive { cueEngine.deviceDidBecomeActive() }
                }
                .onAppear {
                    @MainActor in
                    if ScreenshotTourOptions.isActive {
                        PagerScreenshotTour.start(engine: cueEngine)
                        return
                    }
                    WatchProducerBridge.attach(to: cueEngine)
                    #if canImport(UIKit)
                    UIApplication.shared.isIdleTimerDisabled = true
                    #endif
                }
        }
    }
}
