// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import AppKit
import SwiftUI

enum PagerMenuBarPreferences {
    static let selectedRoleKey = "pagerSelectedRoleId"
    static let showKey = "menuBarShowItem"
    static let showItemNameKey = "menuBarShowItemName"
    static let showUnreadBadgeKey = "menuBarShowUnreadBadge"
    static let priorityTakeoverKey = "menuBarPriorityTakeover"
    static let hideDockIconKey = "menuBarHideDockIcon"
    static let lastReadKey = "menuBarLastReadMessage"

    static var showsItem: Bool {
        UserDefaults.standard.object(forKey: showKey) as? Bool ?? true
    }

    static var hidesDockIcon: Bool {
        UserDefaults.standard.bool(forKey: hideDockIconKey)
    }

    static var selectedRoleId: String {
        UserDefaults.standard.string(forKey: selectedRoleKey) ?? "default"
    }
}

@MainActor
final class PagerMenuBarReadState: ObservableObject {
    @Published private var lastRead: [String: Double]
    private let launchDate = Date()

    init() {
        lastRead = UserDefaults.standard.dictionary(forKey: PagerMenuBarPreferences.lastReadKey) as? [String: Double] ?? [:]
    }

    static func incoming(in messages: [InterTeamMessage], roleId: String) -> [InterTeamMessage] {
        messages
            .filter { ($0.targetRoleId == nil || $0.targetRoleId == roleId) && $0.senderRoleId == nil }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func unread(in messages: [InterTeamMessage], roleId: String) -> [InterTeamMessage] {
        var cutoff = lastRead[roleId].map(Date.init(timeIntervalSince1970:)) ?? launchDate
        if let reply = messages.filter({ $0.senderRoleId == roleId }).map(\.timestamp).max(), reply > cutoff {
            cutoff = reply
        }
        return Self.incoming(in: messages, roleId: roleId).filter { $0.timestamp > cutoff }
    }

    func markRead(in messages: [InterTeamMessage], roleId: String) {
        guard let newest = Self.incoming(in: messages, roleId: roleId).first?.timestamp.timeIntervalSince1970,
              newest > (lastRead[roleId] ?? 0) else { return }
        lastRead[roleId] = newest
        UserDefaults.standard.set(lastRead, forKey: PagerMenuBarPreferences.lastReadKey)
    }
}

@MainActor
final class PagerMenuBarController: NSObject, NSPopoverDelegate {
    static private(set) var shared: PagerMenuBarController?

    private let engine: CueEngine
    private let readState = PagerMenuBarReadState()
    private var statusItem: NSStatusItem?
    private var labelView: StatusItemHostingView?
    private let popover = NSPopover()
    private var outsideClickMonitor: Any?
    private var defaultsObserver: NSObjectProtocol?

    var openPagerWindow: (() -> Void)?

    init(engine: CueEngine) {
        self.engine = engine
        super.init()
        Self.shared = self
        DispatchQueue.main.async { [weak self] in self?.start() }
    }

    private func start() {
        let panel = PagerMenuBarPanel(
            openPager: { [weak self] in self?.showPagerWindow() },
            openSettings: { [weak self] in self?.showSettings() }
        )
        .environmentObject(engine)
        .environmentObject(readState)
        let controller = NSHostingController(rootView: panel)
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self

        applyPreferences()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPreferences() }
        }
    }

    private func applyPreferences() {
        let show = PagerMenuBarPreferences.showsItem
        if show, statusItem == nil {
            installStatusItem()
        } else if !show, let item = statusItem {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            labelView = nil
        }
        let policy: NSApplication.ActivationPolicy = show && PagerMenuBarPreferences.hidesDockIcon ? .accessory : .regular
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(togglePanel(_:))
        button.setAccessibilityLabel("13 Years Pager")

        let label = PagerMenuBarLabel()
            .environmentObject(engine)
            .environmentObject(readState)
        let host = StatusItemHostingView(rootView: AnyView(label))
        host.onSizeChange = { [weak self] in self?.layoutLabel() }
        button.addSubview(host)

        statusItem = item
        labelView = host
        layoutLabel()
    }

    private func layoutLabel() {
        guard let item = statusItem, let host = labelView, let button = item.button else { return }
        let size = host.fittingSize
        let padding: CGFloat = 4
        item.length = ceil(size.width) + padding * 2
        host.frame = NSRect(x: padding, y: 0, width: ceil(size.width), height: button.bounds.height)
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            markRead()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            sender.highlight(true)
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.popover.performClose(nil) }
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        markRead()
        statusItem?.button?.highlight(false)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func markRead() {
        readState.markRead(in: engine.recentMessages, roleId: PagerMenuBarPreferences.selectedRoleId)
    }

    private func showPagerWindow() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(PagerMacApp.pagerWindowId) == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openPagerWindow?()
        }
    }

    private func showSettings() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

private final class StatusItemHostingView: NSHostingView<AnyView> {
    var onSizeChange: (() -> Void)?

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        sizingOptions = [.intrinsicContentSize]
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.onSizeChange?() }
    }
}
