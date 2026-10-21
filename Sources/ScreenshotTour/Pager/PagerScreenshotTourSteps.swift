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
        list.append(contentsOf: extraRoleSteps())
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

    private func extraRoleSteps() -> [Step] {
        guard let role = runner.options.role else { return [] }
        let slug = role.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
        let variants: [(PagerResolvedLayout, CueState, String, String)] = [
            (.portrait, .off, "portrait", "Portrait"),
            (.landscape, .off, "details-split", "Landscape with the item details split"),
            (.landscape, .standby, "details-split-standby", "Landscape with the item details split, STANDBY"),
            (.lowerThird, .off, "lower-third", "Lower third")
        ]
        return variants.map { layout, state, suffix, title in
            Step(id: "pager.\(slug)-\(suffix)", title: "\(role) pager, \(title)", prepare: { [unowned self] in
                guard hasRole(named: role) else {
                    throw TourUIError.skipped("the document has no \(role) role")
                }
                try await show(Scene(role: role, state: state, layout: layout))
                await pause(1.2)
            })
        }
    }

    func show(_ scene: Scene) async throws {
        guard Self.supportedLayouts.contains(scene.layout) else {
            throw TourUIError.skipped("Apple TV always uses the landscape layout")
        }
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

    #if os(iOS) || os(tvOS)
    #if os(tvOS)
    static var waitingLayout: PagerResolvedLayout { .landscape }
    static var sheetLayout: PagerResolvedLayout { .landscape }
    static var supportedLayouts: [PagerResolvedLayout] { [.landscape] }

    func arrange(_ layout: PagerResolvedLayout) async throws {
        await pause(0.3)
    }

    private func platformSteps() -> [Step] {
        [Step(id: "pager.landscape-go-fullscreen", title: "Landscape pager, GO with the full screen cue display", prepare: { [unowned self] in
            try await show(Scene(state: .go, layout: .landscape, cueDisplay: .fullscreen))
        })]
    }
    #else
    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    static var currentLayout: PagerResolvedLayout { ScreenshotTour.orientationName.hasPrefix("landscape") ? .landscape : .portrait }
    static var waitingLayout: PagerResolvedLayout { isPad ? currentLayout : .portrait }
    static var sheetLayout: PagerResolvedLayout { isPad ? currentLayout : .portrait }
    static var supportedLayouts: [PagerResolvedLayout] { [.portrait, .landscape, .lowerThird] }

    func arrange(_ layout: PagerResolvedLayout) async throws {
        try await runner.rotate(to: layout == .portrait ? .portrait : (Self.isPad ? .landscape : .landscapeRight))
    }

    private func platformSteps() -> [Step] { [] }
    #endif
    static var sheetCapture: ScreenshotTour.Capture { .screen }

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
            throw TourUIError.skipped("the role menu needs a touch or the remote")
        })
    }

    private func pickerSteps() -> [Step] {
        [("cue-display", "Cue display"), ("layout", "Layout")].map { slug, title in
            Step(id: "pager.settings-\(slug)-picker", title: "Pager Settings, \(title) picker", prepare: {
                #if os(tvOS)
                if slug == "layout" { throw TourUIError.skipped("Pager Settings on Apple TV has no layout picker") }
                #endif
                throw TourUIError.skipped("menu pickers need a touch or the remote")
            })
        }
    }

    #else
    static var waitingLayout: PagerResolvedLayout { .landscape }
    static var sheetLayout: PagerResolvedLayout { .landscape }
    static var supportedLayouts: [PagerResolvedLayout] { [.portrait, .landscape, .lowerThird] }
    static var sheetCapture: ScreenshotTour.Capture { .appWindows }

    static func windowSize(for layout: PagerResolvedLayout) -> CGSize {
        switch layout {
        case .portrait: return CGSize(width: 540, height: 900)
        case .landscape: return CGSize(width: 1080, height: 680)
        case .lowerThird: return CGSize(width: 1920, height: 240)
        }
    }

    static let esp32Size = CGSize(width: 240, height: 320)

    func arrange(_ layout: PagerResolvedLayout) async throws {
        runner.configureWindow(size: windowSizeOverride ?? Self.windowSize(for: layout))
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
                throw TourUIError.skipped("SwiftUI does not expose the role menu to the tour")
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

    private func esp32SizeSteps() -> [Step] {
        let variants: [(CueState, CueDisplayStyle, Bool, String, String)] = [
            (.off, .outline, false, "", "no cue"),
            (.standby, .outline, false, "-standby", "STANDBY"),
            (.go, .outline, false, "-go", "GO"),
            (.standby, .outline, true, "-message", "with a producer message"),
            (.go, .fullscreen, false, "-go-fullscreen", "GO with the full screen cue display")
        ]
        return variants.map { state, display, messages, suffix, title in
            Step(id: "pager.esp32-size\(suffix)", title: "Mac pager at the ESP32 pager's 240×320 size, \(title)", prepare: { [unowned self] in
                windowSizeOverride = Self.esp32Size
                try await show(Scene(state: state, layout: .portrait, cueDisplay: display, messages: messages))
            }, cleanup: { [unowned self] in
                windowSizeOverride = nil
            })
        }
    }

    private func platformSteps() -> [Step] {
        var list: [Step] = esp32SizeSteps()
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
