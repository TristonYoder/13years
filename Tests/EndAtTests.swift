// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class EndAtTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: hour, minute: minute, second: second))!
    }

    private func time(_ hour: Int, _ minute: Int) -> TimeOfDay {
        TimeOfDay(hour: hour, minute: minute)!
    }

    func testParsesEndAtInput() {
        XCTAssertEqual(TimerInputParser.parseEndAt("1015", isPM: false), .endAt(time(10, 15)))
        XCTAssertEqual(TimerInputParser.parseEndAt("10:15", isPM: true), .endAt(time(22, 15)))
        XCTAssertEqual(TimerInputParser.parseEndAt("9", isPM: false), .endAt(time(9, 0)))
        XCTAssertEqual(TimerInputParser.parseEndAt("930", isPM: true), .endAt(time(21, 30)))
        XCTAssertEqual(TimerInputParser.parseEndAt("12", isPM: false), .endAt(time(0, 0)))
        XCTAssertEqual(TimerInputParser.parseEndAt("1200", isPM: true), .endAt(time(12, 0)))
        XCTAssertNil(TimerInputParser.parseEndAt("13", isPM: false))
        XCTAssertNil(TimerInputParser.parseEndAt("0", isPM: false))
        XCTAssertNil(TimerInputParser.parseEndAt("1060", isPM: false))
        XCTAssertNil(TimerInputParser.parseEndAt("12345", isPM: false))
        XCTAssertNil(TimerInputParser.parseEndAt("1h", isPM: false))
        XCTAssertNil(TimerInputParser.parseEndAt("", isPM: false))
    }

    func testMeridiemDefaultsToNearestUpcoming() {
        let morning = date(8, 0)
        XCTAssertFalse(TimerInputParser.nearestUpcomingIsPM("1015", now: morning, calendar: calendar))
        XCTAssertTrue(TimerInputParser.nearestUpcomingIsPM("3", now: morning, calendar: calendar))
        let afternoon = date(14, 0)
        XCTAssertTrue(TimerInputParser.nearestUpcomingIsPM("3", now: afternoon, calendar: calendar))
        XCTAssertFalse(TimerInputParser.nearestUpcomingIsPM("1", now: afternoon, calendar: calendar))
    }

    func testSecondsUntilFuture() {
        XCTAssertEqual(time(10, 15).secondsUntil(now: date(10, 0), calendar: calendar), 15 * 60)
        XCTAssertEqual(time(10, 15).secondsUntil(now: date(10, 14, 30), calendar: calendar), 30)
    }

    func testSecondsUntilPastUnderTwelveHours() {
        XCTAssertEqual(time(10, 0).secondsUntil(now: date(10, 5), calendar: calendar), -300)
        XCTAssertEqual(time(10, 0).secondsUntil(now: date(22, 0), calendar: calendar), -12 * 3600)
    }

    func testSecondsUntilPastOverTwelveHoursRollsToTomorrow() {
        XCTAssertEqual(time(9, 0).secondsUntil(now: date(22, 0), calendar: calendar), 11 * 3600)
        XCTAssertEqual(time(10, 0).secondsUntil(now: date(22, 1), calendar: calendar), 12 * 3600 - 60)
    }

    func testSecondsUntilMidnightEdge() {
        XCTAssertEqual(time(0, 10).secondsUntil(now: date(23, 50), calendar: calendar), 20 * 60)
        XCTAssertEqual(time(23, 50).secondsUntil(now: date(0, 10), calendar: calendar), 23 * 3600 + 40 * 60)
        XCTAssertEqual(time(0, 0).secondsUntil(now: date(0, 0), calendar: calendar), 0)
    }

    func testPreviewResolvesEndAtAndClampsAtZero() {
        XCTAssertEqual(TimeEntryPreview.resolvedSeconds(for: .endAt(time(10, 15)), base: 0, elapsed: 0, now: date(10, 0), calendar: calendar), 900)
        XCTAssertEqual(TimeEntryPreview.resolvedSeconds(for: .endAt(time(10, 0)), base: 0, elapsed: 0, now: date(10, 5), calendar: calendar), 0)
    }

    func testEndAtRoute() {
        let engine = CueEngine()
        let router = ControlAPIRouter(engine: engine)
        func post(_ json: String) -> HTTPResponse {
            router.handle(HTTPRequest(method: "POST", path: "/v1/timer/end-at", body: Data(json.utf8)))
        }
        XCTAssertEqual(post(#"{"time":"10:15"}"#).status, 409)

        engine.importFlow(title: "Sunday", items: [
            PCOTimerItem(id: "a", title: "Welcome", itemType: "Item", lengthInSeconds: 120)
        ])
        XCTAssertEqual(post(#"{"time":"25:00"}"#).status, 400)
        XCTAssertEqual(post(#"{"time":"9"}"#).status, 400)
        XCTAssertEqual(post("{}").status, 400)

        let target = Date().addingTimeInterval(30 * 60)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: target)
        let expected = TimeOfDay(hour: parts.hour!, minute: parts.minute!)!
        let response = post(#"{"time":"\#(expected.string)"}"#)
        XCTAssertEqual(response.status, 200)
        let remaining = engine.activeTimerItem?.remainingSeconds ?? 0
        XCTAssertEqual(Double(remaining), Double(expected.secondsUntil(now: Date())), accuracy: 2)
        XCTAssertTrue((28 * 60...31 * 60).contains(remaining))
    }
}
