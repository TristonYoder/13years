// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Combine
import Foundation
import WatchConnectivity

final class WatchSessionBridge: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = WatchSessionBridge()

    static let hostKey = "watchProducerHost"
    static let portKey = "watchProducerPort"
    static let producerNameKey = "watchProducerName"
    static let roleIDsKey = "watchRoleIDs"

    @Published private(set) var producerIP: String?
    @Published private(set) var producerPort: Int = ProducerHTTPPagerClient.defaultPort
    @Published private(set) var isSessionActive = false

    private let session = WCSession.default

    private override init() {
        super.init()
    }

    func activate() {
        AppLog.bridge.info("Watch bridge: activate() called, isSupported=\(WCSession.isSupported() ? "yes" : "no", privacy: .public)")
        guard WCSession.isSupported() else {
            AppLog.bridge.error("Watch bridge: WCSession is not supported on this device")
            return
        }
        session.delegate = self
        session.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        AppLog.bridge.info(
            "Watch bridge: activation=\(activationState.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
        isSessionActive = activationState == .activated
        if isSessionActive {
            apply(dictionary: session.receivedApplicationContext)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        AppLog.bridge.info("Watch bridge: didReceiveApplicationContext keys=\(applicationContext.keys.sorted(), privacy: .public)")
        apply(dictionary: applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        AppLog.bridge.info("Watch bridge: didReceiveUserInfo keys=\(userInfo.keys.sorted(), privacy: .public)")
        apply(dictionary: userInfo)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        AppLog.bridge.info("Watch bridge: reachability changed isReachable=\(session.isReachable ? "yes" : "no", privacy: .public)")
    }

    private func apply(dictionary context: [String: Any]) {
        if let ip = context[Self.hostKey] as? String, !ip.isEmpty {
            producerIP = ip
            AppLog.bridge.info("Watch bridge: adopted producer IP \(ip, privacy: .public)")
        } else {
            AppLog.bridge.info("Watch bridge: no producer IP in context")
        }
        if let rawPort = context[Self.portKey] as? Int, rawPort > 0, rawPort < 65536 {
            producerPort = rawPort
            AppLog.bridge.info("Watch bridge: adopted producer port \(rawPort, privacy: .public)")
        }
    }
}