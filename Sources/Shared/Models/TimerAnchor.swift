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

    public func elapsedMs(atProducerMs producerNowMs: Int) -> Int {
        let advance = isRunning ? producerNowMs - anchorMs : 0
        return max(0, elapsedMs + advance)
    }

    public func elapsedSeconds(atProducerMs producerNowMs: Int) -> Int {
        elapsedMs(atProducerMs: producerNowMs) / 1000
    }

    public func remainingSeconds(atProducerMs producerNowMs: Int) -> Int {
        lengthInSeconds - elapsedSeconds(atProducerMs: producerNowMs)
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
