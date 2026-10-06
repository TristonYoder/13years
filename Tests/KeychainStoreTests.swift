// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

final class KeychainStoreTests: XCTestCase {
    private struct Sample: Codable, Equatable {
        let accessToken: String
        let expiresAt: Date
    }

    override func tearDown() {
        KeychainStore.setString(nil, forKey: "kc_test_string")
        KeychainStore.setCodable(Optional<Sample>.none, forKey: "kc_test_codable")
        super.tearDown()
    }

    func testStringRoundTrip() {
        KeychainStore.setString("hello-token", forKey: "kc_test_string")
        XCTAssertEqual(KeychainStore.string(forKey: "kc_test_string"), "hello-token")
    }

    func testStringOverwrite() {
        KeychainStore.setString("first", forKey: "kc_test_string")
        KeychainStore.setString("second", forKey: "kc_test_string")
        XCTAssertEqual(KeychainStore.string(forKey: "kc_test_string"), "second")
    }

    func testSettingNilDeletes() {
        KeychainStore.setString("something", forKey: "kc_test_string")
        XCTAssertNotNil(KeychainStore.string(forKey: "kc_test_string"))

        KeychainStore.setString(nil, forKey: "kc_test_string")
        XCTAssertNil(KeychainStore.string(forKey: "kc_test_string"))
    }

    func testSettingEmptyStringDeletes() {
        KeychainStore.setString("something", forKey: "kc_test_string")
        KeychainStore.setString("", forKey: "kc_test_string")
        XCTAssertNil(KeychainStore.string(forKey: "kc_test_string"))
    }

    func testCodableRoundTrip() {
        let sample = Sample(accessToken: "abc123", expiresAt: Date(timeIntervalSince1970: 1_700_000_000))
        KeychainStore.setCodable(sample, forKey: "kc_test_codable")
        XCTAssertEqual(KeychainStore.codable(Sample.self, forKey: "kc_test_codable"), sample)
    }

    func testMissingKeyReturnsNil() {
        XCTAssertNil(KeychainStore.string(forKey: "kc_test_key_that_was_never_set"))
        XCTAssertNil(KeychainStore.codable(Sample.self, forKey: "kc_test_key_that_was_never_set"))
    }
}
