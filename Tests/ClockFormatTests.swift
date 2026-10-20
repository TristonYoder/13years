// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class ClockFormatTests: XCTestCase {
    func testStringFormats() {
        XCTAssertEqual(ClockFormat.twentyFourHour.string(hour: 7, minute: 5), "07:05")
        XCTAssertEqual(ClockFormat.twentyFourHour.string(hour: 19, minute: 5, second: 9), "19:05:09")
        XCTAssertEqual(ClockFormat.twelveHour.string(hour: 7, minute: 5), "7:05 AM")
        XCTAssertEqual(ClockFormat.twelveHour.string(hour: 19, minute: 5, second: 9), "7:05:09 PM")
        XCTAssertEqual(ClockFormat.twelveHour.string(hour: 0, minute: 0), "12:00 AM")
        XCTAssertEqual(ClockFormat.twelveHour.string(hour: 12, minute: 0), "12:00 PM")
        XCTAssertEqual(ClockFormat.twentyFourHour.string(hour: 0, minute: 0), "00:00")
    }

    func testTimeOfDayFormatting() throws {
        let time = try XCTUnwrap(TimeOfDay(hour: 21, minute: 30))
        XCTAssertEqual(time.formatted(.twelveHour), "9:30 PM")
        XCTAssertEqual(time.formatted(.twentyFourHour), "21:30")
        XCTAssertEqual(ClockFormat.twelveHour.string(time), "9:30 PM")
    }

    func testStringFromDateUsesTimeZone() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(ClockFormat.twentyFourHour.string(from: date, timeZone: utc, includesSeconds: true), "22:13:20")
        XCTAssertEqual(ClockFormat.twelveHour.string(from: date, timeZone: utc), "10:13 PM")
        XCTAssertEqual(ClockFormat.twentyFourHour.string(from: date, timeZone: TimeZone(secondsFromGMT: -18000)!), "17:13")
    }

    func testProducerClockFormatted() {
        let local = Date(timeIntervalSince1970: 1_700_000_000)
        let info = ProducerClockInfo(offsetMs: 0, utcOffsetSeconds: 0)
        XCTAssertEqual(ProducerClock.formatted(localNow: local, info: info, format: .twelveHour), "10:13:20 PM")
        XCTAssertEqual(ProducerClock.formatted(localNow: local, info: info, format: .twentyFourHour), "22:13:20")
    }

    func testRoleCueDecodesWithoutClockFormat() throws {
        let json = #"{"id":"r","name":"Band","state":"OFF","lastUpdated":0,"assignedNoteCategories":[]}"#
        let role = try JSONDecoder().decode(RoleCue.self, from: Data(json.utf8))
        XCTAssertNil(role.clockFormat)
        var changed = role
        changed.clockFormat = .twentyFourHour
        let decoded = try JSONDecoder().decode(RoleCue.self, from: JSONEncoder().encode(changed))
        XCTAssertEqual(decoded.clockFormat, .twentyFourHour)
    }

    func testSettingsDecodeWithoutClockFormat() throws {
        let json = #"{"hourFormatThreshold":"never","plotipharRelayHost":""}"#
        let settings = try JSONDecoder().decode(ProducerDocument.Settings.self, from: Data(json.utf8))
        XCTAssertNil(settings.clockFormat)
    }

    func testCuePacketRoundTripsClockFormat() throws {
        var packet = CuePacket(type: .timerUpdate, senderId: "p")
        packet.clockFormat = "twentyFourHour"
        let decoded = try XCTUnwrap(CuePacket.decode(from: try XCTUnwrap(packet.encode())))
        XCTAssertEqual(decoded.clockFormat, "twentyFourHour")
        let bare = try XCTUnwrap(CuePacket.decode(from: Data(#"{"type":"PING","senderId":"x"}"#.utf8)))
        XCTAssertNil(bare.clockFormat)
    }

    func testProducerStampsClockFormat() {
        let engine = CueEngine(isMasterServer: true, startsNetworking: false)
        engine.clockFormat = .twentyFourHour
        var packet = CuePacket(type: .timerUpdate, senderId: "p")
        engine.stampUtcOffset(&packet)
        XCTAssertEqual(packet.clockFormat, "twentyFourHour")
    }

    func testPagerLearnsProducerClockFormat() {
        let engine = CueEngine(isMasterServer: false, startsNetworking: false)
        var packet = CuePacket(type: .timerUpdate, senderId: "p")
        packet.utcOffsetSeconds = 0
        packet.clockFormat = "twentyFourHour"
        engine.noteProducerUTCOffset(packet)
        XCTAssertEqual(engine.producerClockFormat, .twentyFourHour)
    }

    func testDisplayClockFormatResolution() {
        let producer = CueEngine(isMasterServer: true, startsNetworking: false)
        producer.clockFormat = .twelveHour
        producer.roles = [RoleCue(id: "a", name: "A"), RoleCue(id: "b", name: "B", clockFormat: .twentyFourHour), RoleCue(id: "c", name: "C", clockFormat: .twelveHour)]
        producer.selectedRoleIds = ["a"]
        XCTAssertEqual(producer.displayClockFormat, .twelveHour)
        producer.selectedRoleIds = ["a", "b"]
        XCTAssertEqual(producer.displayClockFormat, .twentyFourHour)
        producer.selectedRoleIds = ["b", "c"]
        XCTAssertEqual(producer.displayClockFormat, .twentyFourHour)
        producer.clockFormat = .twentyFourHour
        producer.selectedRoleIds = ["a", "c"]
        XCTAssertEqual(producer.displayClockFormat, .twelveHour)

        let pager = CueEngine(isMasterServer: false, startsNetworking: false)
        pager.roles = [RoleCue(id: "a", name: "A")]
        pager.selectedRoleIds = ["a"]
        pager.producerClockFormat = .twentyFourHour
        XCTAssertEqual(pager.displayClockFormat, .twentyFourHour)
        pager.roles[0].clockFormat = .twelveHour
        XCTAssertEqual(pager.displayClockFormat, .twelveHour)
    }

    func testSettingsAndRoleRoutes() throws {
        let engine = CueEngine(isMasterServer: true, startsNetworking: false)
        engine.roles = [RoleCue(id: "r1", name: "Band")]
        let router = ControlAPIRouter(engine: engine)
        func send(_ method: String, _ path: String, _ json: String) -> HTTPResponse {
            router.handle(HTTPRequest(method: method, path: path, body: Data(json.utf8)))
        }
        XCTAssertEqual(send("PUT", "/v1/settings", #"{"clockFormat":"bogus"}"#).status, 400)
        let ok = send("PUT", "/v1/settings", #"{"clockFormat":"twentyFourHour"}"#)
        XCTAssertEqual(ok.status, 200)
        XCTAssertEqual(engine.clockFormat, .twentyFourHour)
        let status = try ControlAPIJSON.decoder.decode(ControlAPIState.SettingsStatus.self, from: ok.body)
        XCTAssertEqual(status.clockFormat, "twentyFourHour")

        XCTAssertEqual(send("PATCH", "/v1/roles/r1", #"{"clockFormat":"nope"}"#).status, 400)
        XCTAssertEqual(send("PATCH", "/v1/roles/r1", #"{"clockFormat":"twelveHour"}"#).status, 200)
        XCTAssertEqual(engine.roles[0].clockFormat, .twelveHour)
        XCTAssertEqual(send("PATCH", "/v1/roles/r1", #"{"clockFormat":"default"}"#).status, 200)
        XCTAssertNil(engine.roles[0].clockFormat)
    }
}
