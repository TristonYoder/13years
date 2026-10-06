// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
import Network
#if canImport(UIKit)
import UIKit
#endif

enum LocalNetworkAddress {
    static func ipv4String() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var enNames: [String] = []
        var otherNames: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let ifa = current.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET) {
                let flags = Int32(ifa.ifa_flags)
                let isLoopback = (flags & IFF_LOOPBACK) != 0
                let isUp = (flags & IFF_UP) != 0
                if isUp && !isLoopback {
                    let name = String(cString: ifa.ifa_name)
                    var sa = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                    var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    _ = inet_ntop(AF_INET, &sa.sin_addr, &buf, socklen_t(buf.count))
                    let ip = String(cString: buf)
                    if name.hasPrefix("en") { enNames.append(ip) } else { otherNames.append(ip) }
                }
            }
            cursor = ifa.ifa_next
        }
        return enNames.first ?? otherNames.first
    }
}

public final class LANUnicastServer: @unchecked Sendable {
    public static let port: UInt16 = 13380
    public static let assignPort: UInt16 = 13381

    private static let quickRetryAttempts = 5
    private static let slowRetryInterval: TimeInterval = 10

    public var onPacketReceived: ((CuePacket) -> Void)?
    public var onStatusChanged: ((Bool) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "dev.7co.13years.lanunicast.server", qos: .userInteractive)
    private var isRunning = false
    private var bindAttempt = 0
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    public init() {}

    public var advertisedControlAPIPort: Int?

    public func start() {
        queue.async { [self] in
            guard !isRunning else { return }
            isRunning = true
            bindAttempt = 0
            startListening()
        }
    }

    public func stop() {
        queue.async { [self] in
            isRunning = false
            listener?.cancel()
            listener = nil
            for (_, connection) in connections {
                connection.cancel()
            }
            connections.removeAll()
        }
    }

    public func advertisingTXTDidChange() {
        queue.async { [self] in
            guard isRunning, listener != nil else { return }
            listener?.cancel()
            listener = nil
            startListening()
        }
    }

    public func send(_ packet: CuePacket) {
        queue.async { [self] in
            guard let data = packet.encode(), let framed = LANFraming.frame(data) else { return }
            for (_, connection) in connections {
                connection.send(content: framed, completion: .contentProcessed { error in
                    if let error {
                        AppLog.networking.error("LANUnicastServer send error: \(String(describing: error), privacy: .public)")
                    }
                })
            }
        }
    }

    private func startListening() {
        guard isRunning else { return }
        bindAttempt += 1
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.port)!)
            var txt = NWTXTRecord()
            if let ownIP = LocalNetworkAddress.ipv4String() {
                txt["ip"] = ownIP
                AppLog.networking.info("LANUnicastServer advertising own IPv4 \(ownIP, privacy: .public) in TXT")
            }
            if let apiPort = advertisedControlAPIPort {
                txt["apiport"] = String(apiPort)
            }
            listener.service = NWListener.Service(name: Self.hostDisplayName(), type: "_13years._tcp", txtRecord: txt)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    AppLog.networking.info("LANUnicastServer listening, advertising as \"\(Self.hostDisplayName(), privacy: .public)\"")
                    self?.bindAttempt = 0
                    DispatchQueue.main.async { self?.onStatusChanged?(true) }
                case .failed(let error):
                    AppLog.networking.error("LANUnicastServer listener failed: \(String(describing: error), privacy: .public)")
                    self?.retryAfterFailure()
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.queue.async { self?.accept(connection) }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            AppLog.networking.error("LANUnicastServer: failed to create listener: \(String(describing: error), privacy: .public)")
            retryAfterFailure()
        }
    }

    private func retryAfterFailure() {
        guard isRunning else { return }
        listener = nil
        DispatchQueue.main.async { [weak self] in self?.onStatusChanged?(false) }

        let delay: TimeInterval = bindAttempt < Self.quickRetryAttempts ? 0.3 * Double(bindAttempt) : Self.slowRetryInterval
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startListening()
        }
    }

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.queue.async { self?.connections.removeValue(forKey: key) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveLoop(on: connection, key: key)
    }

    private func receiveLoop(on connection: NWConnection, key: ObjectIdentifier) {
        LANFraming.receiveFrame(on: connection, queue: queue) { [weak self] data in
            guard let self else { return }
            guard let data else {
                self.connections.removeValue(forKey: key)
                return
            }
            if let packet = CuePacket.decode(from: data) {
                DispatchQueue.main.async { self.onPacketReceived?(packet) }
            }
            self.receiveLoop(on: connection, key: key)
        }
    }

    private static func hostDisplayName() -> String {
        #if os(macOS)
        return Host.current().localizedName ?? "13 Years Producer"
        #else
        return UIDevice.current.name
        #endif
    }
}

