// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class ItemCueTests: XCTestCase {
    private func makeEngine() -> CueEngine {
        let engine = CueEngine()
        engine.roles = [
            RoleCue(id: "host", name: "Host"),
            RoleCue(id: "band", name: "Band"),
            RoleCue(id: "lights", name: "Lighting")
        ]
        engine.importFlow(title: "Sunday", items: [
            PCOTimerItem(id: "a", title: "Welcome", itemType: "Item", lengthInSeconds: 60),
            PCOTimerItem(id: "b", title: "Song", itemType: "Item", lengthInSeconds: 240)
        ])
        engine.setItemCueRoles(id: "b", ["band", "lights"])
        return engine
    }

    private func state(_ engine: CueEngine, _ id: String) -> CueState {
        engine.roles.first { $0.id == id }?.state ?? .off
    }

    func testStandbyTagsOnlyTheItemsRoles() {
        let engine = makeEngine()
        engine.standbyItem(id: "b")
        XCTAssertEqual(state(engine, "band"), .standby)
        XCTAssertEqual(state(engine, "lights"), .standby)
        XCTAssertEqual(state(engine, "host"), .off)
        XCTAssertEqual(engine.activeTimerItem?.id, "a")
    }

    func testGoMakesItemActiveStartsClockAndCallsRoles() {
        let engine = makeEngine()
        engine.goItem(id: "b")
        XCTAssertEqual(engine.activeTimerItem?.id, "b")
        XCTAssertEqual(engine.activeTimerItem?.isRunning, true)
        XCTAssertEqual(state(engine, "band"), .go)
        XCTAssertEqual(state(engine, "lights"), .go)
        XCTAssertEqual(state(engine, "host"), .off)
    }

    func testOtherRolesAreLeftAlone() {
        let engine = makeEngine()
        engine.setCueForRole(id: "host", state: .standby)
        engine.goItem(id: "b")
        XCTAssertEqual(state(engine, "host"), .standby)
    }

    func testGoOnTheActiveItemDoesNotRestartItsClock() {
        let engine = makeEngine()
        engine.goItem(id: "b")
        engine.activeTimerItem?.elapsedSeconds = 90
        engine.goItem(id: "b")
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 90)
    }

    func testNoRolesMeansNoButtonsAndNoCalls() {
        let engine = makeEngine()
        let plain = engine.planItems[0]
        XCTAssertFalse(engine.hasCueRoles(plain))
        engine.standbyItem(id: "a")
        engine.goItem(id: "a")
        XCTAssertEqual(state(engine, "host"), .off)
    }

    func testHeadersNeverShowButtons() {
        let engine = makeEngine()
        let header = PCOTimerItem(id: "h", title: "Worship", itemType: "Header", cueRoleIds: ["band"])
        XCTAssertFalse(engine.hasCueRoles(header))
    }

    func testRemovingARolePrunesItFromItems() {
        let engine = makeEngine()
        engine.removeRole(id: "band")
        XCTAssertEqual(engine.planItems.first { $0.id == "b" }?.cueRoleIds, ["lights"])
        engine.removeRole(id: "lights")
        XCTAssertFalse(engine.hasCueRoles(engine.planItems[1]))
    }

    func testUnknownRolesAreDropped() {
        let engine = makeEngine()
        engine.setItemCueRoles(id: "a", ["host", "ghost", "host"])
        XCTAssertEqual(engine.planItems[0].cueRoleIds, ["host"])
    }

    func testCodableRoundTripKeepsRoles() throws {
        let item = PCOTimerItem(title: "x", cueRoleIds: ["a", "b"])
        let back = try JSONDecoder().decode(PCOTimerItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(back.cueRoleIds, ["a", "b"])
        let legacy = try JSONDecoder().decode(PCOTimerItem.self, from: JSONEncoder().encode(PCOTimerItem(title: "y")))
        XCTAssertEqual(legacy.cueRoleIds, [])
    }
}
