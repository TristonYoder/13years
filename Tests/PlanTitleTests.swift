// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class PlanTitleTests: XCTestCase {
    func testImportStoresTitleOnceAndLeavesItemsUntitled() {
        let engine = CueEngine()
        engine.importFlow(title: "Sunday", items: [
            PCOTimerItem(id: "a", title: "Song", itemType: "Item", lengthInSeconds: 60),
            PCOTimerItem(id: "b", title: "Talk", itemType: "Item", lengthInSeconds: 300)
        ])
        XCTAssertEqual(engine.planTitle, "Sunday")
        XCTAssertTrue(engine.planItems.allSatisfy { $0.servicePlanTitle == nil })
    }

    func testImportWithoutTitleClearsPreviousTitle() {
        let engine = CueEngine()
        engine.importFlow(title: "Sunday", items: [PCOTimerItem(id: "a", title: "Song", itemType: "Item", lengthInSeconds: 60)])
        engine.importFlow(title: nil, items: [PCOTimerItem(id: "b", title: "Talk", itemType: "Item", lengthInSeconds: 60)])
        XCTAssertNil(engine.planTitle)
    }

    func testDocumentRoundTripKeepsTitle() throws {
        let engine = CueEngine()
        engine.importFlow(title: "Sunday", items: [PCOTimerItem(id: "a", title: "Song", itemType: "Item", lengthInSeconds: 60)])
        let data = try JSONEncoder().encode(engine.makeDocument())
        let decoded = try JSONDecoder().decode(ProducerDocument.self, from: data)
        XCTAssertEqual(decoded.planTitle, "Sunday")
    }

    func testOlderDocumentTitleOnItemsMigratesToPlan() throws {
        let item = PCOTimerItem(id: "a", title: "Song", itemType: "Item", lengthInSeconds: 60, servicePlanTitle: "Easter")
        var document = ProducerDocument(roles: [], waypoints: [], serviceSchedules: [], planItems: [item], activeItemIndex: 0,
                                        settings: .init(hourFormatThreshold: .never, pcoDefaultServiceTypeId: nil, plotipharRelayHost: ""))
        document.planTitle = nil
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as! [String: Any]
        json.removeValue(forKey: "planTitle")
        let decoded = try JSONDecoder().decode(ProducerDocument.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.planTitle, "Easter")
    }
}
