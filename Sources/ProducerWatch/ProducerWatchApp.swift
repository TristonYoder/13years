// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

@main
struct ProducerWatchApp: App {
    @StateObject private var model = WatchPagerModel()

    init() {
        AppFonts.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            WatchPagerRootView(model: model)
                .task { model.start() }
        }
    }
}