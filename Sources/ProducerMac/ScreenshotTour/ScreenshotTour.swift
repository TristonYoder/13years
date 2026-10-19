// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import AppKit
import SwiftUI

@MainActor
final class ScreenshotTour {
    enum Capture {
        case mainWindow
        case appWindows
        case menus
        case mainWindowAndMenus
        case statusMenu
        case window(() -> NSWindow?)
    }

    struct Step {
        let id: String
        let title: String
        var capture: Capture = .mainWindow
        var prepare: () async throws -> Void = {}
        var tracking: ((TrackingSession) -> Void)?
        var cleanup: () async -> Void = {}
    }

    enum Outcome {
        case captured
        case skipped(String)
        case failed(String)
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

    private struct Record: Encodable {
        let index: Int
        let id: String
        let title: String
        let file: String?
        let status: String
        let reason: String?
        let seconds: Double
    }

    let options: ScreenshotTourOptions
    let engine: CueEngine
    let documents: DocumentController
    let flashingWindow: PagerFlashingWindowController
    private var records: [Record] = []
    private var started = false

    static var current: ScreenshotTour?

    init(options: ScreenshotTourOptions, engine: CueEngine, documents: DocumentController, flashingWindow: PagerFlashingWindowController) {
        self.options = options
        self.engine = engine
        self.documents = documents
        self.flashingWindow = flashingWindow
    }

    static func prepareProcess() {
        guard let options = ScreenshotTourOptions.current else { return }
        setenv("THIRTEEN_EPHEMERAL_KEYCHAIN", "1", 1)
        UpdateChecker.shared.isAutomaticCheckingSuspended = true
        try? FileManager.default.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)
    }

    func start() {
        guard !started else { return }
        started = true
        engine.setLANServingSuspended(true)
        if let appearance = options.appearance { NSApp.appearance = NSAppearance(named: appearance) }
        Task { await run() }
    }

    private var pendingURL: URL { options.outputDirectory.appendingPathComponent(".pending.json") }
    private var ackURL: URL { options.outputDirectory.appendingPathComponent(".ack.json") }
    private var debugDirectory: URL { options.outputDirectory.appendingPathComponent(".debug", isDirectory: true) }

    private func run() async {
        for _ in 0..<100 where TourUI.mainWindow == nil {
            await pause(0.1)
        }
        configureWindow()
        if let url = options.documentURL {
            documents.open(url, in: engine)
        }
        await pause(1.0)
        configureWindow()
        let all = steps()
        for (offset, step) in all.enumerated() where options.includes(step.id) {
            let index = offset + 1
            let file = String(format: "%02d-%@.png", index, step.id.replacingOccurrences(of: ".", with: "-"))
            let began = Date()
            let outcome = await perform(step, index: index, file: file)
            await step.cleanup()
            await dismissOverlays()
            switch outcome {
            case .captured:
                records.append(Record(index: index, id: step.id, title: step.title, file: file, status: "ok", reason: nil, seconds: (Date().timeIntervalSince(began) * 10).rounded() / 10))
            case .skipped(let reason):
                records.append(Record(index: index, id: step.id, title: step.title, file: nil, status: "skipped", reason: reason, seconds: (Date().timeIntervalSince(began) * 10).rounded() / 10))
            case .failed(let reason):
                records.append(Record(index: index, id: step.id, title: step.title, file: nil, status: "failed", reason: reason, seconds: (Date().timeIntervalSince(began) * 10).rounded() / 10))
                writeDebug(step.id)
            }
        }
        finish()
    }

    private func perform(_ step: Step, index: Int, file: String) async -> Outcome {
        do {
            try await step.prepare()
        } catch let error as TourUIError {
            if case .skipped(let reason) = error { return .skipped(reason) }
            return .failed(error.description)
        } catch {
            return .failed(String(describing: error))
        }
        if let tracking = step.tracking {
            return await captureWhileTracking(step, index: index, file: file, open: tracking)
        }
        await pause(0.9)
        await tidyBeforeCapture()
        return await capture(step, index: index, file: file)
    }

