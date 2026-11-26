// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

final class ItemCommandParserTests: XCTestCase {
    private func parse(_ text: String) -> ItemCommandParser.Result { ItemCommandParser.parse(text) }

    func testQuotedLabelTimeTypeAndTrigger() {
        let result = parse(#"Store "Amazing Grace" Time 4:30 Type Song Trigger Follow"#)
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.command.title, "Amazing Grace")
        XCTAssertEqual(result.command.length, .setAbsolute(seconds: 270))
        XCTAssertEqual(result.command.type, "Song")
        XCTAssertEqual(result.command.trigger, .follow)
    }

    func testTimeUsesTheTimerParserExactly() {
        for token in ["4:30", "5m", "1h30m", "430", "5", "90s", "+30", "-1:00", "1.30"] {
            XCTAssertEqual(parse("Time \(token)").command.length, TimerInputParser.parse(token), token)
        }
        XCTAssertEqual(parse("Time + 30").command.length, TimerInputParser.parse("+30"))
        XCTAssertEqual(parse("@5m").command.length, TimerInputParser.parse("5m"))
        XCTAssertEqual(parse("At 4:30").command.length, TimerInputParser.parse("4:30"))
    }

    func testBadTimeIsReported() {
        let result = parse("Time soon")
        XCTAssertFalse(result.isValid)
        XCTAssertNil(result.command.length)
    }

    func testAbbreviationsAndCase() {
        let result = parse(#"sto lab "Offering" tim 5m typ me tri fol"#)
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.command.title, "Offering")
        XCTAssertEqual(result.command.length, .setAbsolute(seconds: 300))
        XCTAssertEqual(result.command.type, "Media")
        XCTAssertEqual(result.command.trigger, .follow)
    }

    func testUnquotedWordsBecomeTheTitleUntilAKeyword() {
        let result = parse("Amazing Grace Time 4:30")
        XCTAssertEqual(result.command.title, "Amazing Grace")
        XCTAssertEqual(parse("Welcome").command.title, "Welcome")
        XCTAssertEqual(parse("Label Opening prayer Time 2m").command.title, "Opening prayer")
    }

    func testQuotesProtectKeywordsInNames() {
        let result = parse(#""Time of prayer" Time 3m"#)
        XCTAssertEqual(result.command.title, "Time of prayer")
        XCTAssertEqual(result.command.length, .setAbsolute(seconds: 180))
    }

    func testItemPositionAndThru() {
        XCTAssertEqual(parse("Store Item 4").command.position, 4)
        let range = parse(#"Store Item 4 Thru 6 "Song" Time 5m"#).command
        XCTAssertEqual(range.position, 4)
        XCTAssertEqual(range.count, 3)
        XCTAssertFalse(parse("Item 6 Thru 4").isValid)
        XCTAssertFalse(parse("Item").isValid)
        XCTAssertFalse(parse("Item 1 Thru 999").isValid)
    }

    func testTriggerGoAndFollowShortcuts() {
        XCTAssertEqual(parse("Trigger Go").command.trigger, .go)
        XCTAssertEqual(parse("Follow").command.trigger, .follow)
        XCTAssertEqual(parse("Go").command.trigger, .go)
        XCTAssertFalse(parse("Trigger Maybe").isValid)
    }

    func testOptions() {
        let result = parse(#""Video" Time 3:10 /Actual /Pre"#)
        XCTAssertEqual(result.command.isActual, true)
        XCTAssertEqual(result.command.servicePosition, .pre)
        XCTAssertEqual(parse("/post").command.servicePosition, .post)
        XCTAssertFalse(parse("/bogus").isValid)
    }

    func testResolvedLength() {
        XCTAssertEqual(parse("Time 4:30").command.resolvedLength(base: 300), 270)
        XCTAssertEqual(parse("Time +30").command.resolvedLength(base: 300), 330)
        XCTAssertEqual(parse("Time -9:00").command.resolvedLength(base: 300), 0)
        XCTAssertEqual(parse("Welcome").command.resolvedLength(base: 300), 300)
    }

    func testEmptyInput() {
        let result = parse("   ")
        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.command.title)
    }
}
