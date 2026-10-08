// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

final class UpdateCheckerTests: XCTestCase {
    func testNewerVersions() {
        XCTAssertTrue(AppVersion.isNewer("1.2.0", than: "1.1.1"))
        XCTAssertTrue(AppVersion.isNewer("v1.1.2", than: "1.1.1"))
        XCTAssertTrue(AppVersion.isNewer("2", than: "1.9.9"))
        XCTAssertTrue(AppVersion.isNewer("1.10", than: "1.9"))
    }

    func testNotNewer() {
        XCTAssertFalse(AppVersion.isNewer("1.1.1", than: "1.1.1"))
        XCTAssertFalse(AppVersion.isNewer("v1.1.1", than: "1.1.1.0"))
        XCTAssertFalse(AppVersion.isNewer("1.0.9", than: "1.1.0"))
    }

    func testSuffixIgnored() {
        XCTAssertFalse(AppVersion.isNewer("1.1.1-beta", than: "1.1.1"))
    }
}
