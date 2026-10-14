// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(iOS) || os(macOS)
import Foundation
import Combine

@MainActor
public final class RemoteLANCoordinator: ObservableObject {
    public static let shared = RemoteLANCoordinator()

    @Published public var mode: RemoteLANMode {
        didSet {
            guard mode != oldValue else { return }
            RemoteLANMode.store(mode)
            refresh()
        }
    }
    @Published public private(set) var statusText: String?
    @Published public private(set) var isError = false

    private let relay: LANRelayService
    private var session: RemoteProducerSession?
    private var bindings = Set<AnyCancellable>()
    private var startedKey: String?

    public init(relay: LANRelayService = LANRelayService()) {
        self.relay = relay
        self.mode = RemoteLANMode.stored()
        relay.onStatusChanged = { [weak self] in
            MainActor.assumeIsolated { self?.updateStatus() }
        }
    }

    public func attach(_ session: RemoteProducerSession?) {
        bindings.removeAll()
        self.session = session
        startedKey = nil
        if let session {
            session.$state
                .map { $0?.network.lanPort }
                .removeDuplicates()
                .sink { [weak self] _ in self?.refresh() }
                .store(in: &bindings)
            session.$connection
                .removeDuplicates()
                .sink { [weak self] _ in self?.refresh() }
                .store(in: &bindings)
        }
        refresh()
    }

    public func shutdown() {
        attach(nil)
    }

    private func refresh() {
        guard let session, mode != .controlOnly, session.connection != .disconnected, session.connection != .idle else {
            if startedKey != nil || session == nil || mode == .controlOnly {
                relay.stop()
                startedKey = nil
            }
            updateStatus()
            return
        }
        let port = UInt16(clamping: session.state?.network.lanPort ?? Int(LANUnicastServer.port))
        let host = session.endpoint.host
        let key = "\(mode.rawValue)|\(host)|\(port)"
        guard key != startedKey else { return }
        startedKey = key
        relay.start(
            mode: mode,
            upstreamHost: host,
            upstreamPort: port,
            advertisedName: LANUnicastServer.hostDisplayName(),
            deviceId: CueEngine.persistentDeviceId()
        )
        updateStatus()
    }

    private func updateStatus() {
        isError = false
        guard session != nil, mode != .controlOnly else {
            statusText = nil
            return
        }
        switch relay.state {
        case .stopped, .starting:
            statusText = "Starting…"
        case .advertising(let host, let port):
            statusText = "Advertising \(host):\(port)"
        case .relaying:
            let count = relay.relayedConnectionCount
            statusText = count == 1 ? "Relaying 1 pager" : "Relaying \(count) pagers"
        case .portBusy(let message):
            statusText = message
            isError = true
        }
        if case .advertising = relay.state, relay.relayedConnectionCount > 0 {
            statusText = (statusText ?? "") + " · proxying \(relay.relayedConnectionCount)"
        }
    }
}
#endif
