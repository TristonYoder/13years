// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(iOS) || os(macOS)
import Foundation
import Combine

@MainActor
public final class RemoteProducerSession: ObservableObject, Identifiable, RemoteProducerCommanding {
    public enum Connection: Equatable {
        case idle
        case connecting
        case connected
        case reconnecting
        case stalled(Stall)
        case failed(String)
        case disconnected
    }

    public enum Stall: Equatable, Sendable {
        case unreachable
        case refused
        case noHello
    }

    public struct ErrorNote: Identifiable, Equatable {
        public let id = UUID()
        public var message: String
        public var detail: String?
        public var at: Date
    }

    private struct QueuedCommand {
        var command: RemoteCommand
        var enqueuedAt: Date
        var epoch: Int
    }

    private enum IdentityCheck {
        case same
        case different
        case failure(Stall)
    }

    public struct Timing: Sendable {
        public var pingInterval: TimeInterval
        public var pongTimeout: TimeInterval
        public var helloTimeout: TimeInterval
        public var retryDelays: [TimeInterval]
        public var maxReconnectAttempts: Int

        public init(pingInterval: TimeInterval, pongTimeout: TimeInterval, helloTimeout: TimeInterval, retryDelays: [TimeInterval], maxReconnectAttempts: Int = 5) {
            self.pingInterval = pingInterval
            self.pongTimeout = pongTimeout
            self.helloTimeout = helloTimeout
            self.retryDelays = retryDelays
            self.maxReconnectAttempts = maxReconnectAttempts
        }

        public static let standard = Timing(pingInterval: 5, pongTimeout: 4, helloTimeout: 5, retryDelays: [0.5, 1, 2, 3, 5])
    }

    @Published public private(set) var connection: Connection = .idle
    @Published public private(set) var state: ControlAPIState?
    @Published public private(set) var lastError: String?
    @Published public private(set) var displayName: String
    @Published public private(set) var recentErrors: [ErrorNote] = []
    @Published public private(set) var isResyncing = false

    public static let errorRetention: TimeInterval = 10
    public static let errorLimit = 3

    public let id = UUID()

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
    private var producerId: String?
    private let ownDeviceId: String?
    private var connectionEpoch = 0
    var now: () -> Date = { Date() }
    var commandMaxAge: TimeInterval = 2
    private var estimator = ClockOffsetEstimator()
    private var pendingSync: [String: Int] = [:]
    private var syncCounter = 0
    private var syncTask: Task<Void, Never>?
    private var isCatchingUp = false
    public private(set) var isProtocolV2 = false
    var clock: () -> Double = { SyncClock.nowMs() }
    var syncBurstSpacing: TimeInterval = 0.1
    var syncInterval: TimeInterval = 30

    public var isLive: Bool { connection == .connected }

