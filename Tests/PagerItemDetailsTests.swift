// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

private func detailedItem(id: String = "item-1", html: String? = "<p>Walk on <b>slowly</b></p>", description: String? = nil) -> PCOTimerItem {
    PCOTimerItem(
        id: id,
        title: "Song",
        itemType: "Song",
        lengthInSeconds: 300,
        details: PCOItemDetails(description: description, htmlDetails: html)
    )
}

private func responseData(for item: PCOTimerItem) -> Data {
    (try? ControlAPIJSON.encoder.encode(item)) ?? Data()
}

final class PagerItemDetailsFetchTests: XCTestCase {
    func testURLPointsAtTheItemRouteOfTheProducerAPI() {
        let url = PagerItemDetailsFetch.url(host: "192.168.1.20", port: 13380, itemId: "abc")
        XCTAssertEqual(url?.absoluteString, "http://192.168.1.20:13380/v1/plan/items/abc")
    }

    func testURLEscapesItemIdsAndBracketsIPv6() {
        XCTAssertEqual(PagerItemDetailsFetch.url(host: "producer.local", port: 80, itemId: "a/b c?d")?.absoluteString, "http://producer.local:80/v1/plan/items/a%2Fb%20c%3Fd")
        XCTAssertEqual(PagerItemDetailsFetch.url(host: "fe80::1", port: 13380, itemId: "x")?.absoluteString, "http://[fe80::1]:13380/v1/plan/items/x")
    }

    func testURLRejectsBadInputs() {
        XCTAssertNil(PagerItemDetailsFetch.url(host: "", port: 13380, itemId: "x"))
        XCTAssertNil(PagerItemDetailsFetch.url(host: "h", port: 0, itemId: "x"))
        XCTAssertNil(PagerItemDetailsFetch.url(host: "h", port: 70000, itemId: "x"))
        XCTAssertNil(PagerItemDetailsFetch.url(host: "h", port: 1, itemId: ""))
    }

    func testResponseYieldsHTMLThenDescription() {
        let html = detailedItem()
        XCTAssertEqual(PagerItemDetailsFetch.source(fromResponse: responseData(for: html), expectedItemId: "item-1"), "<p>Walk on <b>slowly</b></p>")
        let plain = detailedItem(html: nil, description: "Walk on slowly")
        XCTAssertEqual(PagerItemDetailsFetch.source(fromResponse: responseData(for: plain), expectedItemId: "item-1"), "Walk on slowly")
        let none = detailedItem(html: nil)
        XCTAssertNil(PagerItemDetailsFetch.source(fromResponse: responseData(for: none), expectedItemId: "item-1"))
    }

    func testResponseForAnotherItemOrGarbageIsIgnored() {
        XCTAssertNil(PagerItemDetailsFetch.source(fromResponse: responseData(for: detailedItem(id: "other")), expectedItemId: "item-1"))
        XCTAssertNil(PagerItemDetailsFetch.source(fromResponse: Data("not json".utf8), expectedItemId: "item-1"))
        XCTAssertNil(PagerItemDetailsFetch.source(fromResponse: Data(), expectedItemId: "item-1"))
    }

    func testOversizedResponsesAreRejectedAndLongHTMLIsCapped() {
        let huge = Data(repeating: 0x20, count: PagerItemDetailsFetch.maxResponseBytes + 1)
        XCTAssertNil(PagerItemDetailsFetch.source(fromResponse: huge, expectedItemId: "item-1"))
        let long = detailedItem(html: String(repeating: "a", count: PCOTimerItem.maxItemDetailsCharacters + 500))
        let capped = PagerItemDetailsFetch.source(fromResponse: responseData(for: long), expectedItemId: "item-1")
        XCTAssertEqual(capped?.count, PCOTimerItem.maxItemDetailsCharacters)
    }

    func testTheAPIBoundStaysUnderTheClientCap() throws {
        let item = detailedItem(html: String(repeating: "<p>lyrics lyrics lyrics</p>", count: 1200))
        XCTAssertLessThanOrEqual(item.details?.htmlDetails?.count ?? 0, 32000 + 1000)
        XCTAssertLessThan(responseData(for: item).count, PagerItemDetailsFetch.maxResponseBytes)
    }
}

