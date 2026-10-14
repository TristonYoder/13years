// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

final class WindowClosePolicyTests: XCTestCase {
    func testRemoteSessionDisconnectsRegardlessOfLauncher() {
        XCTAssertEqual(WindowClosePolicy.decide(isRemoteActive: true, isLauncherPresented: true), .disconnectRemote)
        XCTAssertEqual(WindowClosePolicy.decide(isRemoteActive: true, isLauncherPresented: false), .disconnectRemote)
    }

    func testLauncherQuits() {
        XCTAssertEqual(WindowClosePolicy.decide(isRemoteActive: false, isLauncherPresented: true), .quitApp)
    }

    func testDocumentClosesNormally() {
        XCTAssertEqual(WindowClosePolicy.decide(isRemoteActive: false, isLauncherPresented: false), .closeNormally)
    }
}
