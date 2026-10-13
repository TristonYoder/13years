// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum AssignedHostPolicy {
    public static func isAcceptable(_ host: String) -> Bool {
        let value = host.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, value.count <= 253 else { return false }
        if let octets = ipv4Octets(value) {
            return isPrivateOrLocal(octets)
        }
        return isMulticastDNSName(value)
    }

    static func ipv4Octets(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(part), number <= 255 else { return nil }
            octets.append(number)
        }
        return octets
    }

    static func isPrivateOrLocal(_ octets: [Int]) -> Bool {
        switch (octets[0], octets[1]) {
        case (10, _): return true
        case (127, _): return true
        case (172, 16...31): return true
        case (192, 168): return true
        case (169, 254): return true
        case (100, 64...127): return true
        default: return false
        }
    }

    static func isMulticastDNSName(_ value: String) -> Bool {
        let lowered = value.lowercased()
        guard lowered.hasSuffix(".local") else { return false }
        let labels = lowered.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }
}

public enum ManualHostValidation: Equatable {
    case valid(String)
    case empty
    case invalid(String)

    public var host: String? {
        if case .valid(let host) = self { return host }
        return nil
    }

    public var message: String? {
        switch self {
        case .valid, .empty: return nil
        case .invalid(let reason): return reason
        }
    }
}

public enum ManualHostPolicy {
    public static func validate(_ input: String) -> ManualHostValidation {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .empty }
        guard value.count <= 253 else { return .invalid("That name is too long.") }
        if value.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) {
            guard AssignedHostPolicy.ipv4Octets(value) != nil else {
                return .invalid("That isn't a valid IP address.")
            }
            return .valid(value)
        }
        guard isHostname(value) else {
            return .invalid("Enter an IP address like 192.168.1.20 or a name like studio-mac.local.")
        }
        return .valid(value)
    }

    static func isHostname(_ value: String) -> Bool {
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }
}

public enum ProducerLinkStatus: Equatable {
    case idle
    case connecting(host: String)
    case unreachable(host: String)
    case localNetworkDenied
    case connected

    public var message: String? {
        switch self {
        case .idle, .connected: return nil
        case .connecting(let host): return "Connecting to \(host)…"
        case .unreachable(let host): return "Can't reach \(host)"
        case .localNetworkDenied: return "Local Network access is off for 13 Years. Turn it on in Settings › Privacy & Security › Local Network."
        }
    }

    public var isProblem: Bool {
        switch self {
        case .unreachable, .localNetworkDenied: return true
        default: return false
        }
    }
}