public final class LANUnicastClient: @unchecked Sendable {
    private static let reconnectInterval: TimeInterval = 3
    private static let assignedHostFailureThreshold = 3
    private static let assignedHostDefaultsKey = "lanUnicastAssignedProducerHost"

    public var onPacketReceived: ((CuePacket) -> Void)?
    public var onStatusChanged: ((Bool) -> Void)?
    public var onMasterDiscovered: ((String) -> Void)?

    public var onConnectedHost: ((String) -> Void)?
    public var onConnectedAPIPort: ((Int) -> Void)?

    private var browser: NWBrowser?
    private var assignListener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "dev.7co.13years.lanunicast.client", qos: .userInteractive)
    private var isRunning = false
    private var lastDiscovered: (endpoint: NWEndpoint, name: String, advertisedIPv4: String?, advertisedAPIPort: Int?)?
    private var isConnectingToAssignedHost = false
    private var assignedHostFailureCount = 0

    public init() {}

    public func start() {
        queue.async { [self] in
            guard !isRunning else { return }
            isRunning = true
            startAssignListener()
            if let assignedHost = Self.loadAssignedHost() {
                connectDirectly(to: assignedHost)
            } else {
                startBrowsing()
            }
        }
    }

    public func stop() {
        queue.async { [self] in
            isRunning = false
            browser?.cancel()
            browser = nil
            assignListener?.cancel()
            assignListener = nil
            connection?.cancel()
            connection = nil
            lastDiscovered = nil
        }
    }

    public func forgetAssignedHost() {
        queue.async { [self] in
            Self.clearAssignedHost()
            isConnectingToAssignedHost = false
            assignedHostFailureCount = 0
            guard isRunning else { return }
            connection?.cancel()
            connection = nil
            lastDiscovered = nil
            if browser == nil { startBrowsing() }
        }
    }

    public func send(_ packet: CuePacket) {
        queue.async { [self] in
            guard let connection, let data = packet.encode(), let framed = LANFraming.frame(data) else { return }
            connection.send(content: framed, completion: .contentProcessed { error in
                if let error {
                    AppLog.networking.error("LANUnicastClient send error: \(String(describing: error), privacy: .public)")
                }
            })
        }
    }

    private func connectDirectly(to host: String) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: LANUnicastServer.port)!)
        lastDiscovered = (endpoint, host, nil, nil)
        connect(to: endpoint, masterName: host, advertisedIPv4: nil, advertisedAPIPort: nil, isAssigned: true)
    }

    private func startAssignListener() {
        do {
            let parameters = NWParameters.udp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: LANUnicastServer.assignPort)!)
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                connection.start(queue: self.queue)
                connection.receiveMessage { [weak self] data, _, _, _ in
                    if let data { self?.handleAssignPing(data) }
                    connection.cancel()
                }
            }
            listener.start(queue: queue)
            self.assignListener = listener
        } catch {
            AppLog.networking.error("LANUnicastClient: failed to start assign listener: \(String(describing: error), privacy: .public)")
        }
    }

    private func handleAssignPing(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "ASSIGN_PRODUCER",
              let host = json["host"] as? String, !host.isEmpty else { return }
        AppLog.networking.info("LANUnicastClient: producer assigned via network ping: \(host, privacy: .public)")
        Self.saveAssignedHost(host)
        queue.async { [self] in
            guard isRunning else { return }
            browser?.cancel()
            browser = nil
            assignedHostFailureCount = 0
            connection?.cancel()
            connection = nil
            connectDirectly(to: host)
        }
    }

    private static func loadAssignedHost() -> String? {
        UserDefaults.standard.string(forKey: assignedHostDefaultsKey)
    }

    private static func ipString(from endpoint: NWEndpoint?) -> String? {
        guard case let .hostPort(host, _)? = endpoint else { return nil }
        switch host {
        case .ipv4(let address): return address.debugDescription
        case .ipv6(let address): return address.debugDescription
        case .name: return nil
        @unknown default: return nil
        }
    }

    private static func saveAssignedHost(_ host: String) {
        UserDefaults.standard.set(host, forKey: assignedHostDefaultsKey)
    }

    private static func clearAssignedHost() {
        UserDefaults.standard.removeObject(forKey: assignedHostDefaultsKey)
    }

    private func startBrowsing() {
        let browser = NWBrowser(for: .bonjour(type: "_13years._tcp", domain: "local."), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, let first = results.first else { return }
            guard case let .service(name, _, _, _) = first.endpoint else { return }
            let advertisedIPv4: String? = {
                if case .bonjour(let txt) = first.metadata {
                    let ip = txt["ip"]
                    return ip.flatMap { $0.isEmpty ? nil : $0 }
                }
                return nil
            }()
            let advertisedAPIPort: Int? = {
                if case .bonjour(let txt) = first.metadata {
                    return txt["apiport"].flatMap { Int($0) }
                }
                return nil
            }()
            self.queue.async {
                self.lastDiscovered = (first.endpoint, name, advertisedIPv4, advertisedAPIPort)
                self.connect(to: first.endpoint, masterName: name, advertisedIPv4: advertisedIPv4, advertisedAPIPort: advertisedAPIPort, isAssigned: false)
            }
        }
        browser.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                AppLog.networking.error("LANUnicastClient browser failed: \(String(describing: error), privacy: .public)")
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    private func connect(to endpoint: NWEndpoint, masterName: String, advertisedIPv4: String?, advertisedAPIPort: Int?, isAssigned: Bool) {
        guard connection == nil else { return }
        isConnectingToAssignedHost = isAssigned
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                AppLog.networking.info("LANUnicastClient connected to \"\(masterName, privacy: .public)\"")
                self.assignedHostFailureCount = 0
                var resolvedHost = Self.ipString(from: connection.currentPath?.remoteEndpoint)
                if let pathHost = resolvedHost, pathHost.contains(":"), let advertised = advertisedIPv4 {
                    AppLog.networking.info("LANUnicastClient using TXT-advertised IPv4 \(advertised, privacy: .public) (path resolved \(pathHost, privacy: .public))")
                    resolvedHost = advertised
                }
                DispatchQueue.main.async {
                    self.onStatusChanged?(true)
                    self.onMasterDiscovered?(masterName)
                    if let resolvedHost {
                        AppLog.networking.info("LANUnicastClient resolved producer address \(resolvedHost, privacy: .public)")
                        self.onConnectedHost?(resolvedHost)
                        if let advertisedAPIPort {
                            self.onConnectedAPIPort?(advertisedAPIPort)
                        }
                    }
                }
                self.queue.async { self.receiveLoop(on: connection) }
            case .failed(let error):
                AppLog.networking.error("LANUnicastClient connection failed: \(String(describing: error), privacy: .public)")
                self.handleDisconnect(connection)
            case .cancelled:
                self.handleDisconnect(connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
        self.connection = connection
    }

    private func handleDisconnect(_ connection: NWConnection) {
        queue.async { [self] in
            guard self.connection === connection else { return }
            self.connection = nil
            DispatchQueue.main.async { [weak self] in self?.onStatusChanged?(false) }
            guard isRunning else { return }

            if isConnectingToAssignedHost {
                assignedHostFailureCount += 1
                if assignedHostFailureCount >= Self.assignedHostFailureThreshold {
                    AppLog.networking.error("LANUnicastClient: assigned host unreachable after \(Self.assignedHostFailureThreshold, privacy: .public) attempts — falling back to Bonjour discovery")
                    isConnectingToAssignedHost = false
                    assignedHostFailureCount = 0
                    lastDiscovered = nil
                    if browser == nil { startBrowsing() }
                    return
                }
            }

            guard let lastDiscovered else { return }
            queue.asyncAfter(deadline: .now() + Self.reconnectInterval) { [weak self] in
                guard let self, self.isRunning, self.connection == nil else { return }
                self.connect(to: lastDiscovered.endpoint, masterName: lastDiscovered.name, advertisedIPv4: lastDiscovered.advertisedIPv4, advertisedAPIPort: lastDiscovered.advertisedAPIPort, isAssigned: self.isConnectingToAssignedHost)
            }
        }
    }

    private func receiveLoop(on connection: NWConnection) {
        LANFraming.receiveFrame(on: connection, queue: queue) { [weak self] data in
            guard let self else { return }
            guard let data else { return }
            if let packet = CuePacket.decode(from: data) {
                DispatchQueue.main.async { self.onPacketReceived?(packet) }
            }
            self.receiveLoop(on: connection)
        }
    }
}