final class PagerItemDetailsPresentationTests: XCTestCase {
    private func presentation(fields: [PagerItemField]?, active: PCOTimerItem?) -> PagerPresentationState {
        PagerPresentationState(
            roles: [RoleCue(id: "band", name: "Band", pagerFields: fields)],
            planItems: [],
            activeItemIndex: 0,
            activeTimerItem: active,
            recentMessages: [],
            selectedRoleId: "band",
            isProducerLive: true,
            isLANConnected: true,
            connectedMasterName: nil,
            hourFormatThreshold: .over90Minutes,
            clockFormat: .twentyFourHour
        )
    }

    func testOnlyRolesThatChoseItemDetailsWantThem() {
        XCTAssertTrue(presentation(fields: [.key, .itemDetails], active: detailedItem()).wantsItemDetails)
        XCTAssertFalse(presentation(fields: [.key], active: detailedItem()).wantsItemDetails)
        XCTAssertFalse(presentation(fields: nil, active: detailedItem()).wantsItemDetails)
    }

    func testLocalSourceNeedsTheFieldAndTheCurrentItem() {
        let state = presentation(fields: [.itemDetails], active: detailedItem())
        XCTAssertEqual(state.localItemDetailsSource(includingDescription: false), "<p>Walk on <b>slowly</b></p>")
        XCTAssertNil(presentation(fields: [.key], active: detailedItem()).localItemDetailsSource(includingDescription: true))
        XCTAssertNil(presentation(fields: [.itemDetails], active: nil).localItemDetailsSource(includingDescription: true))
    }

    func testTrimmedDescriptionIsNotMistakenForDetails() {
        let trimmed = detailedItem(html: nil, description: "Walk on")
        let state = presentation(fields: [.itemDetails, .description], active: trimmed)
        XCTAssertNil(state.localItemDetailsSource(includingDescription: false))
        XCTAssertEqual(state.localItemDetailsSource(includingDescription: true), "Walk on")
    }
}

