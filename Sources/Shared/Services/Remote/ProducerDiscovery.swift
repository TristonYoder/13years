// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(iOS) || os(macOS)
import Foundation
import Network

public struct DiscoveredProducer: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case unknown
        case reachable
        case refused
        case unreachable
    }

    public var serviceName: String
    public var endpoint: RemoteEndpoint
    public var status: Status
    public var deviceName: String?
    public var deviceId: String?

    public var apiReachable: Bool? {
        switch status {
        case .unknown: return nil
        case .reachable: return true
        case .refused, .unreachable: return false
        }
    }

    public var id: String { "\(endpoint.host):\(endpoint.port)" }
    public var displayName: String { deviceName ?? serviceName }

    public static func make(
        serviceName: String,
        txt: [String: String],
        ownAddresses: Set<String>,
        resolvedHost: String? = nil,
        ownDeviceId: String? = nil
    ) -> DiscoveredProducer? {
        let advertised = txt["ip"]?.trimmingCharacters(in: .whitespaces)
        let host = [resolvedHost, advertised].compactMap { $0 }.first { !$0.isEmpty }
        guard let host else { return nil }
        guard !ownAddresses.contains(host), !ownAddresses.contains(advertised ?? "") else { return nil }
        let advertisedId = txt["did"]?.trimmingCharacters(in: .whitespaces)
        if let ownDeviceId, let advertisedId, advertisedId == ownDeviceId { return nil }
        let port = txt["apiport"].flatMap { Int($0) }.flatMap { (1...65535).contains($0) ? $0 : nil } ?? RemoteEndpoint.defaultPort
        return DiscoveredProducer(
            serviceName: serviceName,
            endpoint: RemoteEndpoint(host: host, port: port, name: serviceName),
            status: .unknown,
            deviceName: nil,
            deviceId: advertisedId?.isEmpty == false ? advertisedId : nil
        )
    }
}

public enum BrowseIssue: Equatable, Sendable {
    case localNetworkDenied
    case waiting(String)
    case failed(String)

    public var message: String {
        switch self {
        case .localNetworkDenied:
            return "Allow Local Network access in Settings to find Producers on this network."
        case .waiting(let reason):
            return "Can't browse yet (\(reason)). If you were asked about Local Network access, allow it in Settings."
        case .failed(let reason):
            return reason
        }
    }

    public static func from(waiting error: NWError) -> BrowseIssue {
        if case .dns(let code) = error, code == -65570 { return .localNetworkDenied }
        return .waiting(error.localizedDescription)
    }
}

enum ProbeOutcome: Sendable {
    case reachable(RemoteProducerHealth)
    case refused
    case unreachable
}

@MainActor
public final class ProducerDiscovery: ObservableObject {
    @Published public private(set) var producers: [DiscoveredProducer] = []
    @Published public private(set) var browseIssue: BrowseIssue?

    public var browseError: String? { browseIssue?.message }

    private var browser: NWBrowser?
    private var probeTask: Task<Void, Never>?
    private var resolvers: [String: NWConnection] = [:]
    private var resolved: [String: String] = [:]
    private var lastResults: [(serviceName: String, txt: [String: String])] = []
    private var found: [String: DiscoveredProducer] = [:]
    private var selfIds: Set<String> = []
    private var probeNowRequested = false
    private var quietRounds = 0
    private let http: RemoteProducerHTTP
    private let ownAddresses: () -> Set<String>
    private let ownDeviceId: String?

    public static let baseInterval: TimeInterval = 3
    public static let maxInterval: TimeInterval = 15

    public init(
        http: RemoteProducerHTTP = URLSessionRemoteHTTP(),
        ownAddresses: (() -> Set<String>)? = nil,
        ownDeviceId: String? = CueEngine.persistentDeviceId()
    ) {
        self.http = http
        self.ownAddresses = ownAddresses ?? { Set(DirectPeerChannel.localIPv4Addresses()) }
        self.ownDeviceId = ownDeviceId
    }

    public static func nextInterval(afterQuietRounds rounds: Int) -> TimeInterval {
        min(maxInterval, baseInterval * pow(2, Double(max(0, rounds))))
    }

