// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import AppKit
import SwiftUI

extension ProducerScreenshotTour {
    func steps() -> [Step] {
        var list: [Step] = []

        list.append(Step(id: "launcher", title: "Launcher", prepare: { [unowned self] in
            documents.isLauncherPresented = true
        }, cleanup: { [unowned self] in
            documents.isLauncherPresented = false
            await pause(0.5)
        }))

        list.append(Step(id: "pagers", title: "Pagers with the pager preview", prepare: { [unowned self] in
            seedCues()
            showPagers(layout: "automatic")
        }))
        for (slug, raw, title) in [("landscape", "landscape", "Landscape"), ("portrait", "portrait", "Portrait"), ("lower-third", "lowerThird", "Lower third")] {
            list.append(Step(id: "pagers.layout-\(slug)", title: "Pager preview, \(title) layout", prepare: { [unowned self] in
                showPagers(layout: raw)
            }, cleanup: {
                UserDefaults.standard.set("automatic", forKey: PagerLayoutChoice.storageKey)
            }))
        }
        list.append(Step(id: "pagers.preview-hidden", title: "Pagers without the preview", prepare: { [unowned self] in
            showPagers(layout: "automatic")
            UserDefaults.standard.set(false, forKey: "showPagerPreview")
        }, cleanup: {
            UserDefaults.standard.set(true, forKey: "showPagerPreview")
        }))
        list.append(Step(id: "pagers.pager-settings", title: "Pager preview settings sheet", capture: .appWindows, prepare: { [unowned self] in
            showPagers(layout: "automatic")
            await pause(0.6)
            ScreenshotTourSignal.post("pager.settings")
            _ = try await waitForSheet()
        }))

        list.append(Step(id: "runsheet.list", title: "Run Sheet, list layout", prepare: { [unowned self] in
            showRunSheet(layout: "list")
        }))
        list.append(Step(id: "runsheet.table", title: "Run Sheet, table layout", prepare: { [unowned self] in
            showRunSheet(layout: "table")
        }))
        list.append(Step(id: "runsheet.table-plan-panel", title: "Run Sheet table with the plan panel", prepare: { [unowned self] in
            showRunSheet(layout: "table", planPanel: true)
        }, cleanup: {
            UserDefaults.standard.set(false, forKey: "runSheetPlanPanelVisible")
        }))
        list.append(Step(id: "runsheet.table-now-next", title: "Run Sheet table with the Now & Next pane", prepare: { [unowned self] in
            engine.runSheetLayout.sidePaneTab = nil
            showRunSheet(layout: "table", nowNext: true)
        }))
        list.append(Step(id: "runsheet.table-now-next-details", title: "Now & Next pane, Details tab", prepare: { [unowned self] in
            engine.runSheetLayout.sidePaneTab = RunSheetLayoutSettings.detailsTabId
            showRunSheet(layout: "table", nowNext: true)
        }, cleanup: {
            UserDefaults.standard.set(false, forKey: "runSheetNowNextPane")
        }))
        list.append(Step(id: "runsheet.columns-popover", title: "Table columns popover", capture: .appWindows, prepare: { [unowned self] in
            showRunSheet(layout: "table")
            await pause(0.6)
            ScreenshotTourSignal.post("runsheet.columns")
            try await waitForPopover()
        }))
        list.append(Step(id: "runsheet.row-context-menu", title: "Run Sheet row context menu", capture: .mainWindowAndMenus, prepare: { [unowned self] in
            showRunSheet(layout: "table")
            await pause(0.8)
        }, tracking: { [unowned self] _ in
            rightClickRow()
        }))
        list.append(Step(id: "runsheet.new-waypoint-alert", title: "New Waypoint alert", capture: .appWindows, prepare: { [unowned self] in
            showRunSheet(layout: "table")
            await pause(0.8)
            ScreenshotTourSignal.post("runsheet.new-waypoint", target: try sampleItem().id)
            _ = try await waitForSheet()
        }))
        list.append(Step(id: "runsheet.item-editor", title: "Edit item sheet", capture: .appWindows, prepare: { [unowned self] in
            showRunSheet(layout: "list")
            await pause(0.6)
            ScreenshotTourSignal.post("runsheet.edit-item", target: try sampleItem().id)
            _ = try await waitForSheet()
        }))
        list.append(Step(id: "runsheet.add-item", title: "Add Item sheet", capture: .appWindows, prepare: { [unowned self] in
            showRunSheet(layout: "list")
            await pause(0.4)
            ScreenshotTourSignal.post("runsheet.add-item")
            _ = try await waitForSheet()
        }))
        list.append(Step(id: "runsheet.import-text", title: "Import Text sheet", capture: .appWindows, prepare: { [unowned self] in
            showRunSheet(layout: "list")
            await pause(0.4)
            ScreenshotTourSignal.post("runsheet.import-text")
            _ = try await waitForSheet()
        }))
        list.append(Step(id: "runsheet.event-times", title: "Event Times sheet", capture: .appWindows, prepare: { [unowned self] in
            showRunSheet(layout: "list")
            await pause(0.4)
            ScreenshotTourSignal.post("runsheet.event-times")
            _ = try await waitForSheet()
        }))
        list.append(Step(id: "runsheet.event-time-editor", title: "Event time editor", capture: .appWindows, prepare: { [unowned self] in
            showRunSheet(layout: "list")
            await pause(0.4)
            if engine.eventTimes.contains(where: { $0.pcoPlanTimeId != nil }) {
                throw TourUIError.skipped("event times from Planning Center have no editor")
            }
            throw TourUIError.skipped("the event time editor has no tour hook yet")
        }))
        list.append(Step(id: "runsheet.plan-picker", title: "Planning Center plan picker", prepare: {
            throw TourUIError.skipped("the plan picker needs a Planning Center sign-in and network access")
        }))
        list.append(Step(id: "runsheet.timer-keypad", title: "Header timer keypad", capture: .appWindows, prepare: { [unowned self] in
            showRunSheet(layout: "list")
            await pause(0.6)
            ScreenshotTourSignal.post("header.timer-keypad")
            try await waitForPopover()
        }))
        list.append(Step(id: "runsheet.note-popover", title: "Note pill popover", capture: .appWindows, prepare: { [unowned self] in
            showRunSheet(layout: "list")
            await pause(0.6)
            guard let text = engine.planItems.lazy.compactMap({ $0.runSheetNotePills(layout: self.engine.runSheetLayout).first?.text }).first else {
                throw TourUIError.skipped("the document has no item notes")
            }
            ScreenshotTourSignal.post("runsheet.note-pill", target: text)
            try await waitForPopover()
        }))
        list.append(Step(id: "runsheet.delete-confirmation", title: "Delete item confirmation", capture: .appWindows, prepare: { [unowned self] in
            showRunSheet(layout: "list")
            await pause(0.6)
            ScreenshotTourSignal.post("runsheet.delete-item", target: try sampleItem().id)
            _ = try await waitForSheet()
        }))

        list.append(Step(id: "messages.everyone", title: "Messages, Everyone thread", prepare: { [unowned self] in
            seedMessages()
            engine.selectedMessageThreadId = CueEngine.allMessagesThreadId
            engine.appMode = .messages
        }))
        list.append(Step(id: "messages.role-thread", title: "Messages, direct thread with a role", prepare: { [unowned self] in
            seedMessages()
            engine.appMode = .messages
            engine.selectedMessageThreadId = threadRoleId
        }))
        list.append(Step(id: "messages.clear-history-confirmation", title: "Clear message history confirmation", capture: .appWindows, prepare: { [unowned self] in
            seedMessages()
            engine.appMode = .messages
            engine.selectedMessageThreadId = CueEngine.allMessagesThreadId
            await pause(0.5)
            ScreenshotTourSignal.post("messages.clear-history")
            _ = try await waitForSheet()
        }))
        list.append(Step(id: "pagers.pager-chat", title: "Pager preview chat sheet", capture: .appWindows, prepare: { [unowned self] in
            seedMessages()
            showPagers(layout: "automatic")
            await pause(0.6)
            ScreenshotTourSignal.post("pager.chat")
            _ = try await waitForSheet()
        }))

        for page in 1...6 {
            list.append(Step(id: "settings.page-\(page)", title: "Settings, page \(page)", prepare: { [unowned self] in
                engine.appMode = .settings
                await pause(0.6)
                try scrollSettings(page: page)
            }))
        }
        list.append(Step(id: "settings.roles-sheet", title: "Roles & Pager Fields sheet", capture: .appWindows, prepare: { [unowned self] in
            try await openSettingsSheet("settings.roles")
        }))
        list.append(Step(id: "settings.waypoints-sheet", title: "Waypoint library sheet", capture: .appWindows, prepare: { [unowned self] in
            try await openSettingsSheet("settings.waypoints")
        }))
        list.append(Step(id: "settings.event-schedule-sheet", title: "Event Schedule sheet", capture: .appWindows, prepare: { [unowned self] in
            try await openSettingsSheet("settings.event-schedule")
        }))
        list.append(Step(id: "settings.event-schedule-editor", title: "Event Schedule editor", capture: .appWindows, prepare: { [unowned self] in
            try await openSettingsSheet("settings.event-schedule")
            ScreenshotTourSignal.post("settings.add-schedule")
            _ = try await waitForSheet(depth: 2)
        }))
        list.append(Step(id: "connect-to", title: "Connect To… sheet", prepare: {
            throw TourUIError.skipped("Connect To… needs Bonjour, Local Network permission and live peers")
        }))
        list.append(Step(id: "flash-pager", title: "Flash a Pager window", capture: .window({ NSApp.windows.first { $0.isVisible && $0.title == "Flash a Pager" } }), prepare: { [unowned self] in
            engine.appMode = .producerControl
            flashingWindow.present(cueEngine: engine)
            await pause(0.8)
            if let window = NSApp.windows.first(where: { $0.title == "Flash a Pager" }), let main = TourUI.mainWindow {
                window.setFrameTopLeftPoint(NSPoint(x: main.frame.minX + 80, y: main.frame.maxY - 60))
            }
        }, cleanup: {
            NSApp.windows.filter { $0.title == "Flash a Pager" }.forEach { $0.close() }
        }))

        list.append(contentsOf: runner.menuSteps())
        list.append(Step(id: "menu.menu-bar-extra", title: "Menu bar extra", capture: .statusMenu, tracking: { _ in
            let windows = NSApp.windows.filter { String(describing: type(of: $0)).contains("StatusBar") }
            let buttons = windows.flatMap { TourUI.appKitButtons(in: $0.contentView ?? NSView()) }
            buttons.first?.performClick(nil)
        }))
        return list
    }

