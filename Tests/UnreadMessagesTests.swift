// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
import Combine
@testable import ThirteenYearsClockKit

@MainActor
final class UnreadMessagesTests: XCTestCase {
    private func message(_ id: String, from role: String?, secondsAgo: TimeInterval = 1) -> InterTeamMessage {
        InterTeamMessage(id: id, sender: "Camera", senderRoleId: role, text: "Ready", timestamp: Date().addingTimeInterval(-secondsAgo))
    }

    func testCountsMessagesFromRolesUntilRead() {
        let engine = CueEngine(isMasterServer: true, startsNetworking: false)
        engine.recentMessages = []
        engine.addMessages([message("a", from: "cam"), message("b", from: "lyrics"), message("c", from: nil)])
        XCTAssertEqual(engine.unreadMessageCount, 2)

        engine.markThreadRead(roleId: "cam")
        XCTAssertEqual(engine.unreadMessageCount, 1)
        XCTAssertTrue(engine.hasUnreadMessage(forRoleId: "lyrics"))

        engine.markThreadRead(roleId: CueEngine.allMessagesThreadId)
        XCTAssertEqual(engine.unreadMessageCount, 0)
        XCTAssertFalse(engine.hasUnreadMessage(forRoleId: "lyrics"))
    }

    func testIncomingSignalSkipsOwnAndStaleMessages() {
        let engine = CueEngine(isMasterServer: true, startsNetworking: false)
        engine.recentMessages = []
        var received: [String] = []
        let subscription = engine.incomingMessages.sink { received.append($0.id) }
        engine.addMessages([
            message("fresh", from: "cam"),
            message("producer", from: nil),
            message("stale", from: "cam", secondsAgo: CueEngine.incomingMessageFreshness + 60),
        ])
        engine.addMessages([message("fresh", from: "cam")])
        XCTAssertEqual(received, ["fresh"])
        subscription.cancel()
    }
}
