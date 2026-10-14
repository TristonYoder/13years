// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public final class MainLoopTimer {
    #if os(Linux)
    private var source: DispatchSourceTimer?
    #else
    private var timer: Timer?
    #endif

    private init() {}

    @discardableResult
    public static func repeating(every interval: TimeInterval, _ block: @escaping @MainActor () -> Void) -> MainLoopTimer {
        make(interval: interval, repeats: true, block)
    }

    public static func once(after interval: TimeInterval, _ block: @escaping @MainActor () -> Void) -> MainLoopTimer {
        make(interval: interval, repeats: false, block)
    }

    private static func make(interval: TimeInterval, repeats: Bool, _ block: @escaping @MainActor () -> Void) -> MainLoopTimer {
        let result = MainLoopTimer()
        #if os(Linux)
        let source = DispatchSource.makeTimerSource(queue: .main)
        if repeats {
            source.schedule(deadline: .now() + interval, repeating: interval)
        } else {
            source.schedule(deadline: .now() + interval)
        }
        source.setEventHandler {
            MainActor.assumeIsolated(block)
        }
        source.resume()
        result.source = source
        #else
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in
            MainActor.assumeIsolated(block)
        }
        RunLoop.main.add(timer, forMode: .common)
        result.timer = timer
        #endif
        return result
    }

    public func invalidate() {
        #if os(Linux)
        source?.cancel()
        source = nil
        #else
        timer?.invalidate()
        timer = nil
        #endif
    }

    deinit {
        #if os(Linux)
        source?.cancel()
        #else
        timer?.invalidate()
        #endif
    }
}
