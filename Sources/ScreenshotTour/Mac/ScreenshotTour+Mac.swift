// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import AppKit
import SwiftUI

extension ScreenshotTour {
    enum Capture {
        case mainWindow
        case appWindows
        case menus
        case mainWindowAndMenus
        case statusMenu
        case window(() -> NSWindow?)
        case windowAndMenus(() -> NSWindow?)

        static var standard: Capture { .mainWindow }
    }

    @MainActor
    final class TrackingSession {
        var menu: NSMenu?
        var outcome: Outcome?
        var requested = false
        var finished = false
        var seenAt: Date?
        var afterTracking: (() -> Void)?
    }

    func waitForInterface() async {
        if let appearance = options.appearance {
            NSApp.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        }
        for _ in 0..<100 where TourUI.mainWindow == nil {
            await pause(0.1)
        }
        configureWindow()
    }

    func arrangeInterface() {
        configureWindow()
    }

    func terminate() {
        NSApp.terminate(nil)
    }

    func captureWhileTracking(_ step: Step, index: Int, file: String, open: @escaping (TrackingSession) -> Void) async -> Outcome {
        let session = await trackMenu(open: open) { [unowned self] session, _ in
            if !session.requested {
                session.requested = true
                if let error = writeRequest(step, index: index, file: file) {
                    session.outcome = .failed(error)
                    return true
                }
                return false
            }
            if let outcome = readAck(index: index) {
                session.outcome = outcome
                return true
            }
            return false
        }
        session.afterTracking?()
        return session.outcome ?? .failed("menu did not open")
    }

