// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(iOS) || os(macOS)
import Foundation

public protocol RemoteProducerHTTP: Sendable {
    func perform(method: String, url: URL, body: Data?) async throws -> (status: Int, data: Data)
}

@MainActor
public protocol RemoteSocket: AnyObject {
    var onText: ((String) -> Void)? { get set }
    var onClose: ((String) -> Void)? { get set }
    func open()
    func send(_ text: String)
    func ping(timeout: TimeInterval) async -> Bool
    func close()
}

public extension RemoteSocket {
    func send(_ text: String) {}
}

public typealias RemoteSocketFactory = @MainActor (URL) -> RemoteSocket

public struct URLSessionRemoteHTTP: RemoteProducerHTTP {
    public static let requestTimeout: TimeInterval = 3

    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.requestTimeout
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    public func perform(method: String, url: URL, body: Data?) async throws -> (status: Int, data: Data) {
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}

@MainActor
public final class URLSessionRemoteSocket: RemoteSocket {
    public var onText: ((String) -> Void)?
    public var onClose: ((String) -> Void)?

    private let task: URLSessionWebSocketTask
    private var isClosed = false

    public init(url: URL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        task = URLSession(configuration: configuration).webSocketTask(with: url)
    }

    public func open() {
        task.resume()
        receive()
    }

    private func receive() {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, !self.isClosed else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text): self.onText?(text)
                    case .data(let data): if let text = String(data: data, encoding: .utf8) { self.onText?(text) }
                    @unknown default: break
                    }
                    self.receive()
                case .failure(let error):
                    self.finish(error.localizedDescription)
                }
            }
        }
    }

    private func finish(_ reason: String) {
        guard !isClosed else { return }
        isClosed = true
        task.cancel(with: .goingAway, reason: nil)
        onClose?(reason)
    }

    public func send(_ text: String) {
        guard !isClosed else { return }
        task.send(.string(text)) { _ in }
    }

    public func ping(timeout: TimeInterval) async -> Bool {
        guard !isClosed else { return false }
        let gate = PingGate()
        return await withCheckedContinuation { continuation in
            gate.install(continuation)
            task.sendPing { error in gate.resume(error == nil) }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { gate.resume(false) }
        }
    }

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        onText = nil
        onClose = nil
        task.cancel(with: .goingAway, reason: nil)
    }
}

private final class PingGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var pending: Bool?

    func install(_ continuation: CheckedContinuation<Bool, Never>) {
        lock.lock()
        defer { lock.unlock() }
        if let pending {
            continuation.resume(returning: pending)
        } else {
            self.continuation = continuation
        }
    }

    func resume(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: value)
        } else if pending == nil {
            pending = value
        }
    }
}
#endif
