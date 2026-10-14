// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
#if canImport(Network)
import Network

public final class LANRelayService: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case stopped
        case starting
        case advertising(host: String, port: UInt16)
        case relaying
        case portBusy(String)
    }

    private static let quickRetryAttempts = 5
    private static let slowRetryInterval: TimeInterval = 10

    public private(set) var relayedConnectionCount = 0
    public private(set) var state: State = .stopped
    public private(set) var boundPort: UInt16?
    public var onStatusChanged: (() -> Void)?

    private let listenPort: UInt16
    private let advertise: Bool
    private let queue = DispatchQueue(label: "dev.7co.13years.lanrelay", qos: .userInteractive)
    private var listener: NWListener?
    private var generation = 0
    private var bindAttempt = 0
    private var mode: RemoteLANMode = .controlOnly
    private var upstreamHost = ""
    private var upstreamPort: UInt16 = LANUnicastServer.port
    private var advertisedName = ""
    private var deviceId = ""
    private var resolvedHostIP: String?
    private var pairs: [UInt64: (NWConnection, NWConnection)] = [:]
    private var nextPairID: UInt64 = 0

    public init(listenPort: UInt16 = LANUnicastServer.port, advertise: Bool = true) {
        self.listenPort = listenPort
        self.advertise = advertise
    }

    public func start(mode: RemoteLANMode, upstreamHost: String, upstreamPort: UInt16, advertisedName: String, deviceId: String) {
        queue.async { [self] in
            teardown()
            guard mode != .controlOnly else {
                publish(state: .stopped)
                return
            }
            generation += 1
            self.mode = mode
            self.upstreamHost = upstreamHost
            self.upstreamPort = upstreamPort
            self.advertisedName = advertisedName
            self.deviceId = deviceId
            self.resolvedHostIP = Self.resolveIPv4(upstreamHost)
            bindAttempt = 0
            publish(state: .starting)
            startListening(generation: generation)
        }
    }

    public func stop() {
        queue.async { [self] in
            generation += 1
            teardown()
            publish(state: .stopped)
        }
    }

    private func teardown() {
        listener?.cancel()
        listener = nil
        let open = pairs.values
        pairs.removeAll()
        for (client, upstream) in open {
            client.cancel()
            upstream.cancel()
        }
        boundPort = nil
    }

    private func publish(state newState: State? = nil) {
        let count = pairs.count
        let port = boundPort
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let newState { self.state = newState }
            self.relayedConnectionCount = count
            self.boundPort = port
            self.onStatusChanged?()
        }
    }

    private func startListening(generation: Int) {
        guard generation == self.generation else { return }
        bindAttempt += 1
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener: NWListener
            if listenPort == 0 {
                listener = try NWListener(using: parameters)
            } else {
                listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: listenPort)!)
            }
            if advertise {
                var txt = NWTXTRecord()
                if let ownIP = LocalNetworkAddress.ipv4String() { txt["ip"] = ownIP }
                if !deviceId.isEmpty { txt["did"] = deviceId }
                switch mode {
                case .introducer:
                    txt["mode"] = "introducer"
                    txt["host"] = upstreamHost
                    txt["port"] = String(upstreamPort)
                    if let resolvedHostIP { txt["hostip"] = resolvedHostIP }
                case .localRelay:
                    txt["mode"] = "relay"
                case .controlOnly:
                    break
                }
                listener.service = NWListener.Service(name: advertisedName, type: "_13years._tcp", txtRecord: txt)
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                self.queue.async {
                    guard generation == self.generation else { return }
                    switch state {
                    case .ready:
                        self.bindAttempt = 0
                        self.boundPort = listener.port?.rawValue
                        if self.mode == .introducer {
                            self.publish(state: .advertising(host: self.upstreamHost, port: self.upstreamPort))
                        } else {
                            self.publish(state: .relaying)
                        }
                    case .failed(let error):
                        AppLog.networking.error("LANRelayService listener failed: \(String(describing: error), privacy: .private)")
                        self.retryAfterFailure(generation: generation, error: error)
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.queue.async {
                    guard let self else { return }
                    if self.mode == .introducer {
                        connection.cancel()
                        return
                    }
                    self.accept(connection, generation: generation)
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            retryAfterFailure(generation: generation, error: error)
        }
    }

    private func retryAfterFailure(generation: Int, error: Error) {
        guard generation == self.generation else { return }
        listener?.cancel()
        listener = nil
        publish(state: .portBusy("Port \(listenPort) is busy (\(error.localizedDescription)). Retrying…"))
        let delay: TimeInterval = bindAttempt < Self.quickRetryAttempts ? 0.3 * Double(bindAttempt) : Self.slowRetryInterval
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startListening(generation: generation)
        }
    }

    private func accept(_ client: NWConnection, generation: Int) {
        guard generation == self.generation, let port = NWEndpoint.Port(rawValue: upstreamPort) else {
            client.cancel()
            return
        }
        nextPairID += 1
        let id = nextPairID
        let upstream = NWConnection(host: NWEndpoint.Host(upstreamHost), port: port, using: .tcp)
        pairs[id] = (client, upstream)
        publish()
        var finished = false
        let finish: () -> Void = { [weak self] in
            self?.queue.async {
                guard let self, !finished else { return }
                finished = true
                client.cancel()
                upstream.cancel()
                if self.pairs.removeValue(forKey: id) != nil { self.publish() }
            }
        }
        client.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled: finish()
            default: break
            }
        }
        upstream.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.queue.async {
                    guard !finished else { return }
                    Self.pump(from: client, to: upstream, done: finish)
                    Self.pump(from: upstream, to: client, done: finish)
                }
            case .failed, .cancelled, .waiting:
                finish()
            default:
                break
            }
        }
        client.start(queue: queue)
        upstream.start(queue: queue)
    }

    private static func pump(from source: NWConnection, to sink: NWConnection, done: @escaping () -> Void) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                sink.send(content: data, completion: .contentProcessed { sendError in
                    if sendError != nil {
                        done()
                        return
                    }
                    if isComplete || error != nil {
                        done()
                    } else {
                        pump(from: source, to: sink, done: done)
                    }
                })
            } else if isComplete || error != nil {
                done()
            } else {
                pump(from: source, to: sink, done: done)
            }
        }
    }

    private static func resolveIPv4(_ host: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return nil }
        defer { freeaddrinfo(result) }
        guard let addr = first.pointee.ai_addr else { return nil }
        var sa = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        _ = inet_ntop(AF_INET, &sa.sin_addr, &buf, socklen_t(buf.count))
        return String(cString: buf)
    }
}

public enum LANDiscoveryRouting {
    public struct Target: Equatable {
        public var endpoint: NWEndpoint
        public var advertisedIPv4: String?
        public var isIntroduced: Bool
    }

    public static func advertisesMode(txt: [String: String]) -> Bool {
        txt["mode"] == "relay" || txt["mode"] == "introducer"
    }

    public static func target(serviceEndpoint: NWEndpoint, txt: [String: String]) -> Target {
        let ownIP = txt["ip"].flatMap { $0.isEmpty ? nil : $0 }
        if txt["mode"] != "relay",
           let host = txt["host"], !host.isEmpty,
           let portText = txt["port"], let portValue = UInt16(portText), let port = NWEndpoint.Port(rawValue: portValue), portValue != 0 {
            let hostIP = txt["hostip"].flatMap { AssignedHostPolicy.ipv4Octets($0) == nil ? nil : $0 }
            return Target(endpoint: .hostPort(host: NWEndpoint.Host(hostIP ?? host), port: port), advertisedIPv4: hostIP, isIntroduced: true)
        }
        return Target(endpoint: serviceEndpoint, advertisedIPv4: ownIP, isIntroduced: false)
    }
}
#endif
