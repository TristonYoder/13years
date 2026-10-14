// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

final class RecentItemsTests: XCTestCase {
    private func file(_ name: String, kind: RecentKind = .document, at seconds: TimeInterval) -> RecentItem {
        RecentItem.file(URL(fileURLWithPath: "/tmp/\(name)"), bookmark: Data([1]), kind: kind, lastUsed: Date(timeIntervalSince1970: seconds))
    }

    func testOldEntriesWithoutKindDecodeAsDocuments() throws {
        let json = #"[{"bookmark":"AQID","lastUsed":100}]"#.data(using: .utf8)!
        let decoder = JSONDecoder()
        let items = try decoder.decode([RecentItem].self, from: json)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].kind, .document)
        XCTAssertEqual(items[0].bookmark, Data([1, 2, 3]))
        let bare = try decoder.decode(RecentItem.self, from: "{}".data(using: .utf8)!)
        XCTAssertEqual(bare.kind, .document)
    }

    func testRoundTripKeepsKindAndRemoteFields() throws {
        let remote = RecentItem.remote(RemoteEndpoint(host: "10.0.0.5", port: 14000), name: "Main Stage", lastUsed: Date(timeIntervalSince1970: 5))
        let template = file("a.13years-template", kind: .template, at: 3)
        let decoded = try JSONDecoder().decode([RecentItem].self, from: JSONEncoder().encode([remote, template]))
        XCTAssertEqual(decoded[0].kind, .remoteHost)
        XCTAssertEqual(decoded[0].host, "10.0.0.5")
        XCTAssertEqual(decoded[0].port, 14000)
        XCTAssertEqual(decoded[0].name, "Main Stage")
        XCTAssertEqual(decoded[1].kind, .template)
        XCTAssertEqual(decoded[1].bookmark, Data([1]))
    }

    func testLegacyBookmarkArrayMigratesInOrder() {
        let defaults = UserDefaults(suiteName: "RecentItemsTests-\(UUID().uuidString)")!
        defaults.set([Data([9]), Data([8])], forKey: RecentDocuments.defaultsKey)
        let loaded = RecentItems.load(defaults: defaults)
        XCTAssertTrue(loaded.items.allSatisfy { $0.kind == .document })
        XCTAssertTrue(loaded.changed)
    }

    func testPersistWritesLegacyDocumentBookmarksAndNewItems() {
        let defaults = UserDefaults(suiteName: "RecentItemsTests-\(UUID().uuidString)")!
        let remote = RecentItem.remote(RemoteEndpoint(host: "h"))
        RecentItems.persist([file("a.13years", at: 1), file("t.13years-template", kind: .template, at: 2), remote], defaults: defaults)
        XCTAssertEqual((defaults.array(forKey: RecentDocuments.defaultsKey) as? [Data])?.count, 1)
        let stored = try? JSONDecoder().decode([RecentItem].self, from: defaults.data(forKey: RecentItems.defaultsKey) ?? Data())
        XCTAssertEqual(stored?.count, 3)
        let reloaded = RecentItems.load(defaults: defaults).items
        XCTAssertEqual(reloaded.filter { $0.kind == .remoteHost }.count, 1)
    }

    func testDeduplicatesPerKindAndOrdersByLastUsed() {
        var list: [RecentItem] = []
        list = RecentItems.updated(list, adding: file("a", at: 1))
        list = RecentItems.updated(list, adding: file("a", kind: .template, at: 2))
        list = RecentItems.updated(list, adding: .remote(RemoteEndpoint(host: "Host.local"), lastUsed: Date(timeIntervalSince1970: 3)))
        XCTAssertEqual(list.map(\.kind), [.remoteHost, .template, .document])
        list = RecentItems.updated(list, adding: file("a", at: 4))
        XCTAssertEqual(list.map(\.kind), [.document, .remoteHost, .template])
        list = RecentItems.updated(list, adding: .remote(RemoteEndpoint(host: "host.local"), name: "Renamed", lastUsed: Date(timeIntervalSince1970: 5)))
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list.first?.kind, .remoteHost)
        XCTAssertEqual(list.first?.name, "Renamed")
        list = RecentItems.updated(list, adding: .remote(RemoteEndpoint(host: "host.local", port: 14000), lastUsed: Date(timeIntervalSince1970: 6)))
        XCTAssertEqual(list.count, 4)
    }

    func testCapDropsOldest() {
        var list: [RecentItem] = []
        for index in 0..<(RecentItems.limit + 5) {
            list = RecentItems.updated(list, adding: file("f\(index)", at: TimeInterval(index)))
        }
        XCTAssertEqual(list.count, RecentItems.limit)
        XCTAssertEqual(list.first?.url?.lastPathComponent, "f\(RecentItems.limit + 4)")
        XCTAssertEqual(list.last?.url?.lastPathComponent, "f5")
        XCTAssertEqual(RecentItems.updated([file("x", at: 1), file("y", at: 2)], adding: file("z", at: 3), limit: 2).count, 2)
    }

    func testRemoteItemFromEndpoint() {
        let item = RecentItem.remote(RemoteEndpoint(host: "fe80::1", port: 14000, name: "fe80::1"), name: "  Sanctuary  ")
        XCTAssertEqual(item.kind, .remoteHost)
        XCTAssertEqual(item.title, "Sanctuary")
        XCTAssertEqual(item.subtitle, "[fe80::1]:14000")
        XCTAssertEqual(item.endpoint?.host, "fe80::1")
        XCTAssertEqual(item.endpoint?.port, 14000)
        XCTAssertEqual(item.endpoint?.name, "Sanctuary")
        XCTAssertEqual(RecentItem.remote(RemoteEndpoint(host: "box.local"), name: " ").title, "box.local")
        XCTAssertEqual(RecentItem.remote(RemoteEndpoint(host: "box.local")).subtitle, "box.local")
    }

    func testIconsAndSubtitles() {
        XCTAssertEqual(file("a.13years", at: 1).systemImage, "doc.text.fill")
        XCTAssertEqual(file("t", kind: .template, at: 1).systemImage, "doc.on.doc")
        XCTAssertEqual(file("t", kind: .template, at: 1).subtitle, "Template")
        XCTAssertEqual(RecentItem.remote(RemoteEndpoint(host: "h")).systemImage, "antenna.radiowaves.left.and.right")
    }
}
