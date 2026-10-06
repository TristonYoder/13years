// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

final class PagerPresentationStateTests: XCTestCase {

    private func makeState(
        roles: [RoleCue],
        planItems: [PCOTimerItem] = [],
        activeItemIndex: Int = 0,
        activeItem: PCOTimerItem? = nil,
        messages: [InterTeamMessage] = [],
        selectedRoleId: String = "host"
    ) -> PagerPresentationState {
        PagerPresentationState(
            roles: roles,
            planItems: planItems,
            activeItemIndex: activeItemIndex,
            activeTimerItem: activeItem,
            recentMessages: messages,
            selectedRoleId: selectedRoleId,
            isProducerLive: true,
            isLANConnected: true,
            connectedMasterName: "Studio",
            hourFormatThreshold: .over90Minutes
        )
    }

    private func role(_ id: String = "host", state: CueState = .standby, person: String? = nil, categories: [String] = []) -> RoleCue {
        RoleCue(id: id, name: "Host", personName: person, state: state, assignedNoteCategories: categories)
    }

    private func item(_ id: String = "1", title: String = "Sermon", notes: [String: String] = [:]) -> PCOTimerItem {
        PCOTimerItem(id: id, title: title, notes: notes)
    }

    private func message(id: String, text: String, target: String? = nil, sender: String? = nil, senderName: String = "Producer") -> InterTeamMessage {
        InterTeamMessage(id: id, sender: senderName, targetRoleId: target, senderRoleId: sender, text: text)
    }

    func testActiveRolePrefersSelectedRoleId() {
        let state = makeState(roles: [role("host"), role("cg")], selectedRoleId: "cg")
        XCTAssertEqual(state.activeRole?.id, "cg")
    }

    func testActiveRoleFallsBackToFirstWhenSelectedRoleDisappears() {
        let state = makeState(roles: [role("host"), role("cg")], selectedRoleId: "cameras")
        XCTAssertEqual(state.activeRole?.id, "host")
    }

    func testActiveRoleIsNilWhenNoRolesExist() {
        let state = makeState(roles: [])
        XCTAssertNil(state.activeRole)
        XCTAssertEqual(state.currentState, .off)
    }

    func testCurrentStateMirrorsActiveRole() {
        let state = makeState(roles: [role(state: .go)])
        XCTAssertEqual(state.currentState, .go)
    }

    func testCurrentNotesIncludeOnlyNonEmptyAssignedCategories() {
        let state = makeState(
            roles: [role(categories: ["Host Notes", "Tech Notes", "Empty"])],
            activeItem: item(notes: ["Host Notes": "Welcome everyone", "Empty": ""])
        )
        XCTAssertEqual(state.currentNotes.count, 1)
        XCTAssertEqual(state.currentNotes[0].category, "Host Notes")
        XCTAssertEqual(state.currentNotes[0].text, "Welcome everyone")
    }

    func testNextNotesComeFromTheItemAfterTheActiveIndex() {
        let state = makeState(
            roles: [role(categories: ["Host Notes"])],
            planItems: [
                item("1", title: "Song", notes: ["Host Notes": "current"]),
                item("2", title: "Sermon", notes: ["Host Notes": "next"])
            ],
            activeItemIndex: 0,
            activeItem: item("1", title: "Song", notes: ["Host Notes": "current"])
        )
        XCTAssertEqual(state.nextItem?.id, "2")
        XCTAssertEqual(state.nextNotes.first?.text, "next")
    }

    func testNoNextItemAtEndOfPlan() {
        let state = makeState(
            roles: [role(categories: ["Host Notes"])],
            planItems: [item("1")],
            activeItemIndex: 0,
            activeItem: item("1")
        )
        XCTAssertNil(state.nextItem)
        XCTAssertTrue(state.nextNotes.isEmpty)
    }

    func testBroadcastMessageIsRelevantToAnyRole() {
        let state = makeState(
            roles: [role("host"), role("cg")],
            messages: [message(id: "m1", text: "Everyone stand by", target: nil)],
            selectedRoleId: "cg"
        )
        XCTAssertEqual(state.latestRelevantMessage?.id, "m1")
    }

    func testTargetedMessageIsRelevantOnlyToThatRole() {
        let messages = [
            message(id: "dm", text: "Switch cameras", target: "cg"),
            message(id: "broadcast", text: "Stand by", target: nil)
        ]
        let hostState = makeState(roles: [role("host"), role("cg")], messages: messages, selectedRoleId: "host")
        let cgState = makeState(roles: [role("host"), role("cg")], messages: messages, selectedRoleId: "cg")
        XCTAssertEqual(hostState.latestRelevantMessage?.id, "broadcast")
        XCTAssertEqual(cgState.latestRelevantMessage?.id, "dm")
    }

    func testNoRelevantMessageWhenOnlyOtherRolesAreTargeted() {
        let state = makeState(
            roles: [role("host"), role("cg")],
            messages: [message(id: "dm", text: "For you", target: "cg")],
            selectedRoleId: "host"
        )
        XCTAssertNil(state.latestRelevantMessage)
    }
}