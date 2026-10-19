// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI
#if os(macOS)
import AppKit
#endif

extension PagerScreenshotTour {
    func steps() -> [Step] {
        var list: [Step] = []

        list.append(Step(id: "waiting", title: "Waiting for Producer", prepare: { [unowned self] in
            try await arrange(Self.waitingLayout)
            if engine.hasSyncedWithProducer {
                throw TourUIError.skipped("the pager already holds producer state")
            }
        }))

        let layouts: [(PagerResolvedLayout, String, String)] = [(.portrait, "portrait", "Portrait"), (.landscape, "landscape", "Landscape"), (.lowerThird, "lower-third", "Lower third")]
        let states: [(CueState, String, String)] = [(.off, "", "no cue"), (.standby, "-standby", "STANDBY"), (.go, "-go", "GO")]
        for (layout, slug, title) in layouts {
            for (state, suffix, stateTitle) in states {
                list.append(Step(id: "pager.\(slug)\(suffix)", title: "\(title) pager, \(stateTitle)", prepare: { [unowned self] in
                    try await show(Scene(state: state, layout: layout))
                }))
            }
            list.append(Step(id: "pager.\(slug)-message", title: "\(title) pager with a producer message", prepare: { [unowned self] in
                try await show(Scene(state: .standby, layout: layout, messages: true))
            }))
        }
        list.append(Step(id: "pager.portrait-go-fullscreen", title: "Portrait pager, GO with the full screen cue display", prepare: { [unowned self] in
            try await show(Scene(state: .go, layout: .portrait, cueDisplay: .fullscreen))
        }))
        list.append(Step(id: "pager.lower-third-controls", title: "Lower third pager with its controls showing", prepare: { [unowned self] in
            try await show(Scene(state: .off, layout: .lowerThird))
            ScreenshotTourSignal.post("pager.lower-third-controls")
            await pause(0.4)
        }))
        list.append(Step(id: "pager.details-split", title: "Landscape pager with the item details split", prepare: { [unowned self] in
            guard hasDetailsRole, let role = detailsRoleName else {
                throw TourUIError.skipped("no role in the document shows item details, or the featured item has none")
            }
            try await show(Scene(role: role, state: .off, layout: .landscape))
            await pause(1.2)
        }))
        list.append(roleMenuStep())

        list.append(Step(id: "pager.chat", title: "Messages sheet", capture: Self.sheetCapture, prepare: { [unowned self] in
            try await show(Scene(state: .off, layout: Self.sheetLayout, messages: true))
            await pause(0.4)
            ScreenshotTourSignal.post("pager.chat")
            try await waitForSheetPresented()
        }, cleanup: { [unowned self] in
            await dismissPagerSheets()
        }))
        list.append(Step(id: "pager.settings", title: "Pager Settings sheet", capture: Self.sheetCapture, prepare: { [unowned self] in
            try await openSettingsSheet()
        }, cleanup: { [unowned self] in
            await dismissPagerSheets()
        }))
        list.append(Step(id: "pager.settings-page-2", title: "Pager Settings sheet, scrolled", capture: Self.sheetCapture, prepare: { [unowned self] in
            try await openSettingsSheet()
            try scrollSettingsSheet()
            await pause(0.4)
        }, cleanup: { [unowned self] in
            await dismissPagerSheets()
        }))
        list.append(contentsOf: pickerSteps())
        list.append(contentsOf: platformSteps())
        return list
    }

    func show(_ scene: Scene) async throws {
        try apply(scene)
        try await arrange(scene.layout)
    }

    private func openSettingsSheet() async throws {
        try await show(Scene(state: .off, layout: Self.sheetLayout))
        await pause(0.4)
        ScreenshotTourSignal.post("pager.settings")
        try await waitForSheetPresented()
    }

    private func dismissPagerSheets() async {
        ScreenshotTourSignal.post("pager.dismiss")
        await pause(0.8)
    }

    #if os(iOS)
    static var waitingLayout: PagerResolvedLayout { .portrait }
    static var sheetLayout: PagerResolvedLayout { .portrait }
    static var sheetCapture: ScreenshotTour.Capture { .screen }

    func arrange(_ layout: PagerResolvedLayout) async throws {
        try await runner.rotate(to: layout == .portrait ? .portrait : .landscapeRight)
    }

    private func waitForSheetPresented() async throws {
        for _ in 0..<40 {
            if ScreenshotTour.keyWindow?.rootViewController?.presentedViewController != nil {
                await pause(0.8)
                return
            }
            await pause(0.15)
        }
        throw TourUIError.timedOut("sheet")
    }

    private func scrollSettingsSheet() throws {
        guard let scroll = runner.presentedScrollView() else { throw TourUIError.skipped("Pager Settings fits on one screen") }
        let top = -scroll.adjustedContentInset.top
        let maxOffset = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
        let offset = min(top + scroll.bounds.height - 120, maxOffset)
        guard offset > top + 40 else { throw TourUIError.skipped("Pager Settings fits on one screen") }
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
    }

    private func roleMenuStep() -> Step {
        Step(id: "pager.role-menu", title: "Role menu", prepare: {
            throw TourUIError.skipped("the role picker is a SwiftUI menu that opens only from a touch, which the simulator tour does not synthesize")
        })
    }

    private func pickerSteps() -> [Step] {
        [("cue-display", "Cue display"), ("layout", "Layout")].map { slug, title in
            Step(id: "pager.settings-\(slug)-picker", title: "Pager Settings, \(title) picker", prepare: {
                throw TourUIError.skipped("menu pickers open only from a touch, which the simulator tour does not synthesize")
            })
        }
    }

