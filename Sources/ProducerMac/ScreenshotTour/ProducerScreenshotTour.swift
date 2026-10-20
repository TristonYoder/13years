// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import AppKit

@MainActor
final class ProducerScreenshotTour: ScreenshotTourClient {
    let runner: ScreenshotTour
    let engine: CueEngine
    let documents: DocumentController
    let flashingWindow: PagerFlashingWindowController
    private var started = false

    static var current: ProducerScreenshotTour?

    init(options: ScreenshotTourOptions, engine: CueEngine, documents: DocumentController, flashingWindow: PagerFlashingWindowController) {
        self.runner = ScreenshotTour(options: options)
        self.engine = engine
        self.documents = documents
        self.flashingWindow = flashingWindow
        TourUI.auxiliaryWindowTitles = ["Flash a Pager"]
        runner.beforeCapture = { [unowned self] in
            if self.engine.pcoLastError != nil { self.engine.pcoLastError = nil }
        }
    }

    func start() {
        guard !started else { return }
        started = true
        engine.setLANServingSuspended(true)
        Task {
            await runner.run(setUp: { [unowned self] in
                if let url = runner.options.documentURL {
                    documents.open(url, in: engine)
                }
            }, steps: { [unowned self] in
                steps()
            })
        }
    }
}