    public init(
        endpoint: RemoteEndpoint,
        http: RemoteProducerHTTP = URLSessionRemoteHTTP(),
        socketFactory: @escaping RemoteSocketFactory = { URLSessionRemoteSocket(url: $0) },
        timing: Timing = .standard,
        ownDeviceId: String? = CueEngine.persistentDeviceId()
    ) {
        self.ownDeviceId = ownDeviceId
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
            throw Self.isRefusal(error) ? RemoteProducerError.refused(endpoint.address) : RemoteProducerError.unreachable(endpoint.address)
        }
        guard (200..<300).contains(status),
              let health = try? JSONDecoder().decode(RemoteProducerHealth.self, from: data),
              health.service == RemoteProducerHealth.serviceName else {
            throw RemoteProducerError.notAProducer(endpoint.address)
        }
        return health
    }

    static func isRefusal(_ error: Error) -> Bool {
        guard let urlError = error as? URLError, urlError.code == .cannotConnectToHost else { return false }
        if let underlying = urlError.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
            return underlying.code == Int(ECONNREFUSED)
        }
        return true
    }

    public func connect() async {
        guard connection == .idle || connection == .disconnected || isFailed else { return }
        isUserDisconnected = false
        connection = .connecting
        lastError = nil
        do {
            let health = try await Self.fetchHealth(of: endpoint, using: http)
            if let ownDeviceId, health.deviceId == ownDeviceId {
                connection = .failed(RemoteProducerError.thisDevice.localizedDescription)
                return
            }
            producerId = health.deviceId
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
        resetSync()
        closeSocket()
        connectionEpoch += 1
        isResyncing = false
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
        guard let data = text.data(using: .utf8) else { return }
        let receivedAtMs = clock()
        guard let head = try? JSONDecoder().decode(EventHead.self, from: data) else {
            handleReply(data, receivedAtMs: receivedAtMs)
            return
        }
        let decoder = ControlAPIJSON.decoder
        switch head.event {
        case "hello":
            guard let event = try? decoder.decode(Event<ControlAPIState>.self, from: data) else { return }
            tracker.reset()
            tracker.hello(event.data)
            isResyncing = false
            helloGeneration = generation
            state = tracker.state
            engine.apply(remoteState: event.data)
            negotiateProtocol()
        case "digest":
            guard let event = try? decoder.decode(Event<ControlAPIDigest>.self, from: data) else { return }
            verify(digest: event.data)
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

    private func negotiateProtocol() {
        resetSync()
        socket?.send("{\"id\":\"proto\",\"op\":\"proto\",\"body\":{\"version\":2}}")
    }

    private func handleReply(_ data: Data, receivedAtMs: Double) {
        guard let head = try? JSONDecoder().decode(ReplyHead.self, from: data), let id = head.id else { return }
        if id == "proto" {
            guard head.status == 200 else { return }
            isProtocolV2 = true
            startSync()
        } else if let t0 = pendingSync.removeValue(forKey: id) {
            guard head.status == 200, let reply = try? JSONDecoder().decode(Reply<ControlAPISyncReply>.self, from: data),
                  reply.data.t0 == t0 else { return }
            let sample = ClockSyncSample(t0: Double(t0), t1: Double(reply.data.t1), t2: Double(reply.data.t2), t3: receivedAtMs)
            if estimator.add(sample) {
                engine.setRemoteClockOffset(estimator.offsetMs)
            }
        }
    }

    private func startSync() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            guard let self else { return }
            for index in 0..<CueEngine.syncBurstCount {
                if Task.isCancelled { return }
                self.sendSyncSample()
                if index < CueEngine.syncBurstCount - 1 {
                    try? await Task.sleep(nanoseconds: UInt64(self.syncBurstSpacing * 1_000_000_000))
                }
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.syncInterval * 1_000_000_000))
                if Task.isCancelled { return }
                self.sendSyncSample()
            }
        }
    }

    func sendSyncSample() {
        guard isProtocolV2, let socket else { return }
        syncCounter += 1
        let id = "sync-\(syncCounter)"
        let t0 = Int(clock().rounded())
        pendingSync[id] = t0
        if pendingSync.count > 32, let oldest = pendingSync.keys.min(by: { Int($0.dropFirst(5)) ?? 0 < Int($1.dropFirst(5)) ?? 0 }) {
            pendingSync.removeValue(forKey: oldest)
        }
        socket.send("{\"id\":\"\(id)\",\"op\":\"sync\",\"body\":{\"t0\":\(t0)}}")
    }

    public func resync() {
        sendSyncSample()
    }

    private func resetSync() {
        syncTask?.cancel()
        syncTask = nil
        pendingSync = [:]
        isProtocolV2 = false
        estimator.reset()
        engine.setRemoteClockOffset(nil)
    }

    private func verify(digest: ControlAPIDigest) {
        guard digest.rev >= tracker.lastRev else { return }
        guard !engine.mirrorHashes().mismatches(against: digest.hashes).isEmpty else { return }
        Task { [weak self] in await self?.catchUpFromState() }
    }

    func catchUpFromState() async {
        guard !isCatchingUp, isLive, let url = endpoint.url(path: "/v1/state") else { return }
        isCatchingUp = true
        defer { isCatchingUp = false }
        guard let (status, data) = try? await http.perform(method: "GET", url: url, body: nil),
              (200..<300).contains(status),
              let snapshot = try? ControlAPIJSON.decoder.decode(ControlAPIState.self, from: data),
              tracker.refresh(snapshot) else { return }
        state = tracker.state
        engine.apply(remoteState: snapshot)
    }

    private func restoreHeldState() {
        guard let held = tracker.state else { return }
        engine.apply(remoteState: held)
    }

    public func checkLiveness() async {
        guard connection == .connected, let current = socket else { return }
        let alive = await current.ping(timeout: timing.pongTimeout)
        guard connection == .connected, socket === current, !alive else { return }
        isResyncing = true
        connectionLost()
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
        resetSync()
        closeSocket()
        connectionEpoch += 1
        connection = .reconnecting
        startReconnectLoop()
    }

    public func reconnectNow() {
        guard case .stalled = connection, !isUserDisconnected else { return }
        connection = .reconnecting
        startReconnectLoop()
    }

    private func startReconnectLoop() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            var attempt = 0
            var lastStall = Stall.unreachable
            while let self, !Task.isCancelled, !self.isUserDisconnected {
                if attempt >= self.timing.maxReconnectAttempts {
                    self.connection = .stalled(lastStall)
                    return
                }
                let delays = self.timing.retryDelays
                let delay = delays.isEmpty ? 1 : delays[min(attempt, delays.count - 1)]
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled || self.isUserDisconnected { return }
                switch await self.checkIdentity() {
                case .different:
                    self.connection = .failed(RemoteProducerError.differentProducer(self.endpoint.address).localizedDescription)
                    return
                case .failure(let stall):
                    lastStall = stall
                case .same:
                    if await self.openAndAwaitHello() {
                        self.connection = .connected
                        self.startKeepalive()
                        return
                    }
                    lastStall = .noHello
                }
                attempt += 1
            }
        }
    }

    private func checkIdentity() async -> IdentityCheck {
        do {
            let health = try await Self.fetchHealth(of: endpoint, using: http)
            if let producerId, health.deviceId != producerId { return .different }
            return .same
        } catch RemoteProducerError.refused {
            return .failure(.refused)
        } catch RemoteProducerError.notAProducer {
            return .different
        } catch {
            return .failure(.unreachable)
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
            restoreHeldState()
            return
        }
        let queued = QueuedCommand(command: command, enqueuedAt: now(), epoch: connectionEpoch)
        let previous = commandTail
        commandTail = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await self?.perform(queued)
        }
    }

    private func perform(_ queued: QueuedCommand) async {
        guard isLive, queued.epoch == connectionEpoch else {
            report("A command queued before the connection changed was dropped.", detail: "Check \(displayName) and try again.")
            restoreHeldState()
            return
        }
        guard now().timeIntervalSince(queued.enqueuedAt) <= commandMaxAge else {
            report("A command waited too long and was dropped.", detail: "Check \(displayName) and try again.")
            restoreHeldState()
            return
        }
        let command = queued.command
        do {
            let (status, data) = try await send(command.request, idempotent: command.isIdempotent)
            if case .waypointCreateAndAssign(_, let itemId) = command, (200..<300).contains(status) {
                guard connectionEpoch == queued.epoch else { return }
                guard let created = try? ControlAPIJSON.decoder.decode(ControlAPIState.WaypointStatus.self, from: data) else {
                    report("The waypoint was created but its id couldn't be read.", detail: "Assign it to the item manually.")
                    return
                }
                let assign = RemoteCommand.waypointAssign(ref: created.id, itemId: itemId)
                let (assignStatus, assignData) = try await send(assign.request, idempotent: true)
                handleReply(status: assignStatus, data: assignData)
                return
            }
            handleReply(status: status, data: data)
        } catch {
            let timedOut = (error as? URLError)?.code == .timedOut
            if timedOut {
                report("\(displayName) didn't answer in time.", detail: "The command may have been applied — check the state before retrying.")
            } else {
                report("Couldn't reach \(displayName).", detail: "The command may not have been applied — check the state before retrying.")
            }
            restoreHeldState()
            Task { [weak self] in await self?.catchUpFromState() }
        }
    }

    private func send(_ request: RemoteCommand.Request, idempotent: Bool) async throws -> (status: Int, data: Data) {
        guard let url = endpoint.url(path: request.path) else { throw RemoteProducerError.invalidAddress }
        do {
            return try await http.perform(method: request.method, url: url, body: request.body)
        } catch {
            guard idempotent, isLive else { throw error }
            return try await http.perform(method: request.method, url: url, body: request.body)
        }
    }

    private func handleReply(status: Int, data: Data) {
        if (200..<300).contains(status) {
            if let snapshot = try? ControlAPIJSON.decoder.decode(ControlAPIState.self, from: data), tracker.accept(snapshot) {
                state = tracker.state
                engine.apply(remoteState: snapshot)
            }
        } else {
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            report(body?.error ?? "\(displayName) refused the command (\(status)).", detail: body?.detail)
            restoreHeldState()
        }
    }

    private func report(_ message: String, detail: String? = nil) {
        recentErrors.append(ErrorNote(message: message, detail: detail, at: now()))
        pruneErrors()
        errorClearTask?.cancel()
        errorClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.errorRetention * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.pruneErrors()
        }
    }

    func pruneErrors() {
        let cutoff = now().addingTimeInterval(-Self.errorRetention)
        var kept = recentErrors.filter { $0.at > cutoff }
        if kept.count > Self.errorLimit { kept = Array(kept.suffix(Self.errorLimit)) }
        if kept != recentErrors { recentErrors = kept }
        lastError = kept.last?.message
    }

    public func dismissError() {
        recentErrors = []
        lastError = nil
    }

    private struct EventHead: Decodable {
        let event: String
    }

    private struct ReplyHead: Decodable {
        let id: String?
        let status: Int
    }

    private struct Reply<Payload: Decodable>: Decodable {
        let id: String?
        let status: Int
        let data: Payload
    }

    private struct Event<Payload: Decodable>: Decodable {
        let event: String
        let data: Payload
    }

    private struct ErrorBody: Decodable {
        let error: String
        let detail: String?
    }
}

public enum RemoteProducerError: LocalizedError, Equatable {
    case invalidAddress
    case unreachable(String)
    case notAProducer(String)
    case noHello(String)
    case refused(String)
    case differentProducer(String)
    case thisDevice

    public var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "That address isn't valid."
        case .unreachable(let address):
            return "Couldn't reach \(address). Check the address, and that both devices are on the same network."
        case .refused(let address):
            return "\(address) refused the connection. Switch on the Control API in that Producer's Settings."
        case .differentProducer(let address):
            return "A different Producer is now at \(address). Disconnect and connect again if that's intended."
        case .thisDevice:
            return "That's this device. Choose another Producer."
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
