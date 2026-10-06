// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Combine
import Foundation
import Network

final class WatchProducerBrowser: ObservableObject {
    @Published public private(set) var discoveredHost: String?
    @Published public private(set) var discoveredPort: Int?
    @Published public private(set) var discoveredMasterName: String?

    private let queue = DispatchQueue(label: "WatchProducerBrowser")
    private var browser: NWBrowser?
    private var resolver: NWConnection?
    private var hasReported = false

    private static let serviceType = "_13years._tcp"

    public func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: "local."),
            using: .tcp
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, let first = results.first else { return }
            guard case let .service(name, _, _, _) = first.endpoint else { return }
            var advertisedIPv4: String?
            var advertisedAPIPort: Int?
            if case .bonjour(let txt) = first.metadata {
                if let ip = txt["ip"], !ip.isEmpty {
                    advertisedIPv4 = ip
                }
                if let apiport = txt["apiport"] {
                    advertisedAPIPort = Int(apiport)
                }
            }
            self.queue.async {
                self.consume(
                    endpoint: first.endpoint,
                    name: name,
                    advertisedIPv4: advertisedIPv4,
                    advertisedAPIPort: advertisedAPIPort
                )
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                AppLog.networking.error(
                    "WatchProducerBrowser browse failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    private func consume(endpoint: NWEndpoint, name: String, advertisedIPv4: String?, advertisedAPIPort: Int?) {
        guard !hasReported else { return }
        if let ip = advertisedIPv4, ip.contains(".") {
            report(host: ip, name: name, port: advertisedAPIPort)
            return
        }
        resolve(endpoint: endpoint, name: name)
    }

    private func resolve(endpoint: NWEndpoint, name: String) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                let ip = WatchProducerBrowser.ipv4(from: connection.currentPath?.remoteEndpoint)
                connection.cancel()
                if let ip {
                    self.queue.async { self.report(host: ip, name: name, port: nil) }
                }
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
        resolver = connection
    }

    private func report(host: String, name: String, port: Int?) {
        guard !hasReported else { return }
        hasReported = true
        browser?.cancel()
        browser = nil
        resolver?.cancel()
        resolver = nil
        AppLog.networking.info(
            "WatchProducerBrowser discovered producer \(name, privacy: .public) at \(host, privacy: .public) port \(port.map(String.init) ?? "default", privacy: .public)"
        )
        DispatchQueue.main.async {
            self.discoveredHost = host
            self.discoveredPort = port
            self.discoveredMasterName = name
            self.objectWillChange.send()
        }
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        resolver?.cancel()
        resolver = nil
    }

    private static func ipv4(from endpoint: NWEndpoint?) -> String? {
        guard case let .hostPort(host, _)? = endpoint else { return nil }
        switch host {
        case .ipv4(let address): return address.debugDescription
        case .ipv6(let address):
            let s = address.debugDescription
            return s.lowercased().hasPrefix("::ffff:")
                ? String(s.dropFirst("::ffff:".count))
                : nil
        case .name: return nil
        @unknown default: return nil
        }
    }
}