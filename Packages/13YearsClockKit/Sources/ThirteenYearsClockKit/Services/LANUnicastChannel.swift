// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
#if canImport(Network)
import Network
#if canImport(UIKit)
import UIKit
#endif

public final class LANUnicastServer: @unchecked Sendable {
    public static let port: UInt16 = 13380
    public static let assignPort: UInt16 = 13381

    private static let quickRetryAttempts = 5
    private static let slowRetryInterval: TimeInterval = 10

    public var onPacketReceived: ((CuePacket, LANConnectionID) -> Void)?
    public var onStatusChanged: ((Bool) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "dev.7co.13years.lanunicast.server", qos: .userInteractive)
    private var isRunning = false
    private var bindAttempt = 0
    private var connections: [UInt64: NWConnection] = [:]
    private var v2Connections: Set<UInt64> = []
    private var nextConnectionID: UInt64 = 0
    private var deadlines: [UInt64: ConnectionDeadlines] = [:]
    private var remoteIPs: [UInt64: String] = [:]
    private var admission = ConnectionAdmission()
    private var sweepTimer: DispatchSourceTimer?

    public init() {}

    public var advertisedControlAPIPort: Int?
    public var advertisedDeviceId: String?

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
            v2Connections.removeAll()
            deadlines.removeAll()
            remoteIPs.removeAll()
            admission = ConnectionAdmission()
            sweepTimer?.cancel()
            sweepTimer = nil
        }
    }

    public func markProtocolV2(_ id: LANConnectionID) {
        queue.async { [self] in
            guard connections[id.raw] != nil else { return }
            v2Connections.insert(id.raw)
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

    public func send(_ packet: CuePacket, to audience: LANAudience = .all) {
        queue.async { [self] in
            let targets: [NWConnection]
            switch audience {
            case .all:
                targets = Array(connections.values)
            case .legacy:
                targets = connections.filter { !v2Connections.contains($0.key) }.map(\.value)
            case .v2:
                targets = connections.filter { v2Connections.contains($0.key) }.map(\.value)
            case .connection(let id):
                targets = connections[id.raw].map { [$0] } ?? []
            }
            guard !targets.isEmpty, let data = packet.encode(), let framed = LANFraming.frame(data) else { return }
            for connection in targets {
                connection.send(content: framed, completion: .contentProcessed { error in
                    if let error {
                        AppLog.networking.error("LANUnicastServer send error: \(String(describing: error), privacy: .private)")
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
                AppLog.networking.info("LANUnicastServer advertising own IPv4 \(ownIP, privacy: .private) in TXT")
            }
            if let apiPort = advertisedControlAPIPort {
                txt["apiport"] = String(apiPort)
            }
            if let advertisedDeviceId {
                txt["did"] = advertisedDeviceId
            }
            listener.service = NWListener.Service(name: Self.hostDisplayName(), type: "_13years._tcp", txtRecord: txt)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    AppLog.networking.info("LANUnicastServer listening, advertising as \"\(Self.hostDisplayName(), privacy: .private)\"")
                    self?.bindAttempt = 0
                    DispatchQueue.main.async { self?.onStatusChanged?(true) }
                case .failed(let error):
                    AppLog.networking.error("LANUnicastServer listener failed: \(String(describing: error), privacy: .private)")
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
            AppLog.networking.error("LANUnicastServer: failed to create listener: \(String(describing: error), privacy: .private)")
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

    private func forget(_ key: UInt64) {
        connections.removeValue(forKey: key)
        v2Connections.remove(key)
        deadlines.removeValue(forKey: key)
        if let ip = remoteIPs.removeValue(forKey: key) {
            admission.release(ip: ip)
        }
    }

    private func startSweeping() {
        guard sweepTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in self?.sweep(now: Date()) }
        timer.resume()
        sweepTimer = timer
    }

    private func sweep(now: Date) {
        for (key, window) in deadlines where window.lanExpired(now: now) {
            AppLog.networking.notice("LANUnicastServer: closing idle connection")
            connections[key]?.cancel()
            forget(key)
        }
    }

    private func accept(_ connection: NWConnection) {
        nextConnectionID += 1
        let key = nextConnectionID
        let remoteIP = ControlAPIServer.remoteIP(of: connection.endpoint)
        guard isRunning, admission.admit(ip: remoteIP) else {
            AppLog.networking.notice("LANUnicastServer: refusing connection, client limit reached")
            connection.cancel()
            return
        }
        connections[key] = connection
        remoteIPs[key] = remoteIP
        deadlines[key] = ConnectionDeadlines(acceptedAt: Date())
        startSweeping()
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.queue.async { self?.forget(key) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveLoop(on: connection, key: key)
    }

    private func receiveLoop(on connection: NWConnection, key: UInt64) {
        LANFraming.receiveFrame(on: connection, queue: queue) { [weak self] data in
            guard let self else { return }
            guard let data else {
                self.forget(key)
                connection.cancel()
                return
            }
            self.deadlines[key]?.lastReceivedAt = Date()
            self.deadlines[key]?.hasReceivedFrame = true
            if let packet = CuePacket.decode(from: data) {
                let id = LANConnectionID(raw: key)
                DispatchQueue.main.async { self.onPacketReceived?(packet, id) }
            }
            self.receiveLoop(on: connection, key: key)
        }
    }

    public static func hostDisplayName() -> String {
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
    private static let manualHostDefaultsKey = "lanUnicastManualProducerHost"

    public var onPacketReceived: ((CuePacket) -> Void)?
    public var onStatusChanged: ((Bool) -> Void)?
    public var onMasterDiscovered: ((String) -> Void)?

    public var onConnectedHost: ((String) -> Void)?
    public var onConnectedAPIPort: ((Int) -> Void)?
    public var onLinkStatusChanged: ((ProducerLinkStatus) -> Void)?

    private var browser: NWBrowser?
    private var assignListener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "dev.7co.13years.lanunicast.client", qos: .userInteractive)
    private var isRunning = false
    private var lastDiscovered: (endpoint: NWEndpoint, name: String, advertisedIPv4: String?, advertisedAPIPort: Int?)?
    private var isConnectingToAssignedHost = false
    private var assignedHostFailureCount = 0
    private var manualHost: String?
    private var linkStatus: ProducerLinkStatus = .idle

    public init() {}

    public static func savedManualHost() -> String? {
        UserDefaults.standard.string(forKey: manualHostDefaultsKey).flatMap { ManualHostPolicy.validate($0).endpoint }
    }

    public func setManualHost(_ host: String?) {
        queue.async { [self] in
            if let host {
                UserDefaults.standard.set(host, forKey: Self.manualHostDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.manualHostDefaultsKey)
            }
            manualHost = host
            assignedHostFailureCount = 0
            guard isRunning else { return }
            browser?.cancel()
            browser = nil
            let old = connection
            connection = nil
            old?.cancel()
            lastDiscovered = nil
            publish(.idle)
            if let host {
                connectDirectly(to: host)
            } else if let assigned = Self.loadAssignedHost() {
                connectDirectly(to: assigned)
            } else {
                startBrowsing()
            }
        }
    }

    private func publish(_ status: ProducerLinkStatus) {
        guard status != linkStatus else { return }
        linkStatus = status
        DispatchQueue.main.async { [weak self] in self?.onLinkStatusChanged?(status) }
    }

    private static func isLocalNetworkDenied(_ error: NWError) -> Bool {
        switch error {
        case .dns(let code): return code == -65570
        case .posix(let code): return code == .ENETDOWN || code == .EPERM
        default: return false
        }
    }

    public func start() {
        queue.async { [self] in
            guard !isRunning else { return }
            isRunning = true
            manualHost = Self.savedManualHost()
            startAssignListener()
            if let manualHost {
                connectDirectly(to: manualHost)
            } else if let assignedHost = Self.loadAssignedHost() {
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
            publish(.idle)
        }
    }

    public func forgetAssignedHost() {
        queue.async { [self] in
            Self.clearAssignedHost()
            guard manualHost == nil else { return }
            isConnectingToAssignedHost = false
            assignedHostFailureCount = 0
            guard isRunning else { return }
            connection?.cancel()
            connection = nil
            lastDiscovered = nil
            if browser == nil { startBrowsing() }
        }
    }

    public func reconnectNow(force: Bool = true) {
        queue.async { [self] in
            guard isRunning else { return }
            if !force, connection?.state == .ready { return }
            let old = connection
            connection = nil
            old?.cancel()
            if old != nil {
                DispatchQueue.main.async { [weak self] in self?.onStatusChanged?(false) }
            }
            if let manualHost {
                connectDirectly(to: manualHost)
            } else if let assigned = Self.loadAssignedHost() {
                connectDirectly(to: assigned)
            } else {
                browser?.cancel()
                browser = nil
                lastDiscovered = nil
                startBrowsing()
            }
        }
    }

    public func send(_ packet: CuePacket) {
        queue.async { [self] in
            guard let connection, let data = packet.encode(), let framed = LANFraming.frame(data) else { return }
            connection.send(content: framed, completion: .contentProcessed { error in
                if let error {
                    AppLog.networking.error("LANUnicastClient send error: \(String(describing: error), privacy: .private)")
                }
            })
        }
    }

    private func connectDirectly(to target: String) {
        let parsed = ManualHostPolicy.validate(target)
        let host = parsed.host ?? target
        let port = NWEndpoint.Port(rawValue: parsed.port ?? LANUnicastServer.port) ?? NWEndpoint.Port(rawValue: LANUnicastServer.port)!
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: port)
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
                let senderIP = ControlAPIServer.remoteIP(of: connection.endpoint)
                connection.receiveMessage { [weak self] data, _, _, _ in
                    if let data { self?.handleAssignPing(data, senderIP: senderIP) }
                    connection.cancel()
                }
            }
            listener.start(queue: queue)
            self.assignListener = listener
        } catch {
            AppLog.networking.error("LANUnicastClient: failed to start assign listener: \(String(describing: error), privacy: .private)")
        }
    }

    private func handleAssignPing(_ data: Data, senderIP: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "ASSIGN_PRODUCER",
              let host = json["host"] as? String, !host.isEmpty else { return }
        guard host == senderIP else {
            AppLog.networking.error("LANUnicastClient: rejected ASSIGN_PRODUCER whose host does not match the sender")
            return
        }
        guard AssignedHostPolicy.isAcceptable(host) else {
            AppLog.networking.error("LANUnicastClient: rejected ASSIGN_PRODUCER with a non-local host \(host, privacy: .private)")
            return
        }
        queue.async { [self] in
            guard manualHost == nil else {
                AppLog.networking.info("LANUnicastClient: ignoring ASSIGN_PRODUCER because a manual host is set")
                return
            }
            AppLog.networking.info("LANUnicastClient: producer assigned via network ping: \(host, privacy: .private)")
            Self.saveAssignedHost(host)
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
        UserDefaults.standard.string(forKey: assignedHostDefaultsKey).flatMap { AssignedHostPolicy.isAcceptable($0) ? $0 : nil }
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
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_13years._tcp", domain: "local."), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, let first = results.first else { return }
            guard case let .service(name, _, _, _) = first.endpoint else { return }
            var txtDictionary: [String: String] = [:]
            if case .bonjour(let txt) = first.metadata { txtDictionary = txt.dictionary }
            let target = LANDiscoveryRouting.target(serviceEndpoint: first.endpoint, txt: txtDictionary)
            let advertisedAPIPort = txtDictionary["apiport"].flatMap { Int($0) }
            self.queue.async {
                guard !self.isConnectingToAssignedHost, self.manualHost == nil else { return }
                let previous = self.lastDiscovered?.endpoint
                self.lastDiscovered = (target.endpoint, name, target.advertisedIPv4, advertisedAPIPort)
                if let current = self.connection, let previous, previous != target.endpoint {
                    AppLog.networking.info("LANUnicastClient: discovery target changed, reconnecting")
                    self.connection = nil
                    current.cancel()
                    DispatchQueue.main.async { [weak self] in self?.onStatusChanged?(false) }
                }
                self.connect(to: target.endpoint, masterName: name, advertisedIPv4: target.advertisedIPv4, advertisedAPIPort: advertisedAPIPort, isAssigned: false)
            }
        }
        browser.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                AppLog.networking.error("LANUnicastClient browser failed: \(String(describing: error), privacy: .private)")
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    private func connect(to endpoint: NWEndpoint, masterName: String, advertisedIPv4: String?, advertisedAPIPort: Int?, isAssigned: Bool) {
        guard connection == nil else { return }
        isConnectingToAssignedHost = isAssigned
        if !linkStatus.isProblem { publish(.connecting(host: masterName)) }
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                AppLog.networking.info("LANUnicastClient connected to \"\(masterName, privacy: .private)\"")
                self.assignedHostFailureCount = 0
                self.queue.async { self.publish(.connected) }
                var resolvedHost = Self.ipString(from: connection.currentPath?.remoteEndpoint)
                if let pathHost = resolvedHost, pathHost.contains(":"), let advertised = advertisedIPv4 {
                    AppLog.networking.info("LANUnicastClient using TXT-advertised IPv4 \(advertised, privacy: .private) (path resolved \(pathHost, privacy: .private))")
                    resolvedHost = advertised
                }
                DispatchQueue.main.async {
                    self.onStatusChanged?(true)
                    self.onMasterDiscovered?(masterName)
                    if let resolvedHost {
                        AppLog.networking.info("LANUnicastClient resolved producer address \(resolvedHost, privacy: .private)")
                        self.onConnectedHost?(resolvedHost)
                        if let advertisedAPIPort {
                            self.onConnectedAPIPort?(advertisedAPIPort)
                        }
                    }
                }
                self.queue.async { self.receiveLoop(on: connection) }
            case .failed(let error):
                AppLog.networking.error("LANUnicastClient connection failed: \(String(describing: error), privacy: .private)")
                self.queue.async {
                    guard self.connection === connection else { return }
                    self.publish(Self.isLocalNetworkDenied(error) ? .localNetworkDenied : .unreachable(host: masterName))
                }
                self.handleDisconnect(connection)
            case .waiting(let error):
                AppLog.networking.error("LANUnicastClient connection waiting: \(String(describing: error), privacy: .private)")
                self.queue.async {
                    guard self.connection === connection else { return }
                    self.publish(Self.isLocalNetworkDenied(error) ? .localNetworkDenied : .unreachable(host: masterName))
                    connection.cancel()
                }
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

            if isConnectingToAssignedHost, manualHost == nil {
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
            if !isConnectingToAssignedHost, manualHost == nil {
                browser?.cancel()
                browser = nil
                startBrowsing()
            }
            queue.asyncAfter(deadline: .now() + Self.reconnectInterval) { [weak self] in
                guard let self, self.isRunning, self.connection == nil else { return }
                let lastDiscovered = self.lastDiscovered ?? lastDiscovered
                self.connect(to: lastDiscovered.endpoint, masterName: lastDiscovered.name, advertisedIPv4: lastDiscovered.advertisedIPv4, advertisedAPIPort: lastDiscovered.advertisedAPIPort, isAssigned: self.isConnectingToAssignedHost)
            }
        }
    }

    private func receiveLoop(on connection: NWConnection) {
        LANFraming.receiveFrame(on: connection, queue: queue) { [weak self] data in
            guard let self else { return }
            guard let data else {
                connection.cancel()
                self.handleDisconnect(connection)
                return
            }
            if let packet = CuePacket.decode(from: data) {
                DispatchQueue.main.async { self.onPacketReceived?(packet) }
            }
            self.receiveLoop(on: connection)
        }
    }
}
#endif
