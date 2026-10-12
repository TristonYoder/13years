// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
import Network

public final class ControlAPIServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = 13390

    private static let quickRetryAttempts = 5
    private static let maxInFlightBroadcasts = 8
    private static let slowRetryInterval: TimeInterval = 10

    public var onStatusChanged: ((Bool) -> Void)?
    public var onClientCountChanged: ((Int) -> Void)?

    private let router: ControlAPIRouter
    private let queue = DispatchQueue(label: "dev.7co.13years.controlapi", qos: .userInitiated)
    private var listener: NWListener?
    private var isRunning = false
    private var bindAttempt = 0
    private var port: UInt16 = ControlAPIServer.defaultPort
    private var clients: [ObjectIdentifier: Client] = [:]
    private var admission = ConnectionAdmission()
    private var sweepTimer: DispatchSourceTimer?

    public init(router: ControlAPIRouter) {
        self.router = router
    }

    public func start(port: UInt16) {
        queue.async { [self] in
            if isRunning && self.port == port { return }
            if isRunning { stopLocked() }
            self.port = port
            isRunning = true
            bindAttempt = 0
            startListening()
        }
    }

    public func stop() {
        queue.async { [self] in
            guard isRunning else { return }
            stopLocked()
        }
    }

    private func stopLocked() {
        isRunning = false
        listener?.cancel()
        listener = nil
        for (_, client) in clients {
            client.connection.cancel()
        }
        clients.removeAll()
        admission = ConnectionAdmission()
        sweepTimer?.cancel()
        sweepTimer = nil
        notifyClientCount()
        DispatchQueue.main.async { [weak self] in self?.onStatusChanged?(false) }
    }

    private func startListening() {
        guard isRunning else { return }
        bindAttempt += 1
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                AppLog.networking.error("ControlAPIServer: invalid port \(self.port, privacy: .public)")
                return
            }
            let listener = try NWListener(using: parameters, on: nwPort)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    AppLog.networking.info("ControlAPIServer listening on :\(self.port, privacy: .public)")
                    self.bindAttempt = 0
                    DispatchQueue.main.async { self.onStatusChanged?(true) }
                case .failed(let error):
                    AppLog.networking.error("ControlAPIServer listener failed: \(String(describing: error), privacy: .private)")
                    self.retryAfterFailure()
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
            AppLog.networking.error("ControlAPIServer: failed to create listener: \(String(describing: error), privacy: .private)")
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

    private final class Client: @unchecked Sendable {
        let connection: NWConnection
        var buffer: [UInt8] = []
        var isWebSocket = false
        let session = ControlAPIConnection()
        var inFlightBroadcasts = 0
        let assembler = WebSocketMessageAssembler()
        let remoteIP: String
        var deadlines = ConnectionDeadlines(acceptedAt: Date())

        init(connection: NWConnection, remoteIP: String) {
            self.connection = connection
            self.remoteIP = remoteIP
        }
    }

    static func remoteIP(of endpoint: NWEndpoint) -> String {
        guard case let .hostPort(host, _) = endpoint else { return "unknown" }
        let text: String
        switch host {
        case .ipv4(let address): text = address.debugDescription
        case .ipv6(let address): text = address.debugDescription
        case .name(let name, _): text = name
        @unknown default: text = "unknown"
        }
        return text.split(separator: "%", maxSplits: 1).first.map(String.init) ?? text
    }

    private func startSweeping() {
        guard sweepTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.sweep(now: Date()) }
        timer.resume()
        sweepTimer = timer
    }

    private func sweep(now: Date) {
        for (key, client) in clients {
            if client.deadlines.httpExpired(now: now) || client.deadlines.unupgradedExpired(now: now) {
                AppLog.networking.notice("ControlAPIServer: closing connection that missed its deadline")
                client.connection.cancel()
                removeClient(key)
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        let remoteIP = Self.remoteIP(of: connection.endpoint)
        guard isRunning, admission.admit(ip: remoteIP) else {
            AppLog.networking.notice("ControlAPIServer: refusing connection, client limit reached")
            connection.cancel()
            return
        }
        clients[key] = Client(connection: connection, remoteIP: remoteIP)
        startSweeping()
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.queue.async { self?.removeClient(key) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveLoop(key: key)
    }

    private func removeClient(_ key: ObjectIdentifier) {
        guard let removed = clients.removeValue(forKey: key) else { return }
        admission.release(ip: removed.remoteIP)
        notifyClientCount()
    }

    private func notifyClientCount() {
        let count = clients.values.filter(\.isWebSocket).count
        DispatchQueue.main.async { [weak self] in self?.onClientCountChanged?(count) }
    }

    public var connectedClientCount: Int {
        queue.sync { clients.values.filter(\.isWebSocket).count }
    }

    private func receiveLoop(key: ObjectIdentifier) {
        guard let client = clients[key] else { return }
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                guard let client = self.clients[key] else { return }
                if let data, !data.isEmpty {
                    let now = Date()
                    client.deadlines.lastReceivedAt = now
                    if !client.isWebSocket, client.deadlines.requestStartedAt == nil {
                        client.deadlines.requestStartedAt = now
                    }
                    client.buffer.append(contentsOf: data)
                    self.drain(client, key: key)
                }
                if isComplete || error != nil {
                    client.connection.cancel()
                    self.removeClient(key)
                    return
                }
                self.receiveLoop(key: key)
            }
        }
    }

    private func drain(_ client: Client, key: ObjectIdentifier) {
        while true {
            if client.isWebSocket {
                switch WebSocketCodec.decode(client.buffer) {
                case .incomplete:
                    return
                case .failure(let reason):
                    AppLog.networking.error("ControlAPIServer: bad WebSocket frame — \(reason, privacy: .private)")
                    send(WebSocketCodec.close(code: 1002, reason: "Protocol error"), to: client)
                    client.connection.cancel()
                    removeClient(key)
                    return
                case .frame(let frame, let consumed):
                    client.buffer.removeFirst(consumed)
                    if !handle(frame, client: client, key: key) { return }
                }
            } else {
                switch HTTPMessageParser.parse(client.buffer) {
                case .incomplete:
                    return
                case .failure(let reason):
                    AppLog.networking.error("ControlAPIServer: bad HTTP request — \(reason, privacy: .private)")
                    write(ControlAPIRouter.error(400, "Malformed HTTP request", detail: reason), to: client, close: true)
                    removeClient(key)
                    return
                case .request(let request, let consumed):
                    client.buffer.removeFirst(consumed)
                    client.deadlines.requestStartedAt = client.buffer.isEmpty ? nil : Date()
                    handle(request, client: client, key: key)
                    if client.isWebSocket { continue }
                }
            }
        }
    }

    private func handle(_ request: HTTPRequest, client: Client, key: ObjectIdentifier) {
        guard authorize(request) else {
            write(ControlAPIRouter.error(401, "Unauthorized"), to: client, close: true)
            removeClient(key)
            return
        }

        let upgrading = isWebSocketUpgrade(request)
        if upgrading {
            guard ControlAPIGuard.isAllowedWebSocketUpgrade(request) else {
                write(ControlAPIRouter.error(403, "WebSocket origin or host not allowed"), to: client, close: true)
                removeClient(key)
                return
            }
        } else if case .reject(let status, let message) = ControlAPIGuard.evaluate(request) {
            let close = status == 403
            write(ControlAPIRouter.error(status, message), to: client, close: close)
            if close { removeClient(key) }
            return
        }

        if request.method == "OPTIONS" {
            write(HTTPResponse.empty(status: 204), to: client, close: false)
            return
        }

        if upgrading {
            guard request.path == "/v1/socket" else {
                write(ControlAPIRouter.error(404, "WebSocket lives at /v1/socket"), to: client, close: true)
                removeClient(key)
                return
            }
            guard let clientKey = request.header("sec-websocket-key") else {
                write(ControlAPIRouter.error(400, "Missing Sec-WebSocket-Key"), to: client, close: true)
                removeClient(key)
                return
            }
            completeHandshake(clientKey: clientKey, client: client)
            return
        }

        let router = self.router
        let receivedAtMs = Self.nowMs()
        Task { @MainActor in
            let response = router.handle(request, receivedAtMs: receivedAtMs)
            self.queue.async { self.write(response, to: client, close: false) }
        }
    }

    private func authorize(_ request: HTTPRequest) -> Bool {
        true
    }

    private func isWebSocketUpgrade(_ request: HTTPRequest) -> Bool {
        guard let upgrade = request.header("upgrade")?.lowercased() else { return false }
        return upgrade.contains("websocket")
    }

    private func write(_ response: HTTPResponse, to client: Client, close: Bool) {
        var response = response
        if close {
            response.headers["connection"] = "close"
        }
        let data = response.serialize()
        client.connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                AppLog.networking.error("ControlAPIServer send error: \(String(describing: error), privacy: .private)")
            }
            if close {
                self?.queue.async { client.connection.cancel() }
            }
        })
    }

    private func completeHandshake(clientKey: String, client: Client) {
        let accept = WebSocketCodec.acceptKey(forClientKey: clientKey)
        let handshake = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(accept)\r
        \r

        """
        client.isWebSocket = true
        client.deadlines.isUpgraded = true
        client.deadlines.requestStartedAt = nil
        client.connection.send(content: Data(handshake.utf8), completion: .contentProcessed { error in
            if let error {
                AppLog.networking.error("ControlAPIServer handshake send error: \(String(describing: error), privacy: .private)")
            }
        })
        notifyClientCount()
        AppLog.networking.info("ControlAPIServer: WebSocket client connected")

        let router = self.router
        Task { @MainActor in
            let state = router.snapshot()
            guard let payload = try? ControlAPIJSON.encoder.encode(ControlAPIEvent(event: "hello", data: state)),
                  let text = String(data: payload, encoding: .utf8) else { return }
            self.queue.async { self.send(WebSocketCodec.text(text), to: client) }
        }
    }

    private func handle(_ frame: WebSocketFrame, client: Client, key: ObjectIdentifier) -> Bool {
        switch client.assembler.accept(frame) {
        case .none:
            return true

        case .failure(let reason):
            AppLog.networking.error("ControlAPIServer: WebSocket message error — \(reason, privacy: .private)")
            send(WebSocketCodec.close(code: 1002, reason: "Protocol error"), to: client)
            client.connection.cancel()
            removeClient(key)
            return false

        case .control(let control):
            switch control.opcode {
            case .ping:
                send(WebSocketFrame(opcode: .pong, payload: control.payload), to: client)
            case .close:
                send(WebSocketCodec.close(code: 1000), to: client)
                client.connection.cancel()
                removeClient(key)
                return false
            default:
                break
            }
            return true

        case .message(let message):
            guard let command = try? ControlAPIJSON.decoder.decode(ControlAPICommand.self, from: message.payload) else {
                let reply = ControlAPICommandReply(id: nil, status: 400, error: "Malformed command envelope")
                sendJSON(reply, to: client)
                return true
            }
            let router = self.router
            let session = client.session
            let receivedAtMs = Self.nowMs()
            Task { @MainActor in
                let reply = router.handleCommand(command, connection: session, receivedAtMs: receivedAtMs)
                self.queue.async { self.sendJSON(reply, to: client) }
            }
            return true
        }
    }

    private func send(_ frame: WebSocketFrame, to client: Client) {
        client.connection.send(content: WebSocketCodec.encode(frame), completion: .contentProcessed { error in
            if let error {
                AppLog.networking.error("ControlAPIServer frame send error: \(String(describing: error), privacy: .private)")
            }
        })
    }

    private func sendJSON<T: Encodable>(_ value: T, to client: Client) {
        guard let data = try? ControlAPIJSON.encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else { return }
        send(WebSocketCodec.text(text), to: client)
    }

    private static func nowMs() -> Int {
        Int((Date().timeIntervalSince1970 * 1000).rounded())
    }

    public enum BroadcastAudience: Sendable {
        case all
        case legacy
        case v2
    }

    public func broadcast(_ text: String, to audience: BroadcastAudience = .all) {
        queue.async { [self] in
            guard !clients.isEmpty else { return }
            let frame = WebSocketCodec.encode(WebSocketCodec.text(text))
            for (_, client) in clients where client.isWebSocket {
                switch audience {
                case .all: break
                case .legacy: if client.session.isV2 { continue }
                case .v2: if !client.session.isV2 { continue }
                }
                guard client.inFlightBroadcasts < Self.maxInFlightBroadcasts else { continue }
                client.inFlightBroadcasts += 1
                client.connection.send(content: frame, completion: .contentProcessed { error in
                    client.inFlightBroadcasts -= 1
                    if let error {
                        AppLog.networking.error("ControlAPIServer broadcast error: \(String(describing: error), privacy: .private)")
                    }
                })
            }
        }
    }

    public static func localAddresses() -> [String] {
        DirectPeerChannel.localIPv4Addresses()
    }
}
