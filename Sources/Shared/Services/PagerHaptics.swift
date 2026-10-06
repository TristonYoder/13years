// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
#if os(iOS)
import UIKit
import CoreHaptics
import AudioToolbox
#elseif os(watchOS)
import WatchKit
#endif

public final class PagerHaptics {
    public static let shared = PagerHaptics()

    public static let strengthDefaultsKey = "pagerHapticStrength"
    public static let defaultStrength: Double = 1.0

    public static var isSupported: Bool {
        #if os(iOS) || os(watchOS)
        return true
        #else
        return false
        #endif
    }

    #if os(iOS)
    private var engine: CHHapticEngine?
    #endif

    private init() {}

    public var strength: Double {
        get {
            let stored = UserDefaults.standard.object(forKey: Self.strengthDefaultsKey) as? Double
            return min(max(stored ?? Self.defaultStrength, 0), 1)
        }
        set {
            UserDefaults.standard.set(min(max(newValue, 0), 1), forKey: Self.strengthDefaultsKey)
        }
    }

    private var intensity: Float {
        Float(0.5 + 0.5 * strength)
    }

    public func prepareIfNeeded() {
        #if os(iOS)
        guard engine == nil, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let newEngine = try CHHapticEngine()
            newEngine.isAutoShutdownEnabled = false
            newEngine.resetHandler = { [weak newEngine] in try? newEngine?.start() }
            newEngine.stoppedHandler = { [weak newEngine] _ in try? newEngine?.start() }
            try newEngine.start()
            engine = newEngine
        } catch {
            engine = nil
        }
        #elseif os(watchOS)
        #endif
    }

    public func playCueTransition(for state: CueState) {
        #if os(iOS)
        guard state != .off else { return }
        if state.isGo {
            playPulses(count: 6, pulseDuration: 0.5, gap: 0.1)
        } else {
            playLongBuzz(duration: 2.0)
        }
        #elseif os(watchOS)
        guard state != .off else { return }
        let device = WKInterfaceDevice.current()
        if state.isGo {
            device.play(.start)
            playWatchClicks(count: 5, interval: 0.22)
        } else {
            device.play(.notification)
        }
        #endif
    }

    public func playMessageReceived(for state: CueState) {
        #if os(iOS)
        guard let engine, CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            fallbackVibrate(for: state)
            return
        }
        try? engine.start()
        do {
            let events: [CHHapticEvent]
            if state.isGo {
                events = (0..<5).map { i in
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                        ],
                        relativeTime: Double(i) * 0.15
                    )
                }
            } else {
                events = (0..<3).map { i in
                    CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15)
                        ],
                        relativeTime: Double(i) * 0.65,
                        duration: 0.45
                    )
                }
            }
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallbackVibrate(for: state)
        }
        #elseif os(watchOS)
        if state.isGo {
            playWatchClicks(count: 4, interval: 0.18)
        } else {
            playWatchClicks(count: 2, interval: 0.25)
        }
        #endif
    }

    public func playTest() {
        #if os(iOS)
        playPulses(count: 3, pulseDuration: 0.3, gap: 0.1)
        #elseif os(watchOS)
        playWatchClicks(count: 3, interval: 0.2)
        #endif
    }

    #if os(iOS)
    private func playLongBuzz(duration: TimeInterval) {
        guard let engine, CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            return
        }
        try? engine.start()
        do {
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15)
                ],
                relativeTime: 0,
                duration: duration
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    private func playPulses(count: Int, pulseDuration: TimeInterval, gap: TimeInterval) {
        let step = pulseDuration + gap
        guard let engine, CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            for i in 0..<count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * step) {
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                }
            }
            return
        }
        try? engine.start()
        do {
            let events = (0..<count).map { i in
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15)
                    ],
                    relativeTime: Double(i) * step,
                    duration: pulseDuration
                )
            }
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            for i in 0..<count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * step) {
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                }
            }
        }
    }

    private func fallbackVibrate(for state: CueState) {
        if state.isGo {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            for i in 0..<5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) {
                    generator.impactOccurred()
                }
            }
        } else {
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.6) {
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                }
            }
        }
    }
    #endif

    #if os(watchOS)
    private func playWatchClicks(count: Int, interval: TimeInterval) {
        WKInterfaceDevice.current().play(.click)
        for index in 1..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * interval) {
                WKInterfaceDevice.current().play(.click)
            }
        }
    }
    #endif
}
