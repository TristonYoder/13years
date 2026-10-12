// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(iOS) || os(macOS)
import Foundation
import Combine

@MainActor
public final class RemoteProducerSession: ObservableObject, RemoteProducerCommanding {
    public enum Connection: Equatable {
        case idle
        case connecting
        case connected
        case reconnecting
        case failed(String)
        case disconnected
    }

    public struct Timing: Sendable {
        public var pingInterval: TimeInterval
        public var pongTimeout: TimeInterval
        public var helloTimeout: TimeInterval
        public var retryDelays: [TimeInterval]

        public init(pingInterval: TimeInterval, pongTimeout: TimeInterval, helloTimeout: TimeInterval, retryDelays: [TimeInterval]) {
            self.pingInterval = pingInterval
            self.pongTimeout = pongTimeout
            self.helloTimeout = helloTimeout
            self.retryDelays = retryDelays
        }

        public static let standard = Timing(pingInterval: 5, pongTimeout: 4, helloTimeout: 5, retryDelays: [0.5, 1, 2, 3, 5])
    }

    @Published public private(set) var connection: Connection = .idle
    @Published public private(set) var state: ControlAPIState?
    @Published public private(set) var lastError: String?
    @Published public private(set) var displayName: String

    public let endpoint: RemoteEndpoint
    public let engine: CueEngine

    private let http: RemoteProducerHTTP
    private let socketFactory: RemoteSocketFactory
    private let timing: Timing
    private var tracker = RemoteStateTracker()
    private var socket: RemoteSocket?
    private var socketGeneration = 0
    private var helloGeneration = -1
    private var keepaliveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var commandTail: Task<Void, Never>?
    private var errorClearTask: Task<Void, Never>?
    private var isUserDisconnected = false

    public var isLive: Bool { connection == .connected }

    public init(
        endpoint: RemoteEndpoint,
        http: RemoteProducerHTTP = URLSessionRemoteHTTP(),
        socketFactory: @escaping RemoteSocketFactory = { URLSessionRemoteSocket(url: $0) },
        timing: Timing = .standard
    ) {
        self.endpoint = endpoint
        self.http = http
        self.socketFactory = socketFactory
        self.timing = timing
        self.displayName = endpoint.name
        self.engine = CueEngine(mirroring: nil)
        engine.remoteCommands = self
        engine.remoteProducerName = endpoint.name
    }

    public static func fetchHealth(of endpoint: RemoteEndpoint, using http: RemoteProducerHTTP = URLSessionRemoteHTTP()) async throws -> RemoteProducerHealth {
        guard let url = endpoint.url(path: "/v1/health") else { throw RemoteProducerError.invalidAddress }
        let (status, data): (Int, Data)
        do {
            (status, data) = try await http.perform(method: "GET", url: url, body: nil)
        } catch {
            throw RemoteProducerError.unreachable(endpoint.address)
        }
        guard (200..<300).contains(status),
              let health = try? JSONDecoder().decode(RemoteProducerHealth.self, from: data),
              health.service == RemoteProducerHealth.serviceName else {
            throw RemoteProducerError.notAProducer(endpoint.address)
        }
        return health
    }

    public func connect() async {
        guard connection == .idle || connection == .disconnected || isFailed else { return }
        isUserDisconnected = false
        connection = .connecting
        lastError = nil
        do {
            let health = try await Self.fetchHealth(of: endpoint, using: http)
            if endpoint.name == endpoint.host || endpoint.name.isEmpty { setName(health.device) }
        } catch {
            connection = .failed(error.localizedDescription)
            return
        }
        guard !isUserDisconnected else { return }
        if await openAndAwaitHello() {
            connection = .connected
            startKeepalive()
        } else if !isUserDisconnected {
            connection = .failed(RemoteProducerError.noHello(endpoint.address).localizedDescription)
        }
    }

    public func disconnect() {
        isUserDisconnected = true
        keepaliveTask?.cancel()
        reconnectTask?.cancel()
        commandTail?.cancel()
        errorClearTask?.cancel()
        closeSocket()
        connection = .disconnected
    }

    private var isFailed: Bool {
        if case .failed = connection { return true }
        return false
    }

    private func setName(_ name: String) {
        displayName = name
        engine.remoteProducerName = name
    }

