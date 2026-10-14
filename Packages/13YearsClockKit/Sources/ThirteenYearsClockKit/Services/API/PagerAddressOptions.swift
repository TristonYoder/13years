// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct PagerAddress: Equatable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case hostname
        case wifi
        case ethernet
        case vpn
        case cellular
        case bridge
        case linkLocal
        case loopback
        case other
    }

    public var host: String
    public var kind: Kind
    public var interface: String?

    public init(host: String, kind: Kind, interface: String? = nil) {
        self.host = host
        self.kind = kind
        self.interface = interface
    }

    public var id: String { host }

    public var isIPv6: Bool { host.contains(":") }

    public var label: String { PagerAddressOptions.label(host: host, kind: kind, interface: interface) }
}

public enum PagerAddressOptions {
    public static func kind(host: String, interface: String) -> PagerAddress.Kind {
        if host == "127.0.0.1" || host == "::1" || interface.hasPrefix("lo") { return .loopback }
        if host.hasPrefix("169.254.") || host.lowercased().hasPrefix("fe80:") { return .linkLocal }
        if isCarrierGradeNAT(host) { return .vpn }
        for prefix in ["utun", "ipsec", "ppp", "tun", "tap", "wg"] where interface.hasPrefix(prefix) { return .vpn }
        if interface.hasPrefix("pdp_ip") { return .cellular }
        if interface.hasPrefix("bridge") { return .bridge }
        if interface == "en0" { return .wifi }
        if interface.hasPrefix("en") { return .ethernet }
        return .other
    }

    public static func isCarrierGradeNAT(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts[0] == 100 else { return false }
        return (64...127).contains(parts[1])
    }

    public static func label(host: String, kind: PagerAddress.Kind, interface: String?) -> String {
        let name = interface.map { " (\($0))" } ?? ""
        switch kind {
        case .hostname: return "\(host) — Hostname, survives address changes"
        case .wifi: return "\(host) — Wi-Fi\(name)"
        case .ethernet: return "\(host) — Ethernet\(name)"
        case .vpn: return "\(host) — VPN/Tailscale\(name)"
        case .cellular: return "\(host) — Cellular\(name)"
        case .bridge: return "\(host) — Bridge\(name)"
        case .linkLocal: return "\(host) — Link-local, not routable\(name)"
        case .loopback: return "\(host) — This device only"
        case .other: return "\(host) —\(interface.map { " \($0)" } ?? " Network")"
        }
    }

    public static func hostname(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "localhost" else { return nil }
        if trimmed.lowercased().hasSuffix(".local") { return trimmed }
        guard let first = trimmed.split(separator: ".").first, !first.isEmpty else { return nil }
        return String(first) + ".local"
    }

    public static func arrange(_ found: [PagerAddress], hostname: String?) -> [PagerAddress] {
        var seen = Set<String>()
        let unique = found.filter { seen.insert($0.host).inserted }
        let loopback = unique.filter { $0.kind == .loopback && !$0.isIPv6 }
        let remaining = unique.filter { $0.kind != .loopback }
        let v4 = remaining.filter { !$0.isIPv6 }
        var v6 = remaining.filter { $0.isIPv6 }
        let routableV6 = v6.filter { $0.kind != .linkLocal }
        if !routableV6.isEmpty || !v4.isEmpty { v6 = routableV6 }
        var result: [PagerAddress] = []
        if let hostname { result.append(PagerAddress(host: hostname, kind: .hostname)) }
        result += v4 + v6 + loopback
        return result
    }

    public static func defaultChoice(_ options: [PagerAddress]) -> PagerAddress? {
        options.first { !$0.isIPv6 && ($0.kind == .wifi || $0.kind == .ethernet) }
            ?? options.first { $0.kind == .hostname }
            ?? options.first
    }

    public static func parseCustom(_ text: String, defaultPort: Int) -> (host: String, port: Int)? {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.lowercased().hasPrefix("http://") { rest = String(rest.dropFirst(7)) }
        if let slash = rest.firstIndex(of: "/") { rest = String(rest[..<slash]) }
        guard !rest.isEmpty, !rest.contains(where: { $0.isWhitespace }) else { return nil }

        func port(_ text: String) -> Int? {
            guard let value = Int(text), (1...65535).contains(value) else { return nil }
            return value
        }

        if rest.hasPrefix("[") {
            guard let close = rest.firstIndex(of: "]") else { return nil }
            let host = String(rest[rest.index(after: rest.startIndex)..<close])
            guard host.contains(":") else { return nil }
            let tail = rest[rest.index(after: close)...]
            if tail.isEmpty { return (host, defaultPort) }
            guard tail.hasPrefix(":"), let p = port(String(tail.dropFirst())) else { return nil }
            return (host, p)
        }

        let colons = rest.filter { $0 == ":" }.count
        if colons >= 2 { return (rest, defaultPort) }
        if colons == 1 {
            let pieces = rest.split(separator: ":", omittingEmptySubsequences: false)
            guard pieces.count == 2, !pieces[0].isEmpty, let p = port(String(pieces[1])) else { return nil }
            return (String(pieces[0]), p)
        }
        return (rest, defaultPort)
    }

    private static func socketLength(of addr: UnsafeMutablePointer<sockaddr>) -> socklen_t {
        #if canImport(Darwin)
        return socklen_t(addr.pointee.sa_len)
        #else
        return socklen_t(Int32(addr.pointee.sa_family) == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
        #endif
    }

    public static func localAddresses(hostName: String = ProcessInfo.processInfo.hostName) -> [PagerAddress] {
        var found: [PagerAddress] = [PagerAddress(host: "127.0.0.1", kind: .loopback, interface: "lo0")]
        var head: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&head) == 0, let first = head {
            defer { freeifaddrs(head) }
            var pointer: UnsafeMutablePointer<ifaddrs>? = first
            while let current = pointer {
                defer { pointer = current.pointee.ifa_next }
                let entry = current.pointee
                let flags = UInt32(entry.ifa_flags)
                guard (flags & UInt32(IFF_UP)) == UInt32(IFF_UP), (flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
                guard let addr = entry.ifa_addr else { continue }
                let family = Int32(addr.pointee.sa_family)
                guard family == AF_INET || family == AF_INET6 else { continue }
                let name = String(cString: entry.ifa_name)
                if ["awdl", "llw", "anpi", "ap", "gif", "stf"].contains(where: { name.hasPrefix($0) }) { continue }
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let status = getnameinfo(addr, Self.socketLength(of: addr), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
                guard status == 0 else { continue }
                var host = String(cString: buffer)
                if let percent = host.firstIndex(of: "%") { host = String(host[..<percent]) }
                found.append(PagerAddress(host: host, kind: kind(host: host, interface: name), interface: name))
            }
        }
        return arrange(found, hostname: hostname(from: hostName))
    }
}
