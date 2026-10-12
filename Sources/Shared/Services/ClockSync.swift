// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct ClockSyncSample: Equatable, Sendable {
    public var t0: Double
    public var t1: Double
    public var t2: Double
    public var t3: Double
    public var monotonicMs: Double?

    public init(t0: Double, t1: Double, t2: Double, t3: Double, monotonicMs: Double? = nil) {
        self.t0 = t0
        self.t1 = t1
        self.t2 = t2
        self.t3 = t3
        self.monotonicMs = monotonicMs
    }

    public var rtt: Double { (t3 - t0) - (t2 - t1) }

    public var effectiveRtt: Double { max(0, rtt) }

    public var offset: Double { ((t1 - t0) + (t2 - t3)) / 2 }
}

public struct ClockOffsetEstimator: Sendable {
    public static let maxSamples = 8
    public static let jumpThresholdMs = 20.0
    public static let slewFraction = 0.25
    public static let maxSampleAgeMs = 90_000.0
    public static let maxRttMs = 10_000.0
    public static let maxOffsetMs = 86_400_000.0
    public static let roundingToleranceMs = 5.0
    public static let divergenceFloorMs = 50.0

    public private(set) var samples: [ClockSyncSample] = []
    public private(set) var offsetMs: Double?

    public init() {}

    public var best: ClockSyncSample? {
        var chosen: ClockSyncSample?
        for sample in samples where chosen == nil || sample.effectiveRtt <= chosen!.effectiveRtt {
            chosen = sample
        }
        return chosen
    }

    @discardableResult
    public mutating func add(_ sample: ClockSyncSample, nowMonotonicMs: Double? = nil) -> Bool {
        guard sample.rtt.isFinite, sample.offset.isFinite,
              sample.rtt >= -Self.roundingToleranceMs,
              sample.rtt <= Self.maxRttMs,
              abs(sample.offset) <= Self.maxOffsetMs else { return false }
        if let nowMonotonicMs { expire(nowMonotonicMs: nowMonotonicMs) }
        if let held = best,
           abs(sample.offset - held.offset) > max(Self.divergenceFloorMs, 2 * sample.effectiveRtt) {
            samples.removeAll()
        }
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

    public mutating func expire(nowMonotonicMs: Double) {
        samples.removeAll { sample in
            guard let stamp = sample.monotonicMs else { return false }
            return nowMonotonicMs - stamp > Self.maxSampleAgeMs
        }
    }

    public mutating func clearSamples() {
        samples = []
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

    public static let maxJump = 1_000_000

    public mutating func accept(_ rev: Int?, strict: Bool = false, allowJump: Bool = true, advance: Bool = true) -> Bool {
        guard let rev else { return true }
        if let highest {
            if rev < highest { return false }
            if strict && rev == highest { return false }
            if !allowJump {
                let (gap, overflow) = rev.subtractingReportingOverflow(highest)
                if overflow || gap > Self.maxJump { return false }
            }
        }
        if advance { highest = rev }
        return true
    }

    public mutating func rebase(to rev: Int?) {
        highest = rev
    }

    public mutating func reset() {
        highest = nil
    }
}
