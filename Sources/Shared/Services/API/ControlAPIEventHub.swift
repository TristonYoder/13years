// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
import Combine

@MainActor
public final class ControlAPIEventHub {
    private static let coalesceInterval: TimeInterval = 0.1

    private unowned let engine: CueEngine
    private unowned let server: ControlAPIServer
    private let router: ControlAPIRouter

    private var cancellable: AnyCancellable?
    private var isFlushScheduled = false
    private var announcedMessageIds: Set<String> = []
    private var lastStableState: NSDictionary?

    public init(engine: CueEngine, server: ControlAPIServer, router: ControlAPIRouter) {
        self.engine = engine
        self.server = server
        self.router = router
    }

    public func start() {
        guard cancellable == nil else { return }
        announcedMessageIds = Set(engine.recentMessages.map(\.id))
        cancellable = engine.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.scheduleFlush() }
        }
        flush()
    }

    public func stop() {
        cancellable = nil
        isFlushScheduled = false
        announcedMessageIds = []
        lastStableState = nil
    }

    private func scheduleFlush() {
        guard !isFlushScheduled else { return }
        isFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coalesceInterval) { [weak self] in
            guard let self else { return }
            self.isFlushScheduled = false
            self.flush()
        }
    }

    private func flush() {
        let unannounced = engine.recentMessages.filter { !announcedMessageIds.contains($0.id) }
        if !unannounced.isEmpty {
            announcedMessageIds.formUnion(unannounced.map(\.id))
            for message in unannounced.reversed() {
                send(event: "message", data: message)
            }
        }
        announcedMessageIds.formIntersection(engine.recentMessages.map(\.id))

        let state = router.snapshot()
        let stable = Self.stableRepresentation(of: state)
        let timerOnly = Self.isTimerOnlyChange(previous: lastStableState, current: stable)
        lastStableState = stable
        if timerOnly {
            send(event: "timer", data: ControlAPITimerState(rev: state.rev, serverNowMs: state.serverNowMs, timer: state.timer))
        } else {
            send(event: "state", data: state)
        }
    }

    nonisolated static func stableRepresentation(of state: ControlAPIState) -> NSDictionary? {
        guard let data = try? ControlAPIJSON.encoder.encode(state),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var stripped = object
        for key in ["timer", "rev", "serverNowMs"] { stripped.removeValue(forKey: key) }
        return stripped as NSDictionary
    }

    nonisolated static func isTimerOnlyChange(previous: NSDictionary?, current: NSDictionary?) -> Bool {
        guard let previous, let current else { return false }
        return previous.isEqual(current)
    }

    private func send<T: Encodable>(event: String, data: T) {
        guard let payload = try? ControlAPIJSON.encoder.encode(ControlAPIEvent(event: event, data: data)),
              let text = String(data: payload, encoding: .utf8) else { return }
        server.broadcast(text)
    }
}
