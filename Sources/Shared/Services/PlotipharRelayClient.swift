// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public final class PlotipharRelayClient: NSObject, @unchecked Sendable {
    public var onPacketReceived: ((CuePacket) -> Void)?
    public var onTextMessageReceived: ((Data) -> Void)?

    public var relayHost: String = ""
    public var token: String = ""

    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private let queue = DispatchQueue(label: "dev.7co.13years.relay")
    private var isRunning = false
    private var reconnectWorkItem: DispatchWorkItem?
    private var reconnectDelay: TimeInterval
    private var generation = 0

    private static let initialReconnectDelay: TimeInterval = 1
    private static let maxReconnectDelay: TimeInterval = 30

    public override init() {
        self.session = URLSession(configuration: .default)
        self.reconnectDelay = PlotipharRelayClient.initialReconnectDelay
        super.init()
    }

    public func start() {
        queue.async { [self] in
            guard !isRunning else { return }
            isRunning = true
            reconnectDelay = Self.initialReconnectDelay
            connect()
        }
    }

    public func stop() {
        queue.async { [self] in
            isRunning = false
            generation += 1
            reconnectWorkItem?.cancel()
            reconnectWorkItem = nil
            task?.cancel(with: .goingAway, reason: nil)
            task = nil
        }
    }

    public func broadcast(packet: CuePacket) {
        send(packet: packet)
    }

    public func send(packet: CuePacket) {
        queue.async { [self] in
            guard isRunning, let task, let data = packet.encode() else { return }
            task.send(.data(data)) { error in
                if let error {
                    print("[PlotipharRelayClient] Send error: \(error)")
                }
            }
        }
    }

    public func sendText(_ data: Data) {
        queue.async { [self] in
            guard isRunning, let task, let string = String(data: data, encoding: .utf8) else { return }
            task.send(.string(string)) { error in
                if let error {
                    print("[PlotipharRelayClient] Text send error: \(error)")
                }
            }
        }
    }

    private func connect() {
        guard isRunning else { return }
        guard let url = relayURL() else {
            print("[PlotipharRelayClient] Invalid relay host: \(relayHost)")
            scheduleReconnect()
            return
        }
        guard !token.isEmpty else {
            scheduleReconnect()
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let newTask = session.webSocketTask(with: request)
        task = newTask
        let myGeneration = generation
        newTask.resume()
        receiveLoop(task: newTask, generation: myGeneration)
    }

    private func relayURL() -> URL? {
        var host = relayHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }

        if !host.contains("://") {
            host = "wss://\(host)"
        }
        guard var components = URLComponents(string: host) else { return nil }
        if components.scheme == "http" { components.scheme = "ws" }
        if components.scheme == "https" { components.scheme = "wss" }
        if components.scheme == nil { components.scheme = "wss" }

        if components.path.isEmpty || components.path == "/" {
            components.path = "/relay"
        }
        return components.url
    }

    private func receiveLoop(task: URLSessionWebSocketTask, generation: Int) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard self.generation == generation, self.isRunning else { return }

                switch result {
                case .failure(let error):
                    print("[PlotipharRelayClient] Receive error: \(error)")
                    self.handleDisconnect(generation: generation)
                case .success(let message):
                    self.handle(message: message)
                    self.receiveLoop(task: task, generation: generation)
                }
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            guard let packet = CuePacket.decode(from: data) else { return }
            reconnectDelay = Self.initialReconnectDelay
            DispatchQueue.main.async { [weak self] in
                self?.onPacketReceived?(packet)
            }
        case .string(let string):
            guard let data = string.data(using: .utf8) else { return }
            reconnectDelay = Self.initialReconnectDelay
            DispatchQueue.main.async { [weak self] in
                self?.onTextMessageReceived?(data)
            }
        @unknown default:
            break
        }
    }

    private func handleDisconnect(generation: Int) {
        guard generation == self.generation, isRunning else { return }
        task = nil
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard isRunning else { return }
        reconnectWorkItem?.cancel()

        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, Self.maxReconnectDelay)

        let myGeneration = generation
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isRunning, self.generation == myGeneration else { return }
            self.connect()
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
