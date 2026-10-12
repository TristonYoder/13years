// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

final class LandscapeMetricsTests: XCTestCase {

    func testProportionsScaleFromShorterSide() {
        let m = LandscapeMetrics(size: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(m.shorterSide, 1080)
        XCTAssertEqual(m.frameThickness, 0.022 * 1080, accuracy: 0.001)
        XCTAssertEqual(m.badgeFontSize, 0.11 * 1080, accuracy: 0.001)
        XCTAssertEqual(m.countdownFontSize, 0.32 * 1080, accuracy: 0.001)
        XCTAssertEqual(m.titleFontSize, 0.05 * 1080, accuracy: 0.001)
        XCTAssertEqual(m.timeFontSize, 0.045 * 1080, accuracy: 0.001)
        XCTAssertEqual(m.captionFontSize, 0.02 * 1080, accuracy: 0.001)
        XCTAssertEqual(m.nextCardMaxWidth, 768, accuracy: 0.001)
    }

    func testFrameThicknessHasFloor() {
        let m = LandscapeMetrics(size: CGSize(width: 500, height: 300))
        XCTAssertEqual(m.frameThickness, 14)
    }

    func testCountdownIsLargestAndBadgeBeatsEverythingElse() {
        let m = LandscapeMetrics(size: CGSize(width: 1180, height: 820))
        XCTAssertGreaterThan(m.countdownFontSize, m.badgeFontSize)
        for other in [m.titleFontSize, m.timeFontSize, m.roleFontSize, m.noteFontSize, m.captionFontSize, m.statusFontSize] {
            XCTAssertGreaterThan(m.badgeFontSize, other)
        }
    }

    func testLandscapeDetection() {
        XCTAssertTrue(LandscapeMetrics.isLandscape(CGSize(width: 800, height: 600)))
        XCTAssertFalse(LandscapeMetrics.isLandscape(CGSize(width: 600, height: 600)))
        XCTAssertFalse(LandscapeMetrics.isLandscape(CGSize(width: 400, height: 800)))
    }

    func testCueWordEmptyForOff() {
        XCTAssertEqual(PagerPresentationState.cueWordText(for: .off), "")
        XCTAssertEqual(PagerPresentationState.cueWordText(for: .go), "GO!")
        XCTAssertEqual(PagerPresentationState.cueWordText(for: .standby), "STANDBY")
    }
}
