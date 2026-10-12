// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct RemoteStateTracker {
    public private(set) var state: ControlAPIState?
    public private(set) var lastRev = -1
    public private(set) var epoch: Int?

    public init() {}

    public mutating func reset() {
        state = nil
        lastRev = -1
        epoch = nil
    }

    @discardableResult
    public mutating func noteEpoch(_ value: Int?) -> Bool {
        guard let value else { return false }
        defer { epoch = value }
        guard let epoch, epoch != value else { return false }
        lastRev = -1
        return true
    }

    @discardableResult
    public mutating func hello(_ snapshot: ControlAPIState) -> Bool {
        state = snapshot
        lastRev = snapshot.rev
        epoch = snapshot.epoch
        return true
    }

    @discardableResult
    public mutating func accept(_ snapshot: ControlAPIState) -> Bool {
        guard snapshot.rev > lastRev else { return false }
        state = snapshot
        lastRev = snapshot.rev
        return true
    }

    @discardableResult
    public mutating func merge(timer update: ControlAPITimerState) -> Bool {
        guard var current = state, update.rev > lastRev else { return false }
        current.timer = update.timer
        current.rev = update.rev
        current.serverNowMs = update.serverNowMs
        state = current
        lastRev = update.rev
        return true
    }
}