    func trackMenu(open: @escaping (TrackingSession) -> Void, settle: TimeInterval = 0.7, timeout: TimeInterval = 40, poll: @escaping (TrackingSession, NSMenu) -> Bool) async -> TrackingSession {
        let session = TrackingSession()
        let observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
            guard let menu = note.object as? NSMenu else { return }
            MainActor.assumeIsolated {
                if session.menu == nil { session.menu = menu }
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let begin = Date()
        let timer = Timer(timeInterval: 0.1, repeats: true) { timer in
            MainActor.assumeIsolated {
                guard !session.finished else {
                    timer.invalidate()
                    return
                }
                guard let menu = session.menu else {
                    if Date().timeIntervalSince(begin) > 6 {
                        session.finished = true
                        timer.invalidate()
                    }
                    return
                }
                let seen = session.seenAt ?? Date()
                session.seenAt = seen
                guard Date().timeIntervalSince(seen) >= settle else { return }
                if poll(session, menu) || Date().timeIntervalSince(seen) > timeout {
                    session.finished = true
                    timer.invalidate()
                    menu.cancelTracking()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        open(session)
        while !session.finished {
            await pause(0.1)
        }
        await pause(0.4)
        return session
    }

    func requestFields(for capture: Capture) throws -> [String: Any] {
        let main = TourUI.mainWindow.map { [$0.windowNumber] } ?? []
        let ids: [Int]
        let menus: Bool
        switch capture {
        case .mainWindow:
            (ids, menus) = (main, false)
        case .appWindows:
            let visible = NSApp.windows.filter { window in
                window.isVisible && window.alphaValue > 0 && window.frame.width > 4
                    && !String(describing: type(of: window)).contains("StatusBar")
                    && NSScreen.screens.contains { $0.frame.intersects(window.frame) }
            }
            (ids, menus) = (visible.map(\.windowNumber), false)
        case .menus:
            (ids, menus) = ([], true)
        case .mainWindowAndMenus:
            (ids, menus) = (main, true)
        case .statusMenu:
            let status = NSApp.windows.filter { $0.isVisible && String(describing: type(of: $0)).contains("StatusBar") }
            (ids, menus) = (status.map(\.windowNumber), true)
        case .window(let provider):
            (ids, menus) = (provider().map { [$0.windowNumber] } ?? [], false)
        case .windowAndMenus(let provider):
            (ids, menus) = (provider().map { [$0.windowNumber] } ?? [], true)
        }
        guard !ids.isEmpty || menus else { throw TourUIError.notFound("window to capture") }
        return ["windowIDs": ids, "includeMenus": menus]
    }

    func debugText() -> String {
        var text = ""
        for window in NSApp.windows where window.isVisible {
            text += "=== \(type(of: window)) #\(window.windowNumber) \(NSStringFromRect(window.frame)) title=\"\(window.title)\"\n"
            text += TourUI.dump(window) + "\n"
        }
        return text
    }

    func tidyBeforeCapture() async {
        let popovers = TourUI.popoverWindows
        for window in NSApp.windows where window.isVisible && !popovers.contains(where: { $0 === window }) {
            window.makeFirstResponder(nil)
        }
    }

    func configureWindow(size: CGSize? = nil) {
        guard let window = TourUI.mainWindow else { return }
        let screen = NSScreen.screens.first ?? NSScreen.main
        window.setContentSize(size ?? options.contentSize)
        if let visible = screen?.visibleFrame {
            window.setFrameTopLeftPoint(NSPoint(x: visible.minX + 40, y: visible.maxY - 16))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func dismissOverlays() async {
        for _ in 0..<10 {
            if let popover = TourUI.popoverWindows.first {
                TourUI.pressEscape(in: popover)
                await pause(0.4)
                if popover.isVisible { popover.close() }
                await pause(0.2)
                continue
            }
            guard let main = TourUI.mainWindow else { return }
            if let sheet = TourUI.deepestSheet(of: main) {
                let depth = TourUI.sheetDepth(of: main)
                dismissSheet(sheet)
                await pause(0.6)
                if TourUI.sheetDepth(of: main) >= depth {
                    TourUI.pressEscape(in: sheet)
                    await pause(0.6)
                }
                if TourUI.sheetDepth(of: main) >= depth, let parent = sheet.sheetParent {
                    parent.endSheet(sheet)
                    await pause(0.4)
                }
                continue
            }
            let extras = NSApp.windows.filter { $0.isVisible && $0 !== main && TourUI.auxiliaryWindowTitles.contains($0.title) }
            if !extras.isEmpty {
                extras.forEach { $0.close() }
                await pause(0.3)
                continue
            }
            main.makeKeyAndOrderFront(nil)
            return
        }
    }

    private func dismissSheet(_ sheet: NSWindow) {
        let safe = ["Cancel", "Done", "Close", "Not Now", "OK"]
        for name in safe {
            if let button = TourUI.appKitButtons(in: sheet.contentView ?? NSView()).first(where: { $0.title == name && $0.isEnabled }) {
                button.performClick(nil)
                return
            }
        }
        for name in safe {
            if let element = TourUI.button(named: name, in: sheet) {
                TourUI.press(element, in: sheet)
                return
            }
        }
    }

    @discardableResult
    func waitForSheet(depth: Int = 1) async throws -> NSWindow {
        for _ in 0..<40 {
            if let main = TourUI.mainWindow, TourUI.sheetDepth(of: main) >= depth, let sheet = TourUI.deepestSheet(of: main) {
                await pause(0.5)
                return sheet
            }
            await pause(0.15)
        }
        throw TourUIError.timedOut("sheet")
    }

    func waitForPopover() async throws {
        for _ in 0..<30 {
            if !TourUI.popoverWindows.isEmpty { return }
            await pause(0.15)
        }
        throw TourUIError.timedOut("popover")
    }

    func menuSteps() -> [Step] {
        guard let mainMenu = NSApp.mainMenu else { return [] }
        var seen = Set<String>()
        var steps: [Step] = []
        for (position, item) in mainMenu.items.enumerated() where item.submenu != nil && !item.isHidden {
            let title = item.submenu?.title.isEmpty == false ? item.submenu!.title : item.title
            var slug = position == 0 ? "app" : Self.slug(title)
            if slug.isEmpty || seen.contains(slug) { slug = "menu-\(position)" }
            seen.insert(slug)
            steps.append(Step(id: "menu.\(slug)", title: position == 0 ? "Application menu" : "\(title) menu", capture: .menus, tracking: { [unowned self] _ in
                guard let submenu = NSApp.mainMenu?.items.first(where: { $0 === item })?.submenu else { return }
                let origin = menuOrigin(position: position)
                submenu.popUp(positioning: nil, at: origin, in: nil)
            }))
        }
        return steps
    }

    private func menuOrigin(position: Int) -> NSPoint {
        let screen = NSScreen.screens.first?.visibleFrame ?? .zero
        return NSPoint(x: screen.minX + 80 + CGFloat(position) * 40, y: screen.maxY - 8)
    }

    static func slug(_ text: String) -> String {
        let lowered = text.lowercased()
        var result = ""
        var lastDash = false
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII {
                result.unicodeScalars.append(scalar)
                lastDash = false
            } else if !lastDash && !result.isEmpty {
                result.append("-")
                lastDash = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

extension ScreenshotTourClient {
    @discardableResult
    func waitForSheet(depth: Int = 1) async throws -> NSWindow {
        try await runner.waitForSheet(depth: depth)
    }

    func waitForPopover() async throws {
        try await runner.waitForPopover()
    }
}
