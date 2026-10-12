// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(iOS) || os(macOS)
import Foundation
import Network

public struct DiscoveredProducer: Identifiable, Equatable, Sendable {
    public var serviceName: String
    public var endpoint: RemoteEndpoint
    public var apiReachable: Bool?
    public var deviceName: String?

    public var id: String { "\(endpoint.host):\(endpoint.port)" }
    public var displayName: String { deviceName ?? serviceName }

    public static func make(serviceName: String, txt: [String: String], ownAddresses: Set<String>) -> DiscoveredProducer? {
        guard let ip = txt["ip"]?.trimmingCharacters(in: .whitespaces), !ip.isEmpty else { return nil }
        guard !ownAddresses.contains(ip) else { return nil }
        let port = txt["apiport"].flatMap { Int($0) }.flatMap { (1...65535).contains($0) ? $0 : nil } ?? RemoteEndpoint.defaultPort
        return DiscoveredProducer(
            serviceName: serviceName,
            endpoint: RemoteEndpoint(host: ip, port: port, name: serviceName),
            apiReachable: nil,
            deviceName: nil
        )
    }
}

@MainActor
public final class ProducerDiscovery: ObservableObject {
    @Published public private(set) var producers: [DiscoveredProducer] = []
    @Published public private(set) var browseError: String?

    private var browser: NWBrowser?
    private var probeTask: Task<Void, Never>?
    private var found: [String: DiscoveredProducer] = [:]
    private let http: RemoteProducerHTTP
    private let ownAddresses: () -> Set<String>

    public init(
        http: RemoteProducerHTTP = URLSessionRemoteHTTP(),
        ownAddresses: (() -> Set<String>)? = nil
    ) {
        self.http = http
        self.ownAddresses = ownAddresses ?? { Set(DirectPeerChannel.localIPv4Addresses()) }
    }

    public func start() {
        guard browser == nil else { return }
        browseError = nil
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_13years._tcp", domain: "local."), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            var mapped: [(serviceName: String, txt: [String: String])] = []
            for result in results {
                guard case let .service(name, _, _, _) = result.endpoint else { continue }
                var txt: [String: String] = [:]
                if case .bonjour(let record) = result.metadata {
                    for key in ["ip", "apiport"] {
                        if let value = record[key] { txt[key] = value }
                    }
                }
                mapped.append((serviceName: name, txt: txt))
            }
            Task { @MainActor in self?.update(with: mapped) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                Task { @MainActor in self?.browseError = error.localizedDescription }
            }
        }
        browser.start(queue: .main)
        self.browser = browser

        probeTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.probeAll()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        probeTask?.cancel()
        probeTask = nil
    }

    func update(with results: [(serviceName: String, txt: [String: String])]) {
        let own = ownAddresses()
        var next: [String: DiscoveredProducer] = [:]
        for result in results {
            guard var producer = DiscoveredProducer.make(serviceName: result.serviceName, txt: result.txt, ownAddresses: own) else { continue }
            if let existing = found[producer.id] {
                producer.apiReachable = existing.apiReachable
                producer.deviceName = existing.deviceName
            }
            next[producer.id] = producer
        }
        found = next
        publish()
        Task { await probeAll() }
    }

    private func probeAll() async {
        for producer in Array(found.values) {
            let health = try? await RemoteProducerSession.fetchHealth(of: producer.endpoint, using: http)
            guard var current = found[producer.id] else { continue }
            current.apiReachable = health != nil
            if let device = health?.device { current.deviceName = device }
            found[producer.id] = current
        }
        publish()
    }

    private func publish() {
        let sorted = found.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        if sorted != producers { producers = sorted }
    }
}
#endif
