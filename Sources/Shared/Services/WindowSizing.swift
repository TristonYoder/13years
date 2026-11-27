// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI
#if os(macOS)
import AppKit
#endif

enum WindowSizing {
    static func grow(by extra: CGFloat) {
        #if os(macOS)
        guard extra > 1, let window = NSApp.mainWindow ?? NSApp.keyWindow, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.size.width = min(frame.width + extra, visible.width)
        let overflow = frame.maxX - visible.maxX
        if overflow > 0 { frame.origin.x = max(visible.minX, frame.origin.x - overflow) }
        window.setFrame(frame, display: true, animate: true)
        #endif
    }

    static func ensure(width needed: CGFloat, current: CGFloat) {
        grow(by: needed - current)
    }
}

struct WidthReader: ViewModifier {
    @Binding var width: CGFloat

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newValue in width = newValue }
            }
        )
    }
}

extension View {
    func readWidth(into width: Binding<CGFloat>) -> some View {
        modifier(WidthReader(width: width))
    }
}
