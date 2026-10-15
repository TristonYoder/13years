// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class EventTimeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearPersistedState()
    }

    override func tearDown() {
        clearPersistedState()
        super.tearDown()
    }

    private func clearPersistedState() {
        for key in ["persistedFlow", "persistedRoles", "waypoints", "serviceSchedules", "recentMessages", "isPCOLiveSyncEnabled"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func engineWithTwoTimes() -> CueEngine {
        let engine = CueEngine()
        engine.importFlow(title: "Sunday", items: [
            PCOTimerItem(id: "h", title: "Pre-Service", itemType: "Header", lengthInSeconds: 0),
            PCOTimerItem(id: "a", title: "Welcome", itemType: "Item", lengthInSeconds: 120),
            PCOTimerItem(id: "b", title: "Song", itemType: "Song", lengthInSeconds: 240)
        ])
        engine.addEventTime(name: "Late", day: nil, startTime: TimeOfDay(hour: 11, minute: 0))
        engine.addEventTime(name: "Early", day: nil, startTime: TimeOfDay(hour: 9, minute: 0))
        return engine
    }

    private func call(_ engine: CueEngine, _ method: String, _ path: String, _ json: String? = nil) -> HTTPResponse {
        ControlAPIRouter(engine: engine).handle(HTTPRequest(method: method, path: path, body: json.map { Data($0.utf8) } ?? Data()))
    }

    func testTimeOfDayAndDayCodeAsReadableStrings() throws {
        let time = EventTime(id: "t", name: "Main", day: .weekday(1), startTime: TimeOfDay(hour: 9, minute: 30))
        let data = try ControlAPIJSON.encoder.encode(time)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["startTime"] as? String, "09:30")
        XCTAssertEqual(object["day"] as? String, "sunday")
        XCTAssertEqual(try ControlAPIJSON.decoder.decode(EventTime.self, from: data), time)

        XCTAssertEqual(EventDay(string: "2026-10-18"), .date(year: 2026, month: 10, day: 18))
        XCTAssertEqual(EventDay(string: "Saturday"), .weekday(7))
        XCTAssertNil(EventDay(string: "someday"))
        XCTAssertNil(TimeOfDay(string: "25:00"))
        XCTAssertNil(TimeOfDay(string: "9"))
    }

    func testSortingPutsSaturdayBeforeSundayAndUntimedLast() {
        let sorted = EventTime.sorted([
            EventTime(id: "sun11", day: .weekday(1), startTime: TimeOfDay(hour: 11, minute: 0)),
            EventTime(id: "sun9", day: .weekday(1), startTime: TimeOfDay(hour: 9, minute: 0)),
            EventTime(id: "sat", day: .weekday(7), startTime: TimeOfDay(hour: 17, minute: 0)),
            EventTime(id: "sunUntimed", name: "Overflow", day: .weekday(1))
        ])
        XCTAssertEqual(sorted.map(\.id), ["sat", "sun9", "sun11", "sunUntimed"])
    }

    func testWeekdayResolvesToTheNextMatchingDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let thursday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 14)))
        let time = EventTime(day: .weekday(1), startTime: TimeOfDay(hour: 9, minute: 0))
        let start = try XCTUnwrap(time.startDate(onOrAfter: thursday, calendar: calendar))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start),
                       DateComponents(year: 2026, month: 10, day: 18, hour: 9, minute: 0))
    }

    func testAdvancingAtTheEndGoesBackToTheTopForTheNextTime() throws {
        let engine = engineWithTwoTimes()
        XCTAssertEqual(engine.eventTimes.map(\.name), ["Early", "Late"])
        XCTAssertEqual(engine.liveEventTime?.name, "Early")

        engine.setActivePlanItem(id: "b")
        XCTAssertTrue(engine.isAtEndOfPlan)
        XCTAssertTrue(engine.canAdvanceToNextEventTime)

        engine.advanceToNextEventTime()
        XCTAssertEqual(engine.liveEventTime?.name, "Late")
        XCTAssertEqual(engine.activeTimerItem?.id, "a")
        XCTAssertEqual(engine.activeTimerItem?.isRunning, false)
        XCTAssertNil(engine.nextEventTime)
        XCTAssertFalse(engine.canAdvanceToNextEventTime)
    }

    func testRemovingTheLiveTimeFallsBackToTheFirst() throws {
        let engine = engineWithTwoTimes()
        let late = try XCTUnwrap(engine.eventTimes.last)
        engine.setLiveEventTime(id: late.id)
        engine.removeEventTime(id: late.id)
        XCTAssertNil(engine.liveEventTimeId)
        XCTAssertEqual(engine.liveEventTime?.name, "Early")
    }

    func testDocumentsKeepEventTimesAndOldDocumentsStillOpen() throws {
        let engine = engineWithTwoTimes()
        let late = try XCTUnwrap(engine.eventTimes.last)
        engine.setLiveEventTime(id: late.id)

        let decoded = try ProducerDocument.decoded(from: engine.makeDocument().encoded())
        XCTAssertEqual(decoded.eventTimes.map(\.name), ["Early", "Late"])
        XCTAssertEqual(decoded.liveEventTimeId, late.id)
        XCTAssertNil(decoded.asTemplate().liveEventTimeId)

        let reopened = CueEngine()
        reopened.apply(decoded)
        XCTAssertEqual(reopened.liveEventTime?.id, late.id)

        let legacy = Data(#"{"version":1,"planItems":[]}"#.utf8)
        XCTAssertEqual(try ProducerDocument.decoded(from: legacy).eventTimes, [])
    }

    func testEventTimesSurviveRelaunch() throws {
        let engine = engineWithTwoTimes()
        let late = try XCTUnwrap(engine.eventTimes.last)
        engine.setLiveEventTime(id: late.id)

        let relaunched = CueEngine()
        XCTAssertEqual(relaunched.eventTimes.map(\.name), ["Early", "Late"])
        XCTAssertEqual(relaunched.liveEventTime?.id, late.id)
    }

    func testControlAPICreatesEditsAndAdvancesEventTimes() throws {
        let engine = engineWithTwoTimes()

        let created = call(engine, "POST", "/v1/event-times", #"{"name":"Evening","day":"sunday","startTime":"18:00"}"#)
        XCTAssertEqual(created.status, 201)
        let entry = try ControlAPIJSON.decoder.decode(ControlAPIState.EventTimeStatus.Entry.self, from: created.body)
        XCTAssertEqual(entry.day, .weekday(1))
        XCTAssertEqual(entry.startTime, TimeOfDay(hour: 18, minute: 0))

        XCTAssertEqual(call(engine, "POST", "/v1/event-times", #"{"startTime":"6pm"}"#).status, 400)

        let patched = call(engine, "PATCH", "/v1/event-times/\(entry.id)", #"{"day":""}"#)
        XCTAssertEqual(patched.status, 200)
        XCTAssertNil(engine.eventTime(id: entry.id)?.day)
        XCTAssertEqual(engine.eventTime(id: entry.id)?.name, "Evening")

        XCTAssertEqual(call(engine, "POST", "/v1/event-times/live", #"{"id":"nope"}"#).status, 404)
        XCTAssertEqual(call(engine, "POST", "/v1/event-times/live", "{\"id\":\"\(entry.id)\"}").status, 200)
        XCTAssertEqual(call(engine, "POST", "/v1/event-times/next").status, 409)

        let early = try XCTUnwrap(engine.eventTimes.first)
        XCTAssertEqual(call(engine, "POST", "/v1/event-times/live", "{\"id\":\"\(early.id)\"}").status, 200)
        let advanced = call(engine, "POST", "/v1/event-times/next")
        XCTAssertEqual(advanced.status, 200)
        let state = try ControlAPIJSON.decoder.decode(ControlAPIState.self, from: advanced.body)
        XCTAssertEqual(state.eventTimes?.liveId, engine.eventTimes[1].id)
        XCTAssertEqual(state.eventTimes?.entries.count, 3)

        XCTAssertEqual(call(engine, "DELETE", "/v1/event-times/\(entry.id)").status, 200)
        XCTAssertEqual(engine.eventTimes.count, 2)
    }
}
