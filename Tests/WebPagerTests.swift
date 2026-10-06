// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

@MainActor
final class WebPagerTests: XCTestCase {
    private func get(_ path: String) -> HTTPResponse {
        let engine = CueEngine()
        let router = ControlAPIRouter(engine: engine)
        return router.handle(HTTPRequest(method: "GET", path: path))
    }

    func testPagerPathReturnsTheHTMLPage() {
        let response = get("/pager")
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.headers["content-type"], "text/html; charset=utf-8")
        XCTAssertEqual(response.headers["cache-control"], "no-store")

        let html = String(decoding: response.body, as: UTF8.self)
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("/v1/socket"), "the page has to know where the push lives")
    }

    func testTrailingSlashAndIndexServeTheSamePage() {
        XCTAssertEqual(get("/pager/").status, 200)
        XCTAssertEqual(get("/pager/index.html").status, 200)
    }

    func testRootRedirectsToThePager() {
        let response = get("/")
        XCTAssertEqual(response.status, 302)
        XCTAssertEqual(response.headers["location"], "/pager")
    }

    func testFontRouteServesABundledInterWeight() {
        let response = get("/pager/fonts/Inter-Bold.ttf")
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.headers["content-type"], "font/ttf")
        XCTAssertGreaterThan(response.body.count, 1000)
    }

    func testFontRouteRefusesAnythingNotBundledInter() {
        XCTAssertEqual(get("/pager/fonts/../../../etc/passwd").status, 404)
        XCTAssertEqual(get("/pager/fonts/SpaceGrotesk-Bold.ttf").status, 404)
        XCTAssertEqual(get("/pager/fonts/Inter-Bold.ttf.bak").status, 404)
    }

    func testPostToThePagerPathIsNotHandledHere() {
        let engine = CueEngine()
        let router = ControlAPIRouter(engine: engine)
        let response = router.handle(HTTPRequest(method: "POST", path: "/pager"))
        XCTAssertEqual(response.status, 404)
    }

    func testAPIRoutesStillAnswer() {
        XCTAssertEqual(get("/v1/health").status, 200)
        XCTAssertEqual(get("/v1/nope").status, 404)
    }
}
