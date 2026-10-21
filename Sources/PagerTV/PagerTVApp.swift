// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI
import UIKit

@main
struct PagerTVApp: App {
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
                    UIApplication.shared.isIdleTimerDisabled = phase == .active
                    if phase == .active && !ScreenshotTourOptions.isActive { cueEngine.deviceDidBecomeActive() }
                }
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                    PagerScreenshotTour.start(engine: cueEngine)
                }
        }
    }
}