final class PagerDetailsSplitTests: XCTestCase {
    func testDefaultIsTwoThirdsAndClampIs40To80() {
        XCTAssertEqual(PagerDetailsSplit.defaultFraction, 2.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(PagerDetailsSplit.clamp(0.1), 0.4)
        XCTAssertEqual(PagerDetailsSplit.clamp(0.99), 0.8)
        XCTAssertEqual(PagerDetailsSplit.clamp(0.55), 0.55)
        XCTAssertEqual(PagerDetailsSplit.clamp(.nan), PagerDetailsSplit.defaultFraction)
        XCTAssertEqual(PagerDetailsSplit.clamp(.infinity), PagerDetailsSplit.defaultFraction)
    }

    func testSplitSizesAddUpAroundTheDivider() {
        let size = CGSize(width: 1822, height: 1080)
        let pager = PagerDetailsSplit.pagerSize(in: size, fraction: PagerDetailsSplit.defaultFraction)
        let details = PagerDetailsSplit.detailsSize(in: size, fraction: PagerDetailsSplit.defaultFraction)
        XCTAssertEqual(pager.width + details.width + PagerDetailsSplit.dividerWidth, size.width, accuracy: 0.001)
        XCTAssertEqual(pager.width, 1200, accuracy: 0.001)
        XCTAssertEqual(pager.height, 1080)
        XCTAssertEqual(PagerDetailsSplit.pagerSize(in: size, fraction: 0.01).width, 1800 * 0.4, accuracy: 0.001)
        XCTAssertEqual(PagerDetailsSplit.pagerSize(in: size, fraction: 5).width, 1800 * 0.8, accuracy: 0.001)
    }

    func testDragMapsBackToTheFraction() {
        let size = CGSize(width: 1922, height: 1080)
        for fraction in [0.4, 0.5, 2.0 / 3.0, 0.8] {
            let pager = PagerDetailsSplit.pagerSize(in: size, fraction: fraction)
            let center = pager.width + PagerDetailsSplit.dividerWidth / 2
            XCTAssertEqual(PagerDetailsSplit.fraction(forDividerCenterX: center, in: size), fraction, accuracy: 1e-9)
        }
        XCTAssertEqual(PagerDetailsSplit.fraction(forDividerCenterX: -50, in: size), 0.4)
        XCTAssertEqual(PagerDetailsSplit.fraction(forDividerCenterX: 9000, in: size), 0.8)
    }

    func testOnlyWideWindowsSplit() {
        XCTAssertTrue(PagerDetailsSplit.isSplitLayout(CGSize(width: 1920, height: 1080)))
        XCTAssertTrue(PagerDetailsSplit.isSplitLayout(CGSize(width: 1180, height: 820)))
        XCTAssertTrue(PagerDetailsSplit.isSplitLayout(CGSize(width: 844, height: 390)))
        XCTAssertFalse(PagerDetailsSplit.isSplitLayout(CGSize(width: 900, height: 800)))
        XCTAssertFalse(PagerDetailsSplit.isSplitLayout(CGSize(width: 600, height: 600)))
        XCTAssertFalse(PagerDetailsSplit.isSplitLayout(CGSize(width: 400, height: 0)))
    }

    func testLandscapeMetricsFollowTheNarrowerPagerSide() {
        let full = CGSize(width: 1822, height: 1080)
        let pagerSide = PagerDetailsSplit.pagerSize(in: full, fraction: PagerDetailsSplit.defaultFraction)
        let whole = LandscapeMetrics(size: full)
        let narrow = LandscapeMetrics(size: pagerSide)
        XCTAssertEqual(narrow.size.width, 1200, accuracy: 0.001)
        XCTAssertEqual(narrow.shorterSide, 1080)
        XCTAssertEqual(narrow.countdownFontSize, whole.countdownFontSize, accuracy: 0.001)
        XCTAssertLessThan(narrow.cardWidth, whole.cardWidth)
        XCTAssertEqual(narrow.cardWidth, (1200 - 2 * narrow.clockLeading - narrow.margin) / 2, accuracy: 0.001)
        XCTAssertLessThanOrEqual(narrow.slotWidth, 0.38 * 1200 + 0.001)
        XCTAssertLessThanOrEqual(narrow.timeFontSize, whole.timeFontSize)

        let squeezed = LandscapeMetrics(size: PagerDetailsSplit.pagerSize(in: full, fraction: 0.4))
        XCTAssertEqual(squeezed.size.width, 720, accuracy: 0.001)
        XCTAssertEqual(squeezed.shorterSide, 720)
        XCTAssertLessThan(squeezed.countdownFontSize, narrow.countdownFontSize)
        XCTAssertGreaterThan(squeezed.cardWidth, 0)
        XCTAssertGreaterThan(squeezed.singleCardWidth, squeezed.cardWidth)
    }

    func testDetailsMetricsScaleWithTheWholeWindow() {
        let hd = PagerDetailsMetrics(size: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(hd.bodyFontSize, 32.4, accuracy: 0.001)
        XCTAssertGreaterThan(hd.bodyFontSize, hd.captionFontSize)
        let phone = PagerDetailsMetrics(size: CGSize(width: 844, height: 390))
        XCTAssertEqual(phone.bodyFontSize, 14, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(phone.captionFontSize, 11)
    }
}

@MainActor
final class PagerItemDetailsStoreTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        func add(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
        var all: [URL] { lock.lock(); defer { lock.unlock() }; return urls }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, timeout: TimeInterval = 3) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    func testFetchesFromTheProducerAndPublishesTheHTML() async {
        let counter = Counter()
        let body = responseData(for: detailedItem())
        let store = PagerItemDetailsStore(transport: { url in counter.add(url); return (200, body) }, refreshInterval: 0.05, retryInterval: 0.05)
        let task = Task { await store.run(itemId: "item-1", host: "10.0.0.5", port: 13380) }
        let arrived = await waitUntil { store.source(for: "item-1") != nil }
        XCTAssertTrue(arrived)
        XCTAssertEqual(store.source(for: "item-1"), "<p>Walk on <b>slowly</b></p>")
        XCTAssertNil(store.source(for: "other"))
        XCTAssertEqual(counter.all.first?.absoluteString, "http://10.0.0.5:13380/v1/plan/items/item-1")
        let refreshed = await waitUntil { counter.all.count >= 2 }
        XCTAssertTrue(refreshed)
        task.cancel()
        await task.value
    }

    func testChangingItemDropsTheOldDetailsImmediately() async {
        let body = responseData(for: detailedItem())
        let store = PagerItemDetailsStore(transport: { _ in (200, body) }, refreshInterval: 0.05, retryInterval: 0.05)
        let first = Task { await store.run(itemId: "item-1", host: "h", port: 1) }
        _ = await waitUntil { store.source(for: "item-1") != nil }
        first.cancel()
        await first.value
        let second = Task { await store.run(itemId: "item-2", host: "h", port: 1) }
        _ = await waitUntil { store.itemId == "item-2" }
        XCTAssertNil(store.source(for: "item-1"))
        second.cancel()
        await second.value
    }

    func testFailuresRetryAndKeepWhatWasShown() async {
        let attempts = Counter()
        let body = responseData(for: detailedItem())
        let store = PagerItemDetailsStore(transport: { url in
            attempts.add(url)
            if attempts.all.count == 1 { throw URLError(.cannotConnectToHost) }
            if attempts.all.count == 2 { return (500, Data()) }
            return (200, body)
        }, refreshInterval: 0.05, retryInterval: 0.02)
        let task = Task { await store.run(itemId: "item-1", host: "h", port: 1) }
        let arrived = await waitUntil { store.source(for: "item-1") != nil }
        XCTAssertTrue(arrived)
        XCTAssertGreaterThanOrEqual(attempts.all.count, 3)
        task.cancel()
        await task.value
    }

    func testMissingItemClearsTheDetails() async {
        let body = responseData(for: detailedItem())
        let responses = Counter()
        let store = PagerItemDetailsStore(transport: { url in
            responses.add(url)
            return responses.all.count == 1 ? (200, body) : (404, Data())
        }, refreshInterval: 0.03, retryInterval: 0.03)
        let task = Task { await store.run(itemId: "item-1", host: "h", port: 1) }
        _ = await waitUntil { store.source(for: "item-1") != nil }
        let cleared = await waitUntil { store.source(for: "item-1") == nil }
        XCTAssertTrue(cleared)
        task.cancel()
        await task.value
    }

    func testResetForgetsEverything() async {
        let body = responseData(for: detailedItem())
        let store = PagerItemDetailsStore(transport: { _ in (200, body) }, refreshInterval: 0.05, retryInterval: 0.05)
        let task = Task { await store.run(itemId: "item-1", host: "h", port: 1) }
        _ = await waitUntil { store.source(for: "item-1") != nil }
        task.cancel()
        await task.value
        store.reset()
        XCTAssertNil(store.itemId)
        XCTAssertNil(store.html)
    }
}

final class HTMLRichTextColorTests: XCTestCase {
    func testHTMLColorFromPaletteTokenMatchesThePanelHex() throws {
        let color = try XCTUnwrap(HTMLColor(AppPalette.pagerPanel))
        XCTAssertEqual(color.red, 0x1B / 255.0, accuracy: 0.01)
        XCTAssertEqual(color.green, 0x1B / 255.0, accuracy: 0.01)
        XCTAssertEqual(color.blue, 0x20 / 255.0, accuracy: 0.01)
    }

    func testStyledDropsLowContrastColorsOnTheDarkPanel() throws {
        let ground = try XCTUnwrap(HTMLColor(AppPalette.pagerPanel))
        let source = HTMLAttributedConverter.attributedString(fromHTML: "<span style=\"color:#101010\">dark</span> <span style=\"color:#ff8800\">orange</span>")
        let styled = HTMLRichText.styled(source, baseSize: 20, ground: ground)
        var colored: [String: Bool] = [:]
        for run in styled.runs {
            colored[String(styled[run.range].characters)] = run.foregroundColor != nil
        }
        XCTAssertEqual(colored["dark"], false)
        XCTAssertEqual(colored["orange"], true)
    }
}
