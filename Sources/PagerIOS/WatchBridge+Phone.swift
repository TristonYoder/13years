// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Combine
import Foundation
import WatchConnectivity

@MainActor
enum WatchProducerBridge {
    static let hostKey = "watchProducerHost"
    static let portKey = "watchProducerPort"
    static let producerNameKey = "watchProducerName"
    static let isProducerLiveKey = "watchProducerIsLive"
    static let roleIDsKey = "watchRoleIDs"

    private static let delegate = BridgeDelegate()
    private static var cancellable: AnyCancellable?
    private static var isAttached = false
    fileprivate static weak var engine: CueEngine?
    private static var lastSentSnapshot: [String: Any]?

    static func attach(to engine: CueEngine) {
        guard WCSession.isSupported(), !isAttached else { return }
        isAttached = true
        self.engine = engine
        AppLog.bridge.info("Phone bridge: WCSession supported, attaching")
        let session = WCSession.default
        session.delegate = delegate
        session.activate()
        push(from: engine)
        cancellable = engine.objectWillChange.sink { [weak engine] in
            guard let engine else { return }
            push(from: engine)
        }
    }

    fileprivate static func push(from engine: CueEngine) {
        let activationState = WCSession.default.activationState
        guard activationState == .activated else {
            AppLog.bridge.info("Phone bridge: push skipped (activationState=\(activationState.rawValue, privacy: .public))")
            return
        }
        var context: [String: Any] = [:]
        context[producerNameKey] = engine.connectedMasterName
        context[isProducerLiveKey] = engine.isProducerLive
        context[roleIDsKey] = engine.roles.map(\.id)
        if let host = engine.connectedProducerHost, !host.isEmpty {
            let normalized = Self.normalizeWatchHost(host)
            if let normalized {
                context[hostKey] = normalized
                context[portKey] = engine.connectedProducerAPIPort ?? Int(ControlAPIServer.defaultPort)
                AppLog.bridge.info("Phone bridge: pushing host \(normalized, privacy: .public) (raw \(host, privacy: .public)) port \(context[portKey].map { String(describing: $0) } ?? "?", privacy: .public)")
            } else {
                AppLog.bridge.info("Phone bridge: ignoring host \(host, privacy: .public) (not a numeric IP)")
            }
        }
        if let previous = lastSentSnapshot, (previous as NSDictionary).isEqual(to: context) {
            return
        }
        lastSentSnapshot = context
        WCSession.default.transferUserInfo(context)
    }

    private static func normalizeWatchHost(_ host: String) -> String? {
        let withoutScope = host.split(separator: "%").first.map(String.init) ?? host
        let trimmed = withoutScope.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("::ffff:") {
            let v4 = String(trimmed.dropFirst("::ffff:".count))
            if v4.split(separator: ".").count == 4 { return v4 }
            return nil
        }
        guard !trimmed.contains(":") else { return nil }
        return trimmed.isEmpty ? nil : trimmed
    }
}

private final class BridgeDelegate: NSObject, WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        AppLog.bridge.info(
            "Phone bridge: session activation=\(activationState.rawValue, privacy: .public) isReachable=\(session.isReachable ? "yes" : "no", privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
        if activationState == .activated {
            Task { @MainActor in
                if let engine = WatchProducerBridge.engine {
                    WatchProducerBridge.push(from: engine)
                }
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        AppLog.bridge.info("Phone bridge: session deactivated, reactivating")
        session.activate()
    }
}