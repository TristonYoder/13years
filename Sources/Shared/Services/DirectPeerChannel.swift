// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
import Network
import Security

public struct PeerHello: Codable, Sendable {
    public var addresses: [String]
    public var port: UInt16
    public var connectToken: String

    public init(addresses: [String], port: UInt16, connectToken: String) {
        self.addresses = addresses
        self.port = port
        self.connectToken = connectToken
    }

    public func encode() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func decode(from data: Data) -> PeerHello? {
        try? JSONDecoder().decode(PeerHello.self, from: data)
    }
}

public final class DirectPeerChannel: @unchecked Sendable {
    public var onPacketReceived: ((CuePacket) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "dev.7co.13years.directpeer", qos: .userInteractive)
    private var isRunning = false

    private var localToken: String = ""
    private var localPort: UInt16 = 0

    private var pendingInboundConnections: [ObjectIdentifier: NWConnection] = [:]
    private var verifiedConnections: [ObjectIdentifier: NWConnection] = [:]

    public init() {}

    public func start() {
        queue.async { [self] in
            guard !isRunning else { return }
            isRunning = true
            localToken = Self.generateToken()
            startListening()
        }
    }

    public func stop() {
        queue.async { [self] in
            isRunning = false
            listener?.cancel()
            listener = nil
            for (_, connection) in pendingInboundConnections {
                connection.cancel()
            }
            pendingInboundConnections.removeAll()
            for (_, connection) in verifiedConnections {
                connection.cancel()
            }
            verifiedConnections.removeAll()
            localToken = ""
            localPort = 0
        }
    }

    public func buildHelloPayload() -> Data? {
        queue.sync {
            guard isRunning, localPort != 0, !localToken.isEmpty else { return nil }
            let hello = PeerHello(
                addresses: Self.localIPv4Addresses(),
                port: localPort,
                connectToken: localToken
            )
            return hello.encode()
        }
    }

    public func send(packet: CuePacket) {
        queue.async { [self] in
            guard let data = packet.encode() else { return }
            guard let framed = Self.frame(data) else { return }
            for (_, connection) in verifiedConnections {
                connection.send(content: framed, completion: .contentProcessed { error in
                    if let error {
                        print("[DirectPeerChannel] Send error: \(error)")
                    }
                })
            }
        }
    }

    public func connect(to peerHello: PeerHello) {
        queue.async { [self] in
            guard isRunning else { return }
            self.dial(peerHello: peerHello, addressIndex: 0)
        }
    }

    private func startListening() {
        do {
            let parameters = NWParameters.tcp
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue {
                        self?.queue.async { self?.localPort = port }
                    }
                    print("[DirectPeerChannel] Listening")
                case .failed(let error):
                    print("[DirectPeerChannel] Listener failed: \(error)")
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.acceptInbound(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            print("[DirectPeerChannel] Failed to start listener: \(error)")
        }
    }

    private func acceptInbound(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        pendingInboundConnections[key] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.queue.async {
                    self?.pendingInboundConnections.removeValue(forKey: key)
                    self?.verifiedConnections.removeValue(forKey: key)
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveFrame(on: connection) { [weak self] data in
            guard let self else { return }
            guard let data, let receivedToken = String(data: data, encoding: .utf8), receivedToken == self.localToken else {
                print("[DirectPeerChannel] Inbound connection presented invalid token — closing")
                connection.cancel()
                self.pendingInboundConnections.removeValue(forKey: key)
                return
            }
            self.pendingInboundConnections.removeValue(forKey: key)
            self.verifiedConnections[key] = connection
            self.receivePacketLoop(on: connection, key: key)
        }
    }

    private func dial(peerHello: PeerHello, addressIndex: Int) {
        guard addressIndex < peerHello.addresses.count else { return }
        let address = peerHello.addresses[addressIndex]
        guard let port = NWEndpoint.Port(rawValue: peerHello.port) else { return }

        let host = NWEndpoint.Host(address)
        let connection = NWConnection(host: host, port: port, using: .tcp)
        let key = ObjectIdentifier(connection)

        var didFinish = false
        let timeout = DispatchWorkItem { [weak self] in
            guard !didFinish else { return }
            didFinish = true
            connection.cancel()
            self?.dial(peerHello: peerHello, addressIndex: addressIndex + 1)
        }
        queue.asyncAfter(deadline: .now() + 3, execute: timeout)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard !didFinish else { return }
                didFinish = true
                timeout.cancel()
                guard let tokenData = peerHello.connectToken.data(using: .utf8),
                      let framed = Self.frame(tokenData) else {
                    connection.cancel()
                    return
                }
                connection.send(content: framed, completion: .contentProcessed { [weak self] error in
                    guard let self else { return }
                    if let error {
                        print("[DirectPeerChannel] Failed to send token to peer: \(error)")
                        connection.cancel()
                        return
                    }
                    self.queue.async {
                        guard connection.state == .ready else { return }
                        self.verifiedConnections[key] = connection
                        self.receivePacketLoop(on: connection, key: key)
                    }
                })
            case .failed, .cancelled:
                guard !didFinish else { return }
                didFinish = true
                timeout.cancel()
                self.queue.async {
                    self.verifiedConnections.removeValue(forKey: key)
                    self.dial(peerHello: peerHello, addressIndex: addressIndex + 1)
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receivePacketLoop(on connection: NWConnection, key: ObjectIdentifier) {
        receiveFrame(on: connection) { [weak self] data in
            guard let self else { return }
            guard let data else {
                self.verifiedConnections.removeValue(forKey: key)
                return
            }
            if let packet = CuePacket.decode(from: data) {
                DispatchQueue.main.async {
                    self.onPacketReceived?(packet)
                }
            }
            self.receivePacketLoop(on: connection, key: key)
        }
    }

    private func receiveFrame(on connection: NWConnection, completion: @escaping (Data?) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] lengthData, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                if let error {
                    print("[DirectPeerChannel] Receive error (length prefix): \(error)")
                    completion(nil)
                    return
                }
                guard let lengthData, lengthData.count == 4 else {
                    completion(nil)
                    return
                }
                let length = Self.decodeLength(lengthData)
                guard length > 0, length <= 1 * 1024 * 1024 else {
                    completion(nil)
                    return
                }
                connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] payload, _, _, error in
                    guard let self else { return }
                    self.queue.async {
                        if let error {
                            print("[DirectPeerChannel] Receive error (payload): \(error)")
                            completion(nil)
                            return
                        }
                        guard let payload, payload.count == Int(length) else {
                            completion(nil)
                            return
                        }
                        completion(payload)
                    }
                }
            }
        }
    }

    static func frame(_ payload: Data) -> Data? {
        guard payload.count <= UInt32.max else { return nil }
        var length = UInt32(payload.count).bigEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(payload)
        return framed
    }

    static func decodeLength(_ data: Data) -> UInt32 {
        precondition(data.count == 4)
        return data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
        }
    }

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if result != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: 0...255, using: &generator)
            }
        }
        return Data(bytes).base64EncodedString()
    }

    static func localIPv4Addresses() -> [String] {
        var addresses: [String] = []

        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else {
            return addresses
        }
        defer { freeifaddrs(ifaddrPointer) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let address = String(cString: hostBuffer)

            guard address != "127.0.0.1", !address.hasPrefix("169.254.") else { continue }

            addresses.append(address)
        }

        return addresses
    }
}