    private func openAndAwaitHello() async -> Bool {
        closeSocket()
        guard let url = endpoint.socketURL else { return false }
        socketGeneration += 1
        let generation = socketGeneration
        let socket = socketFactory(url)
        socket.onText = { [weak self] text in
            guard let self, self.socketGeneration == generation else { return }
            self.handle(text, generation: generation)
        }
        socket.onClose = { [weak self] reason in
            guard let self, self.socketGeneration == generation else { return }
            self.socketClosed(reason)
        }
        self.socket = socket
        socket.open()

        let deadline = Date().addingTimeInterval(timing.helloTimeout)
        while helloGeneration != generation {
            if Task.isCancelled || isUserDisconnected || socketGeneration != generation || Date() >= deadline {
                if socketGeneration == generation { closeSocket() }
                return false
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return true
    }

    private func closeSocket() {
        keepaliveTask?.cancel()
        socket?.close()
        socket = nil
        socketGeneration += 1
    }

    private func handle(_ text: String, generation: Int) {
        guard let data = text.data(using: .utf8),
              let head = try? JSONDecoder().decode(EventHead.self, from: data) else { return }
        let decoder = ControlAPIJSON.decoder
        switch head.event {
        case "hello":
            guard let event = try? decoder.decode(Event<ControlAPIState>.self, from: data) else { return }
            tracker.reset()
            tracker.hello(event.data)
            helloGeneration = generation
            state = tracker.state
            engine.apply(remoteState: event.data)
        case "state":
            guard let event = try? decoder.decode(Event<ControlAPIState>.self, from: data),
                  tracker.accept(event.data) else { return }
            state = tracker.state
            engine.apply(remoteState: event.data)
        case "timer":
            guard let event = try? decoder.decode(Event<ControlAPITimerState>.self, from: data),
                  tracker.merge(timer: event.data) else { return }
            state = tracker.state
            engine.apply(remoteTimer: event.data.timer)
        default:
            break
        }
    }

    private func socketClosed(_ reason: String) {
        guard !isUserDisconnected else { return }
        guard connection == .connected else {
            socketGeneration += 1
            return
        }
        connectionLost()
    }

    private func connectionLost() {
        guard connection == .connected else { return }
        keepaliveTask?.cancel()
        closeSocket()
        connection = .reconnecting
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            var attempt = 0
            while let self, !Task.isCancelled, !self.isUserDisconnected {
                let delays = self.timing.retryDelays
                let delay = delays.isEmpty ? 1 : delays[min(attempt, delays.count - 1)]
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled || self.isUserDisconnected { return }
                if await self.openAndAwaitHello() {
                    self.connection = .connected
                    self.startKeepalive()
                    return
                }
                attempt += 1
            }
        }
    }

    private func startKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.timing.pingInterval * 1_000_000_000))
                guard !Task.isCancelled, let socket = self.socket else { return }
                let alive = await socket.ping(timeout: self.timing.pongTimeout)
                if Task.isCancelled { return }
                if !alive {
                    self.connectionLost()
                    return
                }
            }
        }
    }

    public func send(_ command: RemoteCommand) {
        guard isLive else {
            report("Not connected to \(displayName).")
            return
        }
        let previous = commandTail
        commandTail = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await self?.perform(command)
        }
    }

    private func perform(_ command: RemoteCommand) async {
        guard isLive else {
            report("Not connected to \(displayName).")
            return
        }
        let request = command.request
        guard let url = endpoint.url(path: request.path) else { return }
        do {
            let (status, data) = try await http.perform(method: request.method, url: url, body: request.body)
            if (200..<300).contains(status) {
                if let snapshot = try? ControlAPIJSON.decoder.decode(ControlAPIState.self, from: data), tracker.accept(snapshot) {
                    state = tracker.state
                    engine.apply(remoteState: snapshot)
                }
            } else {
                let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
                report(body?.error ?? "\(displayName) refused the command (\(status)).")
            }
        } catch {
            report("\(displayName) didn't answer in time.")
        }
    }

    private func report(_ message: String) {
        lastError = message
        errorClearTask?.cancel()
        errorClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            self?.lastError = nil
        }
    }

    public func dismissError() {
        lastError = nil
    }

    private struct EventHead: Decodable {
        let event: String
    }

    private struct Event<Payload: Decodable>: Decodable {
        let event: String
        let data: Payload
    }

    private struct ErrorBody: Decodable {
        let error: String
    }
}

public enum RemoteProducerError: LocalizedError, Equatable {
    case invalidAddress
    case unreachable(String)
    case notAProducer(String)
    case noHello(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "That address isn't valid."
        case .unreachable(let address):
            return "Couldn't reach \(address). Check the address, and that the Control API is switched on in that Producer's Settings."
        case .notAProducer(let address):
            return "\(address) answered, but it isn't a 13 Years Producer with the Control API on."
        case .noHello(let address):
            return "\(address) didn't start a live connection."
        }
    }
}

@MainActor
public final class RemoteProducerHub: ObservableObject {
    @Published public var isConnectPresented = false
    @Published public private(set) var session: RemoteProducerSession?
    public var pending: RemoteProducerSession?

    public init() {}

    public var isRemoteActive: Bool { session != nil }

    public func activate(_ new: RemoteProducerSession) {
        session?.disconnect()
        session = new
    }

    public func promotePending() {
        guard let pending else { return }
        self.pending = nil
        activate(pending)
    }

    public func disconnect() {
        session?.disconnect()
        session = nil
    }
}
#endif
