// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

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
                let isLoopback = (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) != 0
                let isUp = (ifa.ifa_flags & UInt32(IFF_UP)) != 0
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

public struct LANConnectionID: Hashable, Sendable {
    public let raw: UInt64

    public init(raw: UInt64) {
        self.raw = raw
    }

    init(raw: ObjectIdentifier) {
        self.raw = UInt64(UInt(bitPattern: raw))
    }
}

public enum LANAudience: Sendable {
    case all
    case legacy
    case v2
    case connection(LANConnectionID)
}