    private func platformSteps() -> [Step] { [] }
    #else
    static var waitingLayout: PagerResolvedLayout { .landscape }
    static var sheetLayout: PagerResolvedLayout { .landscape }
    static var sheetCapture: ScreenshotTour.Capture { .appWindows }

    static func windowSize(for layout: PagerResolvedLayout) -> CGSize {
        switch layout {
        case .portrait: return CGSize(width: 540, height: 900)
        case .landscape: return CGSize(width: 1080, height: 680)
        case .lowerThird: return CGSize(width: 1440, height: 240)
        }
    }

    func arrange(_ layout: PagerResolvedLayout) async throws {
        runner.configureWindow(size: Self.windowSize(for: layout))
        await pause(0.4)
    }

    private func waitForSheetPresented() async throws {
        try await waitForSheet()
    }

    private func scrollSettingsSheet() throws {
        guard let sheet = TourUI.mainWindow.flatMap(TourUI.deepestSheet(of:)), let content = sheet.contentView else {
            throw TourUIError.notFound("Pager Settings sheet")
        }
        guard let scroll = TourUI.scrollViews(in: content).filter({ $0.documentView != nil }).max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }),
              let document = scroll.documentView else {
            throw TourUIError.notFound("Pager Settings scroll view")
        }
        let visible = scroll.contentView.bounds.height
        let maxOffset = max(0, document.frame.height - visible)
        guard maxOffset > 40 else { throw TourUIError.skipped("Pager Settings fits in one page") }
        let offset = min(max(visible - 80, 100), maxOffset)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? offset : maxOffset - offset))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func roleMenuStep() -> Step {
        Step(id: "pager.role-menu", title: "Role menu", capture: .mainWindowAndMenus, prepare: { [unowned self] in
            try await show(Scene(state: .off, layout: .landscape))
            guard roleMenuButton() != nil else {
                throw TourUIError.skipped("SwiftUI does not expose the role menu button to in-process accessibility")
            }
        }, tracking: { [unowned self] _ in
            guard let window = TourUI.mainWindow, let element = roleMenuButton() else { return }
            TourUI.press(element, in: window)
        })
    }

    private func roleMenuButton() -> TourElement? {
        guard let window = TourUI.mainWindow else { return nil }
        let roleNames = Set(engine.roles.map(\.name))
        return TourUI.elements(in: window) { element in
            (element.role == NSAccessibility.Role.popUpButton.rawValue || element.role == NSAccessibility.Role.menuButton.rawValue)
                && (element.names().contains { roleNames.contains($0) } || element.value.isEmpty == false && roleNames.contains(element.value))
        }.first
    }

    private func pickerSteps() -> [Step] {
        [(0, "cue-display", "Cue display"), (1, "layout", "Layout")].map { position, slug, title in
            Step(id: "pager.settings-\(slug)-picker", title: "Pager Settings, \(title) picker", capture: .windowAndMenus({ TourUI.mainWindow.flatMap(TourUI.deepestSheet(of:)) }), prepare: { [unowned self] in
                try await openSettingsSheet()
                TourUI.mainWindow.flatMap(TourUI.deepestSheet(of:))?.makeFirstResponder(nil)
                guard settingsPopUps().count > position else {
                    throw TourUIError.skipped("the \(title) picker is not an AppKit pop-up button the tour can open")
                }
            }, tracking: { [unowned self] _ in
                let popUps = settingsPopUps()
                guard popUps.count > position else { return }
                popUps[position].performClick(nil)
            }, cleanup: { [unowned self] in
                await dismissPagerSheets()
            })
        }
    }

    private func settingsPopUps() -> [NSPopUpButton] {
        guard let sheet = TourUI.mainWindow.flatMap(TourUI.deepestSheet(of:)), let content = sheet.contentView else { return [] }
        return TourUI.appKitButtons(in: content)
            .compactMap { $0 as? NSPopUpButton }
            .sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
    }

    private static func settingsWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window.isVisible && !window.isSheet && (TourUI.isSettingsWindow(window) || window.title.localizedCaseInsensitiveContains("settings"))
        }
    }

    private func openSettingsWindow() {
        guard let menu = NSApp.mainMenu?.items.first?.submenu,
              let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command }) else {
            openSettingsWindow()
            return
        }
        menu.performActionForItem(at: index)
    }

    private func platformSteps() -> [Step] {
        var list: [Step] = []
        list.append(Step(id: "settings-window", title: "Settings window", capture: .window({ Self.settingsWindow() }), prepare: { [unowned self] in
            try await show(Scene(state: .off, layout: .landscape))
            openSettingsWindow()
            for _ in 0..<30 where Self.settingsWindow() == nil {
                await pause(0.15)
            }
            guard let window = Self.settingsWindow(), let main = TourUI.mainWindow else {
                throw TourUIError.timedOut("Settings window")
            }
            window.setFrameTopLeftPoint(NSPoint(x: main.frame.minX + 60, y: main.frame.maxY - 40))
            window.makeKeyAndOrderFront(nil)
            await pause(0.4)
        }, cleanup: {
            Self.settingsWindow()?.close()
        }))
        list.append(contentsOf: runner.menuSteps())
        list.append(Step(id: "menu.menu-bar-extra", title: "Menu bar extra", prepare: {
            throw TourUIError.skipped("the Mac Pager has no menu bar extra")
        }))
        return list
    }
    #endif
}
