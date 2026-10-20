// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

final class LowerThirdLayoutTests: XCTestCase {
    func testAutomaticSwitchesOnlyForVeryWideWindows() {
        XCTAssertFalse(PagerLayoutChoice.automatic.usesLowerThird(for: CGSize(width: 1024, height: 768)))
        XCTAssertFalse(PagerLayoutChoice.automatic.usesLowerThird(for: CGSize(width: 1920, height: 1080)))
        XCTAssertTrue(PagerLayoutChoice.automatic.usesLowerThird(for: CGSize(width: 1920, height: 260)))
        XCTAssertTrue(PagerLayoutChoice.automatic.usesLowerThird(for: CGSize(width: 900, height: 300)))
    }

    func testExplicitChoiceAlwaysUsesLowerThird() {
        XCTAssertTrue(PagerLayoutChoice.lowerThird.usesLowerThird(for: CGSize(width: 390, height: 844)))
    }

    func testUnknownStoredValueFallsBackToAutomatic() {
        XCTAssertEqual(PagerLayoutChoice.resolve("nonsense"), .automatic)
        XCTAssertEqual(PagerLayoutChoice.resolve("lowerThird"), .lowerThird)
        XCTAssertEqual(PagerLayoutChoice.resolve("landscape"), .landscape)
        XCTAssertEqual(PagerLayoutChoice.resolve("portrait"), .portrait)
    }

    func testSplitPagerFollowsItsOwnShape() {
        let tallPagerSide = CGSize(width: 600, height: 900)
        let widePagerSide = CGSize(width: 1200, height: 700)
        XCTAssertEqual(PagerLayoutChoice.automatic.splitPagerLayout(for: tallPagerSide), .portrait)
        XCTAssertEqual(PagerLayoutChoice.automatic.splitPagerLayout(for: widePagerSide), .landscape)
        XCTAssertEqual(PagerLayoutChoice.landscape.splitPagerLayout(for: tallPagerSide), .landscape)
        XCTAssertEqual(PagerLayoutChoice.portrait.splitPagerLayout(for: widePagerSide), .portrait)
    }

    func testExplicitLayoutsIgnoreWindowShape() {
        let tall = CGSize(width: 390, height: 844)
        let wide = CGSize(width: 1920, height: 260)
        XCTAssertEqual(PagerLayoutChoice.landscape.layout(for: tall), .landscape)
        XCTAssertEqual(PagerLayoutChoice.portrait.layout(for: wide), .portrait)
        XCTAssertEqual(PagerLayoutChoice.automatic.layout(for: tall), .portrait)
        XCTAssertEqual(PagerLayoutChoice.automatic.layout(for: CGSize(width: 1024, height: 768)), .landscape)
        XCTAssertEqual(PagerLayoutChoice.automatic.layout(for: wide), .lowerThird)
    }

    func testMetricsStayPositiveOnTinyWindows() {
        let metrics = LowerThirdMetrics(size: CGSize(width: 40, height: 20))
        XCTAssertGreaterThan(metrics.fontSize, 0)
        XCTAssertGreaterThan(metrics.contentHeight, 0)
    }
}
