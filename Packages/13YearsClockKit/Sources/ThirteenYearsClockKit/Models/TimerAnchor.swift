// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct TimerAnchor: Codable, Equatable, Sendable {
    public var itemId: String
    public var lengthInSeconds: Int
    public var elapsedMs: Int
    public var anchorMs: Int
    public var isRunning: Bool
    public var isDurationActual: Bool

    public init(
        itemId: String,
        lengthInSeconds: Int,
        elapsedMs: Int,
        anchorMs: Int,
        isRunning: Bool,
        isDurationActual: Bool
    ) {
        self.itemId = itemId
        self.lengthInSeconds = lengthInSeconds
        self.elapsedMs = elapsedMs
        self.anchorMs = anchorMs
        self.isRunning = isRunning
        self.isDurationActual = isDurationActual
    }

    public static let maxLengthInSeconds = 604_800
    public static let maxElapsedMs = 604_800_000
    private static let arithmeticCap = 1 << 50

    public var isWithinBounds: Bool {
        (0...Self.maxLengthInSeconds).contains(lengthInSeconds)
            && (0...Self.maxElapsedMs).contains(elapsedMs)
    }

    public func elapsedMs(atProducerMs producerNowMs: Int) -> Int {
        let cap = Self.arithmeticCap
        guard isRunning else { return max(0, min(elapsedMs, cap)) }
        let (delta, overflow) = producerNowMs.subtractingReportingOverflow(anchorMs)
        let advance = overflow ? (anchorMs < 0 ? cap : -cap) : max(-cap, min(delta, cap))
        return max(0, min(elapsedMs, cap) + advance)
    }

    public func elapsedSeconds(atProducerMs producerNowMs: Int) -> Int {
        elapsedMs(atProducerMs: producerNowMs) / 1000
    }

    public func remainingSeconds(atProducerMs producerNowMs: Int) -> Int {
        lengthInSeconds.saturatingSubtracting(elapsedSeconds(atProducerMs: producerNowMs))
    }

    public func msUntilNextSecond(atProducerMs producerNowMs: Int) -> Int? {
        guard isRunning else { return nil }
        let elapsed = elapsedMs(atProducerMs: producerNowMs)
        return 1000 - (elapsed % 1000)
    }

    public func applying(to item: PCOTimerItem, atProducerMs producerNowMs: Int) -> PCOTimerItem {
        var result = item
        result.lengthInSeconds = lengthInSeconds
        result.elapsedSeconds = elapsedSeconds(atProducerMs: producerNowMs)
        result.isRunning = isRunning
        result.isDurationActual = isDurationActual
        return result
    }
}

extension Int {
    func saturatingSubtracting(_ other: Int) -> Int {
        let (value, overflow) = subtractingReportingOverflow(other)
        return overflow ? (other > 0 ? Int.min : Int.max) : value
    }

    func saturatingAdding(_ other: Int) -> Int {
        let (value, overflow) = addingReportingOverflow(other)
        return overflow ? (other > 0 ? Int.max : Int.min) : value
    }
}
