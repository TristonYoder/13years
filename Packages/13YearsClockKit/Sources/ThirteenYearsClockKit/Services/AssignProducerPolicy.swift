// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public struct AssignProducerPlan: Equatable, Sendable {
    public var host: String
    public var port: Int?
    public var introducer: Bool

    public init(host: String, port: Int? = nil, introducer: Bool = false) {
        self.host = host
        self.port = port
        self.introducer = introducer
    }

    public var jsonObject: [String: Any] {
        var object: [String: Any] = ["type": "ASSIGN_PRODUCER", "host": host]
        if let port { object["port"] = port }
        if introducer { object["mode"] = "introducer" }
        return object
    }
}

public struct RemoteAssignContext: Equatable, Sendable {
    public var endpointHost: String
    public var lanPort: Int?
    public var lanMode: RemoteLANMode

    public init(endpointHost: String, lanPort: Int?, lanMode: RemoteLANMode) {
        self.endpointHost = endpointHost
        self.lanPort = lanPort
        self.lanMode = lanMode
    }
}

public enum AssignProducerPolicy {
    public static let defaultPagerPort = 13380

    public static func plan(selfAddress: String?, remote: RemoteAssignContext?, resolveServer: (String) -> String?) -> AssignProducerPlan? {
        guard let remote, remote.lanMode != .localRelay else {
            guard let selfAddress else { return nil }
            return AssignProducerPlan(host: selfAddress)
        }
        guard let server = resolveServer(remote.endpointHost) else { return nil }
        let port = remote.lanPort.flatMap { (1...65535).contains($0) ? $0 : nil } ?? defaultPagerPort
        return AssignProducerPlan(host: server, port: port, introducer: true)
    }

    public static func resolveIPv4(_ host: String) -> String? {
        if AssignedHostPolicy.ipv4Octets(host) != nil { return host }
        var hints = addrinfo()
        hints.ai_family = AF_INET
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let info = result else { return nil }
        defer { freeaddrinfo(result) }
        guard let address = info.pointee.ai_addr else { return nil }
        var buffer = [CChar](repeating: 0, count: 64)
        let found = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer -> Bool in
            var sin = pointer.pointee.sin_addr
            return inet_ntop(AF_INET, &sin, &buffer, socklen_t(buffer.count)) != nil
        }
        return found ? String(cString: buffer) : nil
    }

    public struct Accepted: Equatable, Sendable {
        public var host: String
        public var port: Int

        public var endpoint: String {
            ManualHostPolicy.format(host: host, port: port == AssignProducerPolicy.defaultPagerPort ? nil : UInt16(port))
        }
    }

    public static func accept(_ json: [String: Any], senderIP: String?) -> Accepted? {
        guard json["type"] as? String == "ASSIGN_PRODUCER",
              let rawHost = json["host"] as? String else { return nil }
        let host = rawHost.trimmingCharacters(in: .whitespaces)
        guard AssignedHostPolicy.isAcceptable(host) else { return nil }
        let introducer = json["mode"] as? String == "introducer"
        guard introducer || host == senderIP else { return nil }
        var port = defaultPagerPort
        if let rawPort = json["port"] {
            guard let number = rawPort as? Int, (1...65535).contains(number) else { return nil }
            port = number
        }
        return Accepted(host: host, port: port)
    }

    public static func parseStored(_ value: String) -> Accepted? {
        guard case .valid(let host, let port) = ManualHostPolicy.validate(value),
              AssignedHostPolicy.isAcceptable(host) else { return nil }
        return Accepted(host: host, port: Int(port ?? UInt16(defaultPagerPort)))
    }
}
