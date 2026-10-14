// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
import Combine

@MainActor
public final class ControlAPIEventHub {
    private static let coalesceInterval: TimeInterval = 0.1
    static let digestInterval: TimeInterval = 10

    private unowned let engine: CueEngine
    private unowned let server: ControlAPIServer
    private let router: ControlAPIRouter

    private var cancellable: AnyCancellable?
    private var isFlushScheduled = false
    private var announcedMessageIds: Set<String> = []
    private var lastFingerprint: Int?
    private var lastAnchor: TimerAnchor?
    var hasClients: (() -> Bool)?
    var outbound: ((String, ControlAPIServer.BroadcastAudience) -> Void)?
    private var digestTimer: Timer?

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
        digestTimer = Timer.scheduledTimer(withTimeInterval: Self.digestInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sendDigest() }
        }
    }

    func sendDigest() {
        if let hasClients, !hasClients() { return }
        send(event: "digest", data: router.digest(), to: .v2)
    }

    public func stop() {
        digestTimer?.invalidate()
        digestTimer = nil
        lastAnchor = nil
        cancellable = nil
        isFlushScheduled = false
        announcedMessageIds = []
        lastFingerprint = nil
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

    func flush() {
        let unannounced = engine.recentMessages.filter { !announcedMessageIds.contains($0.id) }
        if !unannounced.isEmpty {
            announcedMessageIds.formUnion(unannounced.map(\.id))
            for message in unannounced.reversed() {
                send(event: "message", data: message)
            }
        }
        announcedMessageIds.formIntersection(engine.recentMessages.map(\.id))

        if let hasClients, !hasClients() {
            lastFingerprint = nil
            lastAnchor = nil
            return
        }

        let anchor = engine.currentAnchor
        let anchorChanged = anchor != lastAnchor
        lastAnchor = anchor
        let fingerprint = router.nonTimerFingerprint()
        let timerOnly = lastFingerprint == fingerprint
        lastFingerprint = fingerprint
        if timerOnly {
            let timerState = router.timerSnapshot()
            send(event: "timer", data: timerState, to: .legacy)
            if anchorChanged {
                send(event: "timer", data: timerState, to: .v2)
            }
        } else {
            send(event: "state", data: router.snapshot())
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

    private func send<T: Encodable>(event: String, data: T, to audience: ControlAPIServer.BroadcastAudience = .all) {
        if let hasClients, !hasClients() { return }
        guard let payload = try? ControlAPIJSON.encoder.encode(ControlAPIEvent(event: event, data: data)),
              let text = String(data: payload, encoding: .utf8) else { return }
        if let outbound { outbound(text, audience) }
        server.broadcast(text, to: audience)
    }
}
