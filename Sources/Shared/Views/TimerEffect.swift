// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

extension View {
    /// Animates a view to grab attention. `.none` leaves it alone, and so does Reduce Motion.
    func timerEffect(_ effect: TimerEffect) -> some View {
        modifier(TimerEffectModifier(effect: effect))
    }
}

private struct TimerEffectModifier: ViewModifier {
    let effect: TimerEffect
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if effect == .none || reduceMotion {
            content
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                animated(content, at: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    @ViewBuilder
    private func animated(_ content: Content, at t: Double) -> some View {
        switch effect {
        case .none:
            content
        case .pulse:
            // A slow swell between most and fully visible.
            content.opacity(0.62 + 0.38 * (0.5 + 0.5 * sin(t * 2 * .pi / 1.4)))
        case .blink:
            content.opacity(t.truncatingRemainder(dividingBy: 1.0) < 0.6 ? 1 : 0.1)
        case .flicker:
            content.opacity(Self.flickerOpacity(at: t))
        case .glitch:
            glitch(content, at: t)
        }
    }

    /// Mostly steady, with quick irregular dips like a failing bulb.
    private static func flickerOpacity(at t: Double) -> Double {
        let bucket = Int(t * 16)
        let r = hash(bucket)
        if r < 0.62 { return 1 }
        return r < 0.85 ? 0.55 : 0.2
    }

    /// Short bursts every couple of seconds: the text jumps sideways with offset cyan and red ghosts.
    @ViewBuilder
    private func glitch(_ content: Content, at t: Double) -> some View {
        let cycle = t.truncatingRemainder(dividingBy: 2.2)
        if cycle < 0.28 {
            let bucket = Int(t * 24)
            let dx = (Self.hash(bucket) - 0.5) * 10
            let dy = (Self.hash(bucket &+ 97) - 0.5) * 3
            ZStack {
                content.colorMultiply(.cyan).offset(x: dx - 3, y: dy).opacity(0.7)
                content.colorMultiply(.red).offset(x: dx + 3, y: -dy).opacity(0.7)
                content.offset(x: dx * 0.4, y: 0)
            }
        } else {
            content
        }
    }

    private static func hash(_ n: Int) -> Double {
        var x = UInt64(bitPattern: Int64(n)) &* 0x9E3779B97F4A7C15
        x ^= x >> 29
        x = x &* 0xBF58476D1CE4E5B9
        x ^= x >> 32
        return Double(x % 10_000) / 10_000
    }
}

extension TimerEffect {
    var title: String {
        switch self {
        case .none: return "None"
        case .pulse: return "Pulse"
        case .blink: return "Blink"
        case .flicker: return "Flicker"
        case .glitch: return "Glitch"
        }
    }
}
