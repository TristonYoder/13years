// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI
import XCTest

final class PortraitMetricsTests: XCTestCase {
    private let phone = CGSize(width: 390, height: 844)

    func testProportionsScaleFromWidth() {
        let m = PortraitMetrics(size: phone)
        XCTAssertEqual(m.frameThickness, 0.022 * 390 > 10 ? 0.022 * 390 : 10, accuracy: 0.001)
        XCTAssertEqual(m.countdownFontSize, 0.2 * 390, accuracy: 0.001)
        XCTAssertEqual(m.messageFontSize, 0.055 * 390, accuracy: 0.001)
        XCTAssertEqual(m.messageMaxHeight, 0.34 * 390, accuracy: 0.001)
        XCTAssertEqual(PortraitMetrics.messageMaxLines, 4)
    }

    func testFrameThicknessHasFloor() {
        XCTAssertEqual(PortraitMetrics(size: CGSize(width: 300, height: 600)).frameThickness, 10)
        XCTAssertEqual(PortraitMetrics(size: CGSize(width: 1000, height: 1400)).frameThickness, 22, accuracy: 0.001)
    }

    func testSlotAndRoleColumnFitOnOneRow() {
        for size in [CGSize(width: 320, height: 568), phone, CGSize(width: 820, height: 1180)] {
            let m = PortraitMetrics(size: size)
            XCTAssertLessThanOrEqual(m.slotWidth, 0.5 * size.width + 0.001)
            XCTAssertGreaterThan(m.roleColumnMaxWidth, 0)
            XCTAssertEqual(m.slotWidth + m.margin + m.roleColumnMaxWidth + 2 * m.inset, size.width, accuracy: 0.001)
            XCTAssertEqual(m.topRowHeight, m.badgeFontSize * 1.3, accuracy: 0.001)
            XCTAssertGreaterThan(m.badgeFontSize, m.titleFontSize)
        }
    }

    func testCountdownIsLargest() {
        let m = PortraitMetrics(size: phone)
        for other in [m.badgeFontSize, m.titleFontSize, m.timeFontSize, m.roleFontSize, m.noteFontSize, m.messageFontSize] {
            XCTAssertGreaterThan(m.countdownFontSize, other)
        }
    }

    func testCentringDependsOnlyOnWindowAndStackHeight() {
        let m = PortraitMetrics(size: phone)
        let a = m.currentCardCentreY(bottomStackHeight: 200)
        let b = PortraitMetrics(size: phone).currentCardCentreY(bottomStackHeight: 200)
        XCTAssertEqual(a, b)
        let top = m.topRowBottom + m.margin
        let bottom = m.bottomEdge - 200 - m.margin
        XCTAssertEqual(a, (top + bottom) / 2, accuracy: 0.001)
        XCTAssertLessThan(a, m.currentCardCentreY(bottomStackHeight: 0))
    }

    func testMessageFitsAtMostFourLinesWithinCap() {
        let m = PortraitMetrics(size: phone)
        XCTAssertGreaterThanOrEqual(m.messageMaxHeight, 4 * m.messageFontSize * 0.6)
        XCTAssertLessThan(m.messageMaxHeight, phone.height / 2)
    }

    func testPortraitDetection() {
        XCTAssertTrue(PortraitMetrics.isPortrait(CGSize(width: 400, height: 800)))
        XCTAssertTrue(PortraitMetrics.isPortrait(CGSize(width: 600, height: 600)))
        XCTAssertFalse(PortraitMetrics.isPortrait(CGSize(width: 800, height: 600)))
    }

    func testFitScalesDescendFromOne() {
        let s = PortraitMetrics.fitScales
        XCTAssertEqual(s.first, 1)
        XCTAssertEqual(s, s.sorted(by: >))
    }

    func testNoFooterReservedAndHeaderFitsIcons() {
        let m = PortraitMetrics(size: phone)
        XCTAssertEqual(m.bottomEdge, phone.height - m.inset, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(m.headerHeight, m.topRowHeight)
        XCTAssertGreaterThanOrEqual(m.headerHeight, PagerChromeSizes.iconRowHeight + m.roleFontSize)
        XCTAssertEqual(m.topRowBottom, m.inset + m.headerHeight, accuracy: 0.001)
    }
}

final class CueDisplayStyleTests: XCTestCase {
    func testDefaultsAndResolve() {
        XCTAssertEqual(CueDisplayStyle.defaultStyle, .outline)
        XCTAssertEqual(CueDisplayStyle.storageKey, "pagerCueDisplay")
        XCTAssertEqual(CueDisplayStyle.resolve("fullscreen"), .fullscreen)
        XCTAssertEqual(CueDisplayStyle.resolve("outline"), .outline)
        XCTAssertEqual(CueDisplayStyle.resolve("bogus"), .outline)
    }

    func testOutlineKeepsGroundAndFramesCue() {
        let s = CueDisplayStyle.outline
        for state in CueState.allCases {
            XCTAssertEqual(s.groundColor(for: state), CueDisplayStyle.ground)
            XCTAssertNotNil(s.frameColor(for: state))
            XCTAssertEqual(s.primaryText(for: state), .white)
        }
        XCTAssertEqual(s.frameColor(for: .go), CueState.go.color)
        XCTAssertTrue(s.showsBadgePill)
    }

    func testFullscreenFillsWithCueColourAndHasNoFrame() {
        let s = CueDisplayStyle.fullscreen
        XCTAssertEqual(s.groundColor(for: .standby), CueState.standby.color)
        XCTAssertEqual(s.groundColor(for: .go), CueState.go.color)
        XCTAssertEqual(s.groundColor(for: .off), CueDisplayStyle.ground)
        for state in CueState.allCases { XCTAssertNil(s.frameColor(for: state)) }
        XCTAssertFalse(s.showsBadgePill)
        XCTAssertEqual(s.cardFill, Color.black.opacity(0.28))
        XCTAssertEqual(s.primaryText(for: .go), CueDisplayStyle.darkText)
        XCTAssertEqual(s.primaryText(for: .off), .white)
    }
}
