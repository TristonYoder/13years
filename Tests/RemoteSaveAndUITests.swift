// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
import SwiftUI
import AppKit
@testable import ThirteenYearsClockKit

@MainActor
final class RemoteSaveAndUITests: XCTestCase {
    func testMirrorDocumentCarriesRemoteState() throws {
        let engine = CueEngine(mirroring: nil)
        var state = RemoteFixtures.state(rev: 3, roleName: "Lead")
        state.plan.items[0].notes = ["Lights": "Dim on cue"]
        engine.apply(remoteState: state)

        let document = engine.makeDocument()
        XCTAssertEqual(document.roles.map(\.name), ["Lead", "Band"])
        XCTAssertEqual(document.selectedRoleIds, ["host"])
        XCTAssertEqual(document.planItems.map(\.id), ["a", "b"])
        XCTAssertEqual(document.planItems[0].notes["Lights"], "Dim on cue")
        XCTAssertEqual(document.planItems[0].waypointIds, ["w1"])
        XCTAssertEqual(document.waypoints.map(\.name), ["Song 1"])
        XCTAssertEqual(document.activeItemIndex, 1)
        XCTAssertEqual(document.serviceSchedules.first?.recurrence, .weekly)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("remote-\(UUID().uuidString).13years")
        defer { try? FileManager.default.removeItem(at: url) }
        try document.write(to: url)
        let reread = try ProducerDocument.read(from: url)
        XCTAssertEqual(reread.planItems.map(\.id), ["a", "b"])
        XCTAssertEqual(reread.planItems[0].notes["Lights"], "Dim on cue")
        XCTAssertEqual(reread.waypoints.map(\.name), ["Song 1"])
    }

    func testMirrorSessionStartsWithoutAFileSoSaveActsAsSaveAs() {
        let session = RemoteProducerSession(endpoint: RemoteEndpoint(host: "127.0.0.1", name: "David"))
        XCTAssertNil(session.engine.currentDocumentURL)
    }

    private func render(_ view: some View, size: CGSize, name: String) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
    }

    func testSnapshotSettingsAndBanner() {
        let hub = RemoteProducerHub()
        let session = RemoteProducerSession(endpoint: RemoteEndpoint(host: "127.0.0.1", name: "David Headless Producer"))
        session.engine.apply(remoteState: RemoteFixtures.state(rev: 1))
        let local = CueEngine(isMasterServer: true, startsNetworking: false)
        render(SettingsView().environmentObject(local).environmentObject(LaunchPreferences()), size: CGSize(width: 700, height: 2700), name: "clockkit-settings")
        render(RemoteProducerContainerView(session: session, lan: hub.lan) {}, size: CGSize(width: 900, height: 300), name: "clockkit-banner")
    }
}
