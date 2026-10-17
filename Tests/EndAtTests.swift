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

    func testParseClockAccepts24HourShapes() {
        XCTAssertEqual(TimerInputParser.parseClock("7")?.hour, 7)
        XCTAssertEqual(TimerInputParser.parseClock("07")?.hour, 7)
        XCTAssertEqual(TimerInputParser.parseClock("730")?.minute, 30)
        XCTAssertEqual(TimerInputParser.parseClock("0730")?.hour, 7)
        XCTAssertEqual(TimerInputParser.parseClock("19:30")?.hour, 19)
        XCTAssertEqual(TimerInputParser.parseClock("19:30")?.minute, 30)
        XCTAssertEqual(TimerInputParser.parseClock("0")?.hour, 0)
        XCTAssertEqual(TimerInputParser.parseClock("2359")?.hour, 23)
        XCTAssertNil(TimerInputParser.parseClock("24"))
        XCTAssertNil(TimerInputParser.parseClock("2400"))
        XCTAssertNil(TimerInputParser.parseClock("1960"))
        XCTAssertNil(TimerInputParser.parseClock("12345"))
        XCTAssertNil(TimerInputParser.parseClock("1h"))
        XCTAssertNil(TimerInputParser.parseClock(""))
    }

    func testParsesEndAtWithoutMeridiemAs24Hour() {
        XCTAssertEqual(TimerInputParser.parseEndAt("1015", meridiem: nil), .endAt(time(10, 15)))
        XCTAssertEqual(TimerInputParser.parseEndAt("19:30", meridiem: nil), .endAt(time(19, 30)))
        XCTAssertEqual(TimerInputParser.parseEndAt("0", meridiem: nil), .endAt(time(0, 0)))
        XCTAssertEqual(TimerInputParser.parseEndAt("07", meridiem: nil), .endAt(time(7, 0)))
        XCTAssertNil(TimerInputParser.parseEndAt("24", meridiem: nil))
        XCTAssertNil(TimerInputParser.parseEndAt("1060", meridiem: nil))
        XCTAssertNil(TimerInputParser.parseEndAt("", meridiem: nil))
    }

    func testParsesEndAtWithMeridiem() {
        XCTAssertEqual(TimerInputParser.parseEndAt("1015", meridiem: .am), .endAt(time(10, 15)))
        XCTAssertEqual(TimerInputParser.parseEndAt("10:15", meridiem: .pm), .endAt(time(22, 15)))
        XCTAssertEqual(TimerInputParser.parseEndAt("930", meridiem: .pm), .endAt(time(21, 30)))
        XCTAssertEqual(TimerInputParser.parseEndAt("12", meridiem: .am), .endAt(time(0, 0)))
        XCTAssertEqual(TimerInputParser.parseEndAt("1200", meridiem: .pm), .endAt(time(12, 0)))
        XCTAssertEqual(TimerInputParser.parseEndAt("1230", meridiem: .am), .endAt(time(0, 30)))
        XCTAssertNil(TimerInputParser.parseEndAt("13", meridiem: .am))
        XCTAssertNil(TimerInputParser.parseEndAt("0", meridiem: .pm))
        XCTAssertNil(TimerInputParser.parseEndAt("1060", meridiem: .pm))
    }

    func testSecondsUntilFuture() {
        XCTAssertEqual(time(10, 15).secondsUntil(now: date(10, 0), calendar: calendar), 15 * 60)
        XCTAssertEqual(time(10, 15).secondsUntil(now: date(10, 14, 30), calendar: calendar), 30)
    }

    func testSecondsUntilPassedTimeMeansTomorrow() {
        XCTAssertEqual(time(7, 0).secondsUntil(now: date(21, 0), calendar: calendar), 10 * 3600)
        XCTAssertEqual(time(10, 0).secondsUntil(now: date(10, 5), calendar: calendar), 24 * 3600 - 300)
        XCTAssertEqual(time(10, 0).secondsUntil(now: date(22, 0), calendar: calendar), 12 * 3600)
        XCTAssertEqual(time(9, 0).secondsUntil(now: date(22, 0), calendar: calendar), 11 * 3600)
    }

    func testSecondsUntilIsNeverNegative() {
        for hour in 0..<24 {
            for target in [time(0, 0), time(6, 30), time(12, 0), time(23, 59)] {
                XCTAssertGreaterThanOrEqual(target.secondsUntil(now: date(hour, 17), calendar: calendar), 0)
            }
        }
    }

    func testSecondsUntilMidnightEdge() {
        XCTAssertEqual(time(0, 10).secondsUntil(now: date(23, 50), calendar: calendar), 20 * 60)
        XCTAssertEqual(time(23, 50).secondsUntil(now: date(0, 10), calendar: calendar), 23 * 3600 + 40 * 60)
        XCTAssertEqual(time(0, 0).secondsUntil(now: date(0, 0), calendar: calendar), 0)
    }

    func testPreviewResolvesEndAtToNextOccurrence() {
        XCTAssertEqual(TimeEntryPreview.resolvedSeconds(for: .endAt(time(10, 15)), base: 0, elapsed: 0, now: date(10, 0), calendar: calendar), 900)
        XCTAssertEqual(TimeEntryPreview.resolvedSeconds(for: .endAt(time(10, 0)), base: 0, elapsed: 0, now: date(10, 5), calendar: calendar), 24 * 3600 - 300)
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