    private func captureWhileTracking(_ step: Step, index: Int, file: String, open: @escaping (TrackingSession) -> Void) async -> Outcome {
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

    private func windowIDs(for capture: Capture) -> (ids: [Int], menus: Bool) {
        let main = TourUI.mainWindow.map { [$0.windowNumber] } ?? []
        switch capture {
        case .mainWindow:
            return (main, false)
        case .appWindows:
            let visible = NSApp.windows.filter { window in
                window.isVisible && window.alphaValue > 0 && window.frame.width > 4
                    && !String(describing: type(of: window)).contains("StatusBar")
                    && NSScreen.screens.contains { $0.frame.intersects(window.frame) }
            }
            return (visible.map(\.windowNumber), false)
        case .menus:
            return ([], true)
        case .mainWindowAndMenus:
            return (main, true)
        case .statusMenu:
            let status = NSApp.windows.filter { $0.isVisible && String(describing: type(of: $0)).contains("StatusBar") }
            return (status.map(\.windowNumber), true)
        case .window(let provider):
            return (provider().map { [$0.windowNumber] } ?? [], false)
        }
    }

    private func writeRequest(_ step: Step, index: Int, file: String) -> String? {
        let target = windowIDs(for: step.capture)
        guard !target.ids.isEmpty || target.menus else { return "no window to capture" }
        try? FileManager.default.removeItem(at: ackURL)
        let pending: [String: Any] = [
            "index": index,
            "id": step.id,
            "title": step.title,
            "file": file,
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "windowIDs": target.ids,
            "includeMenus": target.menus
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: pending, options: [.sortedKeys]) else { return "could not encode request" }
        do {
            try data.write(to: pendingURL, options: .atomic)
        } catch {
            return "could not write request: \(error.localizedDescription)"
        }
        return nil
    }

    private func readAck(index: Int) -> Outcome? {
        guard let ack = try? Data(contentsOf: ackURL),
              let object = try? JSONSerialization.jsonObject(with: ack) as? [String: Any],
              object["index"] as? Int == index else { return nil }
        if object["ok"] as? Bool == true { return .captured }
        return .failed(object["error"] as? String ?? "capture failed")
    }

    private func capture(_ step: Step, index: Int, file: String) async -> Outcome {
        if let error = writeRequest(step, index: index, file: file) { return .failed(error) }
        for _ in 0..<300 {
            if let outcome = readAck(index: index) { return outcome }
            await pause(0.1)
        }
        return .failed("no capture acknowledgement")
    }

    private func finish() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(records) {
            try? data.write(to: options.outputDirectory.appendingPathComponent(".tour.json"), options: .atomic)
        }
        NSApp.terminate(nil)
    }

    private func writeDebug(_ id: String) {
        try? FileManager.default.createDirectory(at: debugDirectory, withIntermediateDirectories: true)
        var text = ""
        for window in NSApp.windows where window.isVisible {
            text += "=== \(type(of: window)) #\(window.windowNumber) \(NSStringFromRect(window.frame)) title=\"\(window.title)\"\n"
            text += TourUI.dump(window) + "\n"
        }
        try? text.write(to: debugDirectory.appendingPathComponent("\(id).txt"), atomically: true, encoding: .utf8)
    }

    private func tidyBeforeCapture() async {
        let popovers = TourUI.popoverWindows
        for window in NSApp.windows where window.isVisible && !popovers.contains(where: { $0 === window }) {
            window.makeFirstResponder(nil)
        }
        if engine.pcoLastError != nil { engine.pcoLastError = nil }
        await pause(0.3)
    }

    func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func configureWindow() {
        guard let window = TourUI.mainWindow else { return }
        let screen = NSScreen.screens.first ?? NSScreen.main
        window.setContentSize(options.contentSize)
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
            let extras = NSApp.windows.filter { $0.isVisible && $0 !== main && $0.title == "Flash a Pager" }
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
}
