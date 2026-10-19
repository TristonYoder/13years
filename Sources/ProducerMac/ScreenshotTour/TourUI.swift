// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import AppKit

struct TourElement {
    let object: NSAccessibilityProtocol
    let role: String
    let label: String
    let title: String
    let identifier: String
    let help: String
    let value: String

    init(_ object: NSAccessibilityProtocol) {
        self.object = object
        let roleGetter: (() -> NSAccessibility.Role?)? = object.accessibilityRole
        let labelGetter: (() -> String?)? = object.accessibilityLabel
        let titleGetter: (() -> String?)? = object.accessibilityTitle
        let helpGetter: (() -> String?)? = object.accessibilityHelp
        let valueGetter: (() -> Any?)? = object.accessibilityValue
        role = roleGetter?()?.rawValue ?? ""
        label = labelGetter?() ?? ""
        title = titleGetter?() ?? ""
        identifier = object.accessibilityIdentifier() ?? ""
        help = helpGetter?() ?? ""
        value = (valueGetter?() as? String) ?? ""
    }

    var frame: NSRect { object.accessibilityFrame() }

    var isButton: Bool {
        role == NSAccessibility.Role.button.rawValue
            || role == NSAccessibility.Role.popUpButton.rawValue
            || role == NSAccessibility.Role.menuButton.rawValue
            || role == NSAccessibility.Role.radioButton.rawValue
            || role == NSAccessibility.Role.checkBox.rawValue
    }

    func names() -> [String] { [label, title, identifier].filter { !$0.isEmpty } }

    var summary: String {
        "\(role) label=\"\(label)\" title=\"\(title)\" id=\"\(identifier)\" help=\"\(help)\" value=\"\(value)\" frame=\(NSStringFromRect(frame))"
    }
}

enum TourUIError: Error, CustomStringConvertible {
    case notFound(String)
    case timedOut(String)
    case skipped(String)

    var description: String {
        switch self {
        case .notFound(let what): return "not found: \(what)"
        case .timedOut(let what): return "timed out waiting for \(what)"
        case .skipped(let reason): return reason
        }
    }
}

@MainActor
enum TourUI {
    static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible }
            ?? NSApp.windows.first { $0.canBecomeMain && $0.isVisible && !$0.isSheet && $0.title != "Flash a Pager" }
    }

    static func children(of object: NSAccessibilityProtocol) -> [NSAccessibilityProtocol] {
        let getter: (() -> [Any]?)? = object.accessibilityChildren
        let raw: [Any] = getter?() ?? []
        return raw.compactMap { $0 as? NSAccessibilityProtocol }
    }

    static func walk(_ root: NSAccessibilityProtocol, limit: Int = 40_000, visit: (TourElement, Int) -> Bool) {
        var stack: [(NSAccessibilityProtocol, Int)] = [(root, 0)]
        var count = 0
        while count < limit, let entry = stack.popLast() {
            let (node, depth) = entry
            count += 1
            if !visit(TourElement(node), depth) { return }
            guard depth < 80 else { continue }
            for child in children(of: node).reversed() {
                stack.append((child, depth + 1))
            }
        }
    }

    static func elements(in window: NSWindow, where predicate: (TourElement) -> Bool) -> [TourElement] {
        var found: [TourElement] = []
        walk(window) { element, _ in
            if predicate(element) { found.append(element) }
            return true
        }
        return found
    }

    static func button(named name: String, in window: NSWindow) -> TourElement? {
        let matches = elements(in: window) { $0.isButton && $0.names().contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
        if let match = matches.first { return match }
        return elements(in: window) { $0.isButton && $0.help.caseInsensitiveCompare(name) == .orderedSame }.first
    }

    static func dump(_ window: NSWindow) -> String {
        var lines: [String] = []
        walk(window) { element, depth in
            lines.append(String(repeating: "  ", count: depth) + element.summary)
            return true
        }
        return lines.joined(separator: "\n")
    }

    static func press(_ element: TourElement, in window: NSWindow) {
        let pressGetter: (() -> Bool)? = element.object.accessibilityPerformPress
        if pressGetter?() == true { return }
        let frame = element.frame
        click(at: NSPoint(x: frame.midX, y: frame.midY), in: window)
    }

    static func click(at screenPoint: NSPoint, in window: NSWindow) {
        let point = window.convertPoint(fromScreen: screenPoint)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            ) else { continue }
            window.sendEvent(event)
        }
    }

    static func rightClick(at screenPoint: NSPoint, in window: NSWindow) {
        let point = window.convertPoint(fromScreen: screenPoint)
        guard let event = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else { return }
        var view = window.contentView?.hitTest(window.contentView?.convert(point, from: nil) ?? point)
        while let current = view {
            if let menu = current.menu(for: event) {
                NSMenu.popUpContextMenu(menu, with: event, for: current)
                return
            }
            view = current.superview
        }
        window.sendEvent(event)
    }

    static func pressEscape(in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false,
                keyCode: 53
            ) else { continue }
            window.sendEvent(event)
        }
    }

    static func appKitButtons(in view: NSView) -> [NSButton] {
        var result: [NSButton] = []
        if let button = view as? NSButton { result.append(button) }
        for subview in view.subviews { result.append(contentsOf: appKitButtons(in: subview)) }
        return result
    }

    static func scrollViews(in view: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        if let scroll = view as? NSScrollView { result.append(scroll) }
        for subview in view.subviews { result.append(contentsOf: scrollViews(in: subview)) }
        return result
    }

    static var popoverWindows: [NSWindow] {
        NSApp.windows.filter { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
    }

    static func deepestSheet(of window: NSWindow) -> NSWindow? {
        var current = window.attachedSheet
        while let next = current?.attachedSheet { current = next }
        return current
    }

    static func sheetDepth(of window: NSWindow) -> Int {
        var depth = 0
        var current = window.attachedSheet
        while let sheet = current {
            depth += 1
            current = sheet.attachedSheet
        }
        return depth
    }

    static func findMenuItem(in menu: NSMenu, where predicate: (NSMenuItem) -> Bool) -> NSMenuItem? {
        for item in menu.items {
            if predicate(item) { return item }
            if let submenu = item.submenu, let found = findMenuItem(in: submenu, where: predicate) { return found }
        }
        return nil
    }
}
