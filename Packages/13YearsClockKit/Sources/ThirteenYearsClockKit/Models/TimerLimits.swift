// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum TimerLimits {
    public static let maxSeconds = 604_800
    public static let maxElapsedSeconds = 31_536_000

    public static func clampLength(_ seconds: Int) -> Int {
        min(max(seconds, 0), maxSeconds)
    }

    public static func clampDelta(_ seconds: Int) -> Int {
        min(max(seconds, -maxSeconds), maxSeconds)
    }

    public static func clampElapsed(_ seconds: Int) -> Int {
        min(max(seconds, 0), maxElapsedSeconds)
    }

    public static func isValidLength(_ seconds: Int) -> Bool {
        (0...maxSeconds).contains(seconds)
    }

    public static func isValidDelta(_ seconds: Int) -> Bool {
        (-maxSeconds...maxSeconds).contains(seconds)
    }

    public static func saturatingSubtract(_ lhs: Int, _ rhs: Int) -> Int {
        let (value, overflow) = lhs.subtractingReportingOverflow(rhs)
        if overflow { return lhs < 0 ? -Int.max : Int.max }
        return max(value, -Int.max)
    }

    public static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        if overflow { return lhs < 0 ? -Int.max : Int.max }
        return max(value, -Int.max)
    }

    public static func seconds(fromMinutes minutes: Int) -> Int? {
        let (value, overflow) = minutes.multipliedReportingOverflow(by: 60)
        return overflow ? nil : value
    }

    public static func safeAbs(_ value: Int) -> Int {
        value == Int.min ? Int.max : abs(value)
    }
}
