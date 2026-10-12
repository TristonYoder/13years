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
        XCTAssertEqual(m.timeFontSize, 0.075 * 1080, accuracy: 0.001)
        XCTAssertEqual(m.captionFontSize, 0.02 * 1080, accuracy: 0.001)
        XCTAssertEqual(m.tagFontSize, 0.035 * 1080, accuracy: 0.001)
        XCTAssertEqual(m.timeCaptionFontSize, 0.018 * 1080, accuracy: 0.001)
        XCTAssertEqual(m.nextTitleFontSize, 0.035 * 1080, accuracy: 0.001)
        XCTAssertEqual(m.frameCornerRadius, 0.04 * 1080, accuracy: 0.001)
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

    func testVerticalPositionsDependOnlyOnWindow() {
        let size = CGSize(width: 1180, height: 820)
        let m = LandscapeMetrics(size: size)
        XCTAssertEqual(m.centreY, 410)
        XCTAssertEqual(m.topRowHeight, m.badgeFontSize * 1.3, accuracy: 0.001)
        for state in [CueState.off, .standby, .go] {
            let again = LandscapeMetrics(size: size)
            XCTAssertEqual(again.topRowHeight, m.topRowHeight)
            XCTAssertEqual(again.centreY, m.centreY)
            XCTAssertLessThanOrEqual(PagerPresentationState.cueWordText(for: state).count, LandscapeMetrics.widestCueWord.count)
        }
    }

    func testTimeFontShrinksOnlyWhenNarrow() {
        let wide = LandscapeMetrics(size: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(wide.timeFontSize, 0.075 * 1080, accuracy: 0.001)
        let narrow = LandscapeMetrics(size: CGSize(width: 700, height: 600))
        XCTAssertLessThan(narrow.timeFontSize, 0.075 * 600)
        XCTAssertGreaterThan(narrow.timeFontSize, 0)
    }

    func testClockSitsAtFarLeftAndSlotFitsWidestWord() {
        let m = LandscapeMetrics(size: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(m.clockLeading, m.frameThickness + m.margin, accuracy: 0.001)
        XCTAssertEqual(m.slotWidth, m.badgeWidthEstimate, accuracy: 0.001)
        XCTAssertLessThan(m.slotWidth, 0.38 * m.size.width + 0.001)
    }

    func testFrameCornerRadiusHasFloor() {
        XCTAssertEqual(LandscapeMetrics(size: CGSize(width: 500, height: 300)).frameCornerRadius, 18)
    }

    func testCardsAreEqualWidthAndFillRow() {
        let m = LandscapeMetrics(size: CGSize(width: 1180, height: 820))
        XCTAssertEqual(2 * m.cardWidth + m.margin, m.size.width - 2 * m.clockLeading, accuracy: 0.001)
        XCTAssertEqual(m.singleCardWidth, m.size.width - 2 * m.clockLeading, accuracy: 0.001)
        XCTAssertEqual(LandscapeMetrics.cardWidth(for: 1, in: m), m.singleCardWidth)
        XCTAssertEqual(LandscapeMetrics.cardWidth(for: 2, in: m), m.cardWidth)
        XCTAssertGreaterThan(m.nextTitleFontSize, m.noteFontSize)
    }

    func testCardAndMessageCaps() {
        let m = LandscapeMetrics(size: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(m.cardMaxHeight, 0.28 * 1080, accuracy: 0.001)
        XCTAssertEqual(m.messageFontSize, 0.06 * 1080, accuracy: 0.001)
        XCTAssertEqual(m.messageMaxHeight, min(0.25 * 1080, m.bottomRowBottom - m.centreTagBottom - m.messageClearance), accuracy: 0.001)
        XCTAssertEqual(LandscapeMetrics.messageMaxLines, 3)
        XCTAssertLessThan(m.cardContentMaxHeight, m.cardMaxHeight)
        XCTAssertGreaterThan(m.messageFontSize, m.noteFontSize)
        XCTAssertGreaterThanOrEqual(m.messageMaxHeight, 3 * m.messageFontSize * 0.9)
    }

    func testMessagePanelNeverOverlapsCentreTag() {
        for size in [CGSize(width: 1024, height: 768), CGSize(width: 1920, height: 1080), CGSize(width: 1280, height: 800), CGSize(width: 1180, height: 820), CGSize(width: 1366, height: 1024)] {
            let m = LandscapeMetrics(size: size)
            XCTAssertGreaterThanOrEqual(m.messageTop, m.centreTagBottom)
            XCTAssertEqual(m.messageMaxHeight, min(0.25 * m.shorterSide, m.bottomRowBottom - m.centreTagBottom - m.messageClearance), accuracy: 0.001)
        }
    }

    func testFirstFittingIndex() {
        XCTAssertEqual(LandscapeMetrics.firstFittingIndex(heights: [300, 200, 100], maxHeight: 250), 1)
        XCTAssertEqual(LandscapeMetrics.firstFittingIndex(heights: [100, 50], maxHeight: 250), 0)
        XCTAssertEqual(LandscapeMetrics.firstFittingIndex(heights: [300, 280], maxHeight: 250), 1)
        XCTAssertEqual(LandscapeMetrics.firstFittingIndex(heights: [], maxHeight: 250), 0)
    }

    func testFitScalesDescendFromOne() {
        let scales = LandscapeMetrics.fitScales
        XCTAssertEqual(scales.first, 1)
        XCTAssertEqual(scales, scales.sorted(by: >))
        XCTAssertGreaterThan(scales.last ?? 0, 0)
    }

    func testCentreIndependentOfBottomRowContent() {
        let size = CGSize(width: 1180, height: 820)
        let a = LandscapeMetrics(size: size)
        let b = LandscapeMetrics(size: size)
        XCTAssertEqual(a.centreY, 410)
        XCTAssertEqual(a.centreY, b.centreY)
        XCTAssertEqual(a.messageMaxHeight, b.messageMaxHeight)
        XCTAssertEqual(a.cardMaxHeight, b.cardMaxHeight)
    }

    func testFooterStripIsReservedBelowBottomRow() {
        for size in [CGSize(width: 1024, height: 768), CGSize(width: 1920, height: 1080)] {
            let m = LandscapeMetrics(size: size)
            XCTAssertEqual(m.footerHeight, 0.065 * m.shorterSide, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(m.footerButtonSide, 44)
            XCTAssertEqual(m.bottomRowBottom + m.margin + m.footerHeight + m.frameThickness, size.height, accuracy: 0.001)
            XCTAssertEqual(m.centreY, size.height / 2)
        }
    }
}