    public func start() {
        guard browser == nil else { return }
        browseIssue = nil
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_13years._tcp", domain: "local."), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            var mapped: [(serviceName: String, txt: [String: String], endpoint: NWEndpoint)] = []
            for result in results {
                guard case let .service(name, _, _, _) = result.endpoint else { continue }
                var txt: [String: String] = [:]
                if case .bonjour(let record) = result.metadata {
                    for key in ["ip", "apiport", "did"] {
                        if let value = record[key] { txt[key] = value }
                    }
                }
                mapped.append((serviceName: name, txt: txt, endpoint: result.endpoint))
            }
            Task { @MainActor in self?.update(with: mapped.map { ($0.serviceName, $0.txt) }, endpoints: Dictionary(mapped.map { ($0.serviceName, $0.endpoint) }, uniquingKeysWith: { first, _ in first })) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .waiting(let error): self?.browseIssue = BrowseIssue.from(waiting: error)
                case .failed(let error): self?.browseIssue = .failed(error.localizedDescription)
                case .ready: self?.browseIssue = nil
                default: break
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
        startProbeLoop()
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        probeTask?.cancel()
        probeTask = nil
        for connection in resolvers.values { connection.cancel() }
        resolvers = [:]
    }

    private func startProbeLoop() {
        guard probeTask == nil else { return }
        probeTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let changed = await self.probeAll()
                self.quietRounds = changed ? 0 : self.quietRounds + 1
                let interval = Self.nextInterval(afterQuietRounds: self.quietRounds)
                let deadline = Date().addingTimeInterval(interval)
                while Date() < deadline, !self.probeNowRequested, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
                self.probeNowRequested = false
            }
        }
    }

    func update(with results: [(serviceName: String, txt: [String: String])], endpoints: [String: NWEndpoint] = [:]) {
        lastResults = results
        for (name, endpoint) in endpoints where resolved[name] == nil && resolvers[name] == nil {
            resolve(name: name, endpoint: endpoint)
        }
        rebuild()
        probeNowRequested = true
    }

    private func rebuild() {
        let own = ownAddresses()
        var next: [String: DiscoveredProducer] = [:]
        for result in lastResults {
            guard var producer = DiscoveredProducer.make(
                serviceName: result.serviceName,
                txt: result.txt,
                ownAddresses: own,
                resolvedHost: resolved[result.serviceName],
                ownDeviceId: ownDeviceId
            ) else { continue }
            guard !selfIds.contains(producer.id) else { continue }
            if let existing = found[producer.id] {
                producer.status = existing.status
                producer.deviceName = existing.deviceName
                producer.deviceId = producer.deviceId ?? existing.deviceId
            }
            next[producer.id] = producer
        }
        found = next
        publish()
    }

    private func resolve(name: String, endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        resolvers[name] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .ready:
                var host: String?
                if case let .hostPort(remote, _)? = connection?.currentPath?.remoteEndpoint {
                    host = Self.hostString(remote)
                }
                connection?.cancel()
                Task { @MainActor in self?.finishResolve(name: name, host: host) }
            case .failed, .cancelled:
                Task { @MainActor in self?.finishResolve(name: name, host: nil) }
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    private func finishResolve(name: String, host: String?) {
        guard resolvers.removeValue(forKey: name) != nil else { return }
        guard let host else { return }
        resolved[name] = host
        rebuild()
        probeNowRequested = true
    }

    nonisolated static func hostString(_ host: NWEndpoint.Host) -> String? {
        switch host {
        case .ipv4(let address):
            return address.debugDescription.split(separator: "%").first.map(String.init)
        case .ipv6(let address):
            return address.debugDescription
        case .name(let name, _):
            return name
        @unknown default:
            return nil
        }
    }

    private func probeAll() async -> Bool {
        let targets = Array(found.values)
        guard !targets.isEmpty else { return false }
        let http = self.http
        let outcomes = await withTaskGroup(of: (String, ProbeOutcome).self) { group in
            for producer in targets {
                group.addTask {
                    do {
                        return (producer.id, .reachable(try await RemoteProducerSession.fetchHealth(of: producer.endpoint, using: http)))
                    } catch RemoteProducerError.refused {
                        return (producer.id, .refused)
                    } catch {
                        return (producer.id, .unreachable)
                    }
                }
            }
            var collected: [String: ProbeOutcome] = [:]
            for await (id, outcome) in group { collected[id] = outcome }
            return collected
        }
        var changed = false
        for (id, outcome) in outcomes {
            guard var current = found[id] else { continue }
            let before = current
            switch outcome {
            case .reachable(let health):
                if let ownDeviceId, health.deviceId == ownDeviceId {
                    selfIds.insert(id)
                    found.removeValue(forKey: id)
                    changed = true
                    continue
                }
                current.status = .reachable
                current.deviceName = health.device
                if let deviceId = health.deviceId { current.deviceId = deviceId }
            case .refused:
                current.status = .refused
            case .unreachable:
                current.status = .unreachable
            }
            if current != before { changed = true }
            found[id] = current
        }
        publish()
        return changed
    }

    private func publish() {
        let sorted = found.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        if sorted != producers { producers = sorted }
    }
}
#endif
