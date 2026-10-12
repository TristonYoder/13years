// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct ClockSyncSample: Equatable, Sendable {
    public var t0: Double
    public var t1: Double
    public var t2: Double
    public var t3: Double

    public init(t0: Double, t1: Double, t2: Double, t3: Double) {
        self.t0 = t0
        self.t1 = t1
        self.t2 = t2
        self.t3 = t3
    }

    public var rtt: Double { (t3 - t0) - (t2 - t1) }

    public var offset: Double { ((t1 - t0) + (t2 - t3)) / 2 }
}

public struct ClockOffsetEstimator: Sendable {
    public static let maxSamples = 8
    public static let jumpThresholdMs = 20.0
    public static let slewFraction = 0.25

    public private(set) var samples: [ClockSyncSample] = []
    public private(set) var offsetMs: Double?

    public init() {}

    public var best: ClockSyncSample? {
        var chosen: ClockSyncSample?
        for sample in samples where chosen == nil || sample.rtt <= chosen!.rtt {
            chosen = sample
        }
        return chosen
    }

    @discardableResult
    public mutating func add(_ sample: ClockSyncSample) -> Bool {
        guard sample.rtt >= 0 else { return false }
        samples.append(sample)
        if samples.count > Self.maxSamples {
            samples.removeFirst(samples.count - Self.maxSamples)
        }
        guard let target = best?.offset else { return true }
        if let current = offsetMs {
            let delta = target - current
            if abs(delta) < Self.jumpThresholdMs {
                offsetMs = current + delta * Self.slewFraction
            } else {
                offsetMs = target
            }
        } else {
            offsetMs = target
        }
        return true
    }

    public mutating func reset() {
        samples = []
        offsetMs = nil
    }

    public func producerNowMs(localNowMs: Double) -> Double? {
        offsetMs.map { localNowMs + $0 }
    }
}

public struct SyncRevisionGate: Equatable, Sendable {
    public private(set) var highest: Int?

    public init() {}

    public mutating func accept(_ rev: Int?) -> Bool {
        guard let rev else { return true }
        if let highest, rev < highest { return false }
        highest = rev
        return true
    }

    public mutating func rebase(to rev: Int?) {
        highest = rev
    }

    public mutating func reset() {
        highest = nil
    }
}
