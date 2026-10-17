// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if canImport(SwiftUI)
import SwiftUI

public enum AppPalette {
    public static let cueOff = Color(red: 0.08, green: 0.10, blue: 0.15)
    public static let cueStandby = Color(red: 0.96, green: 0.72, blue: 0.15)
    public static let cueGo = Color(red: 0.15, green: 0.78, blue: 0.35)
    public static let cueLightText = Color.white
    public static let cueDarkText = Color(red: 0.1, green: 0.1, blue: 0.1)

    public static let pagerGround = Color(red: 0.067, green: 0.067, blue: 0.078)
    public static let pagerClock = Color(white: 0.96)
    public static let pagerMessage = Color(red: 1, green: 0.84, blue: 0.04)

    public static let positive = Color.green
    public static let warning = Color.orange
    public static let negative = Color.red
    public static let info = Color.blue
    public static let favorite = Color.yellow
    public static let remote = Color.purple
    public static let keyPill = Color.purple
    public static let rehearsal = Color.purple

    public static let timerOnTime = Color.green
    public static let timerWarning = Color.yellow
    public static let timerOvertime = Color(red: 0.80, green: 0.09, blue: 0.09)

    public static let driftLate = Color.orange
    public static let driftEarly = Color.green

    public static let brandGroundDark = Color(red: 0x10 / 255, green: 0x10 / 255, blue: 0x14 / 255)
    public static let brandGroundLight = Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF3 / 255)

    public static let stoplightInkDark = Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF3 / 255)
    public static let stoplightRedDark = Color(red: 0xFF / 255, green: 0x52 / 255, blue: 0x52 / 255)
    public static let stoplightYellowDark = Color(red: 0xFF / 255, green: 0xEB / 255, blue: 0x3B / 255)
    public static let stoplightGreenDark = Color(red: 0x66 / 255, green: 0xBB / 255, blue: 0x6A / 255)

    public static let stoplightInkLight = Color(red: 0x33 / 255, green: 0x33 / 255, blue: 0x33 / 255)
    public static let stoplightRedLight = Color(red: 0xDC / 255, green: 0x14 / 255, blue: 0x3C / 255)
    public static let stoplightYellowLight = Color(red: 0xFF / 255, green: 0xD7 / 255, blue: 0x00 / 255)
    public static let stoplightGreenLight = Color(red: 0x22 / 255, green: 0x8B / 255, blue: 0x22 / 255)
}
#endif
