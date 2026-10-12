// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

final class PagerURLBuilderTests: XCTestCase {
    func testDefaultsOmitEveryParameter() {
        XCTAssertEqual(PagerURLBuilder(host: "192.168.1.5").urlString, "http://192.168.1.5:13390/pager")
    }

    func testCustomPort() {
        XCTAssertEqual(PagerURLBuilder(host: "10.0.0.2", port: 8080).urlString, "http://10.0.0.2:8080/pager")
    }

    func testRoleEncodesSpacesAndSymbols() {
        XCTAssertEqual(PagerURLBuilder(host: "h", role: "Front of House").urlString, "http://h:13390/pager?role=Front%20of%20House")
        XCTAssertEqual(PagerURLBuilder(host: "h", role: "A&B=C+D#?").urlString, "http://h:13390/pager?role=A%26B%3DC%2BD%23%3F")
    }

    func testRoleEncodesNonASCII() {
        XCTAssertEqual(PagerURLBuilder(host: "h", role: "Caf\u{E9} \u{1F3A4}").urlString, "http://h:13390/pager?role=Caf%C3%A9%20%F0%9F%8E%A4")
    }

    func testEmptyRoleIsOmitted() {
        XCTAssertEqual(PagerURLBuilder(host: "h", role: "").urlString, "http://h:13390/pager")
    }

    func testLayoutValues() {
        XCTAssertEqual(PagerURLBuilder(host: "h", layout: .landscape).urlString, "http://h:13390/pager?layout=landscape")
        XCTAssertEqual(PagerURLBuilder(host: "h", layout: .portrait).urlString, "http://h:13390/pager?layout=portrait")
        XCTAssertEqual(PagerURLBuilder(host: "h", layout: .lowerThird).urlString, "http://h:13390/pager?layout=lowerthird")
        XCTAssertEqual(PagerURLBuilder(host: "h", layout: .auto).urlString, "http://h:13390/pager")
    }

    func testCueValues() {
        XCTAssertEqual(PagerURLBuilder(host: "h", cue: .outline).urlString, "http://h:13390/pager?cue=outline")
        XCTAssertEqual(PagerURLBuilder(host: "h", cue: .full).urlString, "http://h:13390/pager?cue=full")
        XCTAssertEqual(PagerURLBuilder(host: "h", cue: .viewerChoice).urlString, "http://h:13390/pager")
    }

    func testButtonToggles() {
        XCTAssertEqual(PagerURLBuilder(host: "h", showSettings: false).urlString, "http://h:13390/pager?settings=0")
        XCTAssertEqual(PagerURLBuilder(host: "h", showMessages: false).urlString, "http://h:13390/pager?messages=0")
        XCTAssertEqual(PagerURLBuilder(host: "h", showSettings: false, showMessages: false).urlString, "http://h:13390/pager?settings=0&messages=0")
    }

    func testParameterOrderIsDeterministic() {
        let builder = PagerURLBuilder(host: "h", role: "Host", layout: .lowerThird, cue: .full, showSettings: false, showMessages: false)
        XCTAssertEqual(builder.urlString, "http://h:13390/pager?role=Host&layout=lowerthird&cue=full&settings=0&messages=0")
    }

    func testEveryCombinationParsesBack() throws {
        for layout in PagerURLBuilder.Layout.allCases {
            for cue in PagerURLBuilder.CueDisplay.allCases {
                for settings in [true, false] {
                    for messages in [true, false] {
                        for role in [nil, "Host", "Front of House"] as [String?] {
                            let builder = PagerURLBuilder(host: "h", role: role, layout: layout, cue: cue, showSettings: settings, showMessages: messages)
                            let url = try XCTUnwrap(builder.url)
                            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                            let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
                            XCTAssertEqual(dict["role"], role)
                            XCTAssertEqual(dict["layout"], layout == .auto ? nil : layout.rawValue)
                            XCTAssertEqual(dict["cue"], cue == .viewerChoice ? nil : cue.rawValue)
                            XCTAssertEqual(dict["settings"], settings ? nil : "0")
                            XCTAssertEqual(dict["messages"], messages ? nil : "0")
                        }
                    }
                }
            }
        }
    }

    func testIPv6HostIsBracketed() {
        XCTAssertEqual(PagerURLBuilder(host: "fe80::1", port: 13390).urlString, "http://[fe80::1]:13390/pager")
        XCTAssertEqual(PagerURLBuilder(host: "[::1]", port: 9).urlString, "http://[::1]:9/pager")
    }

    func testIPv6ScopeIdIsEscaped() {
        XCTAssertEqual(PagerURLBuilder(host: "fe80::1%en0").urlString, "http://[fe80::1%25en0]:13390/pager")
    }

    func testURLIsValid() {
        XCTAssertNotNil(PagerURLBuilder(host: "studio.local", role: "Pastor Jos\u{E9}").url)
    }
}
