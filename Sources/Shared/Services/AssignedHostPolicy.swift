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
    case valid(host: String, port: UInt16?)
    case empty
    case invalid(String)

    public var host: String? {
        if case .valid(let host, _) = self { return host }
        return nil
    }

    public var port: UInt16? {
        if case .valid(_, let port) = self { return port }
        return nil
    }

    public var endpoint: String? {
        guard case .valid(let host, let port) = self else { return nil }
        return ManualHostPolicy.format(host: host, port: port)
    }

    public var message: String? {
        switch self {
        case .valid, .empty: return nil
        case .invalid(let reason): return reason
        }
    }
}

public enum ManualHostPolicy {
    public static let defaultPort: UInt16 = 13380

    private static let formatHint = "Enter an IP address like 192.168.1.20 or a name like studio-mac.local, optionally followed by :port."

    public static func validate(_ input: String) -> ManualHostValidation {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .empty }
        guard value.count <= 260 else { return .invalid("That name is too long.") }

        var hostPart = value
        var portPart: Substring?
        if value.hasPrefix("[") {
            guard let close = value.firstIndex(of: "]") else { return .invalid(formatHint) }
            hostPart = String(value[value.index(after: value.startIndex)..<close])
            let rest = value[value.index(after: close)...]
            if !rest.isEmpty {
                guard rest.hasPrefix(":") else { return .invalid(formatHint) }
                portPart = rest.dropFirst()
            }
            guard isIPv6Literal(hostPart) else { return .invalid("That isn't a valid IPv6 address.") }
        } else {
            let colons = value.filter { $0 == ":" }.count
            if colons > 1 { return .invalid("Put an IPv6 address in brackets, like [::1]:13380.") }
            if colons == 1, let index = value.firstIndex(of: ":") {
                hostPart = String(value[..<index])
                portPart = value[value.index(after: index)...]
            }
        }

        var port: UInt16?
        if let portPart {
            guard let parsed = parsePort(portPart) else {
                return .invalid("The port must be a number from 1 to 65535.")
            }
            port = parsed
        }

        guard hostPart.count <= 253, !hostPart.isEmpty else { return .invalid(formatHint) }
        if value.hasPrefix("[") { return .valid(host: hostPart, port: port) }
        if hostPart.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) {
            guard AssignedHostPolicy.ipv4Octets(hostPart) != nil else {
                return .invalid("That isn't a valid IP address.")
            }
            return .valid(host: hostPart, port: port)
        }
        guard isHostname(hostPart) else { return .invalid(formatHint) }
        return .valid(host: hostPart, port: port)
    }

    public static func format(host: String, port: UInt16?) -> String {
        let shown = host.contains(":") ? "[\(host)]" : host
        guard let port else { return shown }
        return "\(shown):\(port)"
    }

    static func parsePort(_ text: Substring) -> UInt16? {
        guard !text.isEmpty, text.count <= 5, text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = UInt16(text), number >= 1 else { return nil }
        return number
    }

    static func isIPv6Literal(_ value: String) -> Bool {
        guard value.contains(":"), !value.isEmpty else { return false }
        return value.allSatisfy { $0.isASCII && ($0.isHexDigit || $0 == ":" || $0 == ".") }
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