    private var threadRoleId: String {
        engine.roles.first { $0.name == "Band" }?.id ?? engine.roles.first?.id ?? CueEngine.allMessagesThreadId
    }

    private func showPagers(layout: String) {
        UserDefaults.standard.set(true, forKey: "showPagerPreview")
        UserDefaults.standard.set(layout, forKey: PagerLayoutChoice.storageKey)
        engine.appMode = .producerControl
    }

    private func showRunSheet(layout: String, planPanel: Bool = false, nowNext: Bool = false) {
        UserDefaults.standard.set(layout, forKey: "runSheetLayout")
        UserDefaults.standard.set(planPanel, forKey: "runSheetPlanPanelVisible")
        UserDefaults.standard.set(nowNext, forKey: "runSheetNowNextPane")
        engine.appMode = .serviceFlow
        engine.pcoLastError = nil
        guard layout == "table" else { return }
        Task { @MainActor [weak self] in
            await self?.pause(0.4)
            self?.resetHorizontalScroll()
        }
    }

    private func resetHorizontalScroll() {
        guard let content = TourUI.mainWindow?.contentView else { return }
        for scroll in TourUI.scrollViews(in: content) where scroll.contentView.bounds.origin.x != 0 {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.origin.y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    private func seedCues() {
        for role in engine.roles {
            switch role.name {
            case "Host": engine.setCueForRole(id: role.id, state: .standby)
            case "Band": engine.setCueForRole(id: role.id, state: .go)
            default: break
            }
        }
    }

    private func seedMessages() {
        guard engine.recentMessages.isEmpty else { return }
        let now = Date()
        func role(_ name: String) -> RoleCue? { engine.roles.first { $0.name == name } }
        var messages: [InterTeamMessage] = [
            InterTeamMessage(text: "Doors are open. Places in 10.", timestamp: now.addingTimeInterval(-900)),
            InterTeamMessage(text: "Walk-in loop is up on the screens.", timestamp: now.addingTimeInterval(-600))
        ]
        if let band = role("Band") {
            messages.append(InterTeamMessage(targetRoleId: band.id, text: "Start the countdown song on my GO.", timestamp: now.addingTimeInterval(-540)))
            messages.append(InterTeamMessage(sender: band.name, targetRoleId: band.id, senderRoleId: band.id, text: "Copy. In-ears checked, ready.", timestamp: now.addingTimeInterval(-480)))
            messages.append(InterTeamMessage(targetRoleId: band.id, text: "Stretch the last chorus, host is running long.", timestamp: now.addingTimeInterval(-120), isHighPriority: true))
        }
        if let backstage = role("Backstage") {
            messages.append(InterTeamMessage(sender: backstage.name, targetRoleId: backstage.id, senderRoleId: backstage.id, text: "Host is mic'd and standing by.", timestamp: now.addingTimeInterval(-300)))
        }
        if let lighting = role("Lighting") {
            messages.append(InterTeamMessage(targetRoleId: lighting.id, text: "House to half after the welcome.", timestamp: now.addingTimeInterval(-240)))
        }
        engine.recentMessages = messages.sorted { $0.timestamp > $1.timestamp }
    }

    @discardableResult
    private func openSettingsSheet(_ name: String) async throws -> NSWindow {
        engine.appMode = .settings
        await pause(0.6)
        try? scrollSettings(page: 1)
        await pause(0.3)
        ScreenshotTourSignal.post(name)
        return try await waitForSheet()
    }

    private func settingsScrollView() -> NSScrollView? {
        guard let content = TourUI.mainWindow?.contentView else { return nil }
        return TourUI.scrollViews(in: content)
            .filter { $0.frame.width > 400 && $0.documentView != nil }
            .max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }
    }

    private func scrollSettings(page: Int) throws {
        guard let scroll = settingsScrollView(), let document = scroll.documentView else {
            throw TourUIError.notFound("settings scroll view")
        }
        let visible = scroll.contentView.bounds.height
        let total = document.frame.height
        let maxOffset = max(0, total - visible)
        let step = max(visible - 80, 100)
        let wanted = CGFloat(page - 1) * step
        if page > 1 && wanted - step >= maxOffset - 1 {
            throw TourUIError.skipped("Settings fits in fewer pages")
        }
        let offset = min(wanted, maxOffset)
        let y = document.isFlipped ? offset : maxOffset - offset
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func sampleItem() throws -> PCOTimerItem {
        guard let item = engine.planItems.first(where: { !$0.isHeader && !$0.notes.isEmpty }) ?? engine.planItems.first(where: { !$0.isHeader }) else {
            throw TourUIError.skipped("the document has no run sheet items")
        }
        return item
    }

    private func rightClickRow() {
        guard let window = TourUI.mainWindow, let content = window.contentView else { return }
        let candidates = TourUI.scrollViews(in: content).filter { $0.frame.width > 600 && $0.frame.height > 200 }
        guard let scroll = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { return }
        let visible = scroll.convert(scroll.bounds, to: nil)
        let point = NSPoint(x: visible.minX + min(260, visible.width / 3), y: visible.maxY - 130)
        TourUI.rightClick(at: window.convertPoint(toScreen: point), in: window)
    }
}
