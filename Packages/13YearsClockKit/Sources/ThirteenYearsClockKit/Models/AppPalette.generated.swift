// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if canImport(SwiftUI)
import SwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum AppPalette {
    public static let cueOff = fixed(0x141A26FF)
    public static let cueStandby = fixed(0xF5B826FF)
    public static let cueGo = fixed(0x26C759FF)
    public static let cueLightText = fixed(0xFFFFFFFF)
    public static let cueDarkText = fixed(0x1A1A1AFF)
    public static let pagerGround = fixed(0x111114FF)
    public static let pagerClock = fixed(0xF5F5F7FF)
    public static let pagerMessage = fixed(0xFFD60AFF)
    public static let pagerPanel = fixed(0x1B1B20FF)
    public static let displayBlack = fixed(0x000000FF)
    public static let displayWhite = fixed(0xFFFFFFFF)
    public static let positive = adaptive(light: 0x34C759FF, dark: 0x30D158FF)
    public static let warning = adaptive(light: 0xFF9500FF, dark: 0xFF9F0AFF)
    public static let negative = adaptive(light: 0xFF3B30FF, dark: 0xFF453AFF)
    public static let info = adaptive(light: 0x007AFFFF, dark: 0x0A84FFFF)
    public static let favorite = adaptive(light: 0xFFCC00FF, dark: 0xFFD60AFF)
    public static let remote = adaptive(light: 0xAF52DEFF, dark: 0xBF5AF2FF)
    public static let keyPill = adaptive(light: 0xAF52DEFF, dark: 0xBF5AF2FF)
    public static let rehearsal = adaptive(light: 0xAF52DEFF, dark: 0xBF5AF2FF)
    public static let timerOnTime = adaptive(light: 0x34C759FF, dark: 0x30D158FF)
    public static let timerWarning = adaptive(light: 0xFFCC00FF, dark: 0xFFD60AFF)
    public static let timerOvertime = fixed(0xCC1717FF)
    public static let driftLate = adaptive(light: 0xFF9500FF, dark: 0xFF9F0AFF)
    public static let driftEarly = adaptive(light: 0x34C759FF, dark: 0x30D158FF)
    public static let brandGround = adaptive(light: 0xF5F5F3FF, dark: 0x101014FF)
    public static let brandGroundDark = fixed(0x101014FF)
    public static let brandGroundLight = fixed(0xF5F5F3FF)
    public static let stoplightInkDark = fixed(0xF5F5F3FF)
    public static let stoplightRedDark = fixed(0xFF5252FF)
    public static let stoplightYellowDark = fixed(0xFFEB3BFF)
    public static let stoplightGreenDark = fixed(0x66BB6AFF)
    public static let stoplightInkLight = fixed(0x333333FF)
    public static let stoplightRedLight = fixed(0xDC143CFF)
    public static let stoplightYellowLight = fixed(0xFFD700FF)
    public static let stoplightGreenLight = fixed(0x228B22FF)
    public static let sectionCard = adaptive(light: 0xFFFFFFFF, dark: 0x232328FF)
    public static let sectionCardBorder = adaptive(light: 0x0000001F, dark: 0xFFFFFF1A)
    public static let sectionHeaderTint = adaptive(light: 0xAF52DE12, dark: 0xBF5AF224)
    public static let sectionHeaderText = adaptive(light: 0x7A3AA5FF, dark: 0xD7A8F2FF)
    public static let highlightMarker = adaptive(light: 0xFFE0668C, dark: 0xFFB02059)
    public static let rowActive = adaptive(light: 0x34C75924, dark: 0x30D15824)
    public static let rowSelected = adaptive(light: 0x007AFF38, dark: 0x0A84FF38)
    public static let rowHeader = fixed(0x8E8E9324)
    public static let driftLateFill = adaptive(light: 0xFF950029, dark: 0xFF9F0A29)
    public static let driftEarlyFill = adaptive(light: 0x34C75929, dark: 0x30D15829)
    public static let keyPillFill = adaptive(light: 0xAF52DE29, dark: 0xBF5AF229)
    public static let keyPillText = adaptive(light: 0xAF52DEFF, dark: 0xBF5AF2FF)
    public static let rehearsalFill = adaptive(light: 0xAF52DE26, dark: 0xBF5AF226)
    public static let warningFill = adaptive(light: 0xFF950026, dark: 0xFF9F0A26)
    public static let surfaceSubtle = adaptive(light: 0x3C3C4312, dark: 0xEBEBF512)
    public static let surfaceMuted = adaptive(light: 0x3C3C431A, dark: 0xEBEBF51A)
    public static let surfaceControl = adaptive(light: 0x00000014, dark: 0xFFFFFF14)
    public static let surfaceControlPressed = adaptive(light: 0x00000029, dark: 0xFFFFFF29)
    public static let bubbleReceived = adaptive(light: 0x7878801F, dark: 0x7878803D)
    public static let launcherBorder = adaptive(light: 0xFFFFFF66, dark: 0xFFFFFF14)
    public static let keypadKey = fixed(0x292929FF)
    public static let scrimFaint = fixed(0x00000033)
    public static let scrimSoft = fixed(0x0000004D)
    public static let scrimMedium = fixed(0x00000073)
    public static let scrimStrong = fixed(0x000000B3)
    public static let glassFaint = fixed(0xFFFFFF14)
    public static let glassSoft = fixed(0xFFFFFF1F)
    public static let glassMedium = fixed(0xFFFFFF33)
    public static let glassBorder = fixed(0xFFFFFF4D)
    public static let glassBorderFocus = fixed(0xFFFFFF99)
    public static let pagerDimmed = fixed(0x8E8E9373)
    public static let focusRing = fixed(0xFFFFFFCC)
}

private extension AppPalette {
    static func fixed(_ value: UInt32) -> Color {
        Color(.sRGB,
              red: Double((value >> 24) & 0xFF) / 255,
              green: Double((value >> 16) & 0xFF) / 255,
              blue: Double((value >> 8) & 0xFF) / 255,
              opacity: Double(value & 0xFF) / 255)
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        #if os(watchOS)
        return fixed(dark)
        #elseif os(macOS)
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return component(isDark ? dark : light)
        }))
        #else
        return Color(uiColor: UIColor(dynamicProvider: { traits in
            component(traits.userInterfaceStyle == .dark ? dark : light)
        }))
        #endif
    }

    #if os(macOS)
    static func component(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 24) & 0xFF) / 255,
                green: CGFloat((value >> 16) & 0xFF) / 255,
                blue: CGFloat((value >> 8) & 0xFF) / 255,
                alpha: CGFloat(value & 0xFF) / 255)
    }
    #elseif canImport(UIKit) && !os(watchOS)
    static func component(_ value: UInt32) -> UIColor {
        UIColor(red: CGFloat((value >> 24) & 0xFF) / 255,
                green: CGFloat((value >> 16) & 0xFF) / 255,
                blue: CGFloat((value >> 8) & 0xFF) / 255,
                alpha: CGFloat(value & 0xFF) / 255)
    }
    #endif
}
#endif
