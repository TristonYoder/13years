// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum ControlAPIGuard {
    public enum Verdict: Equatable, Sendable {
        case allow
        case reject(status: Int, message: String)
    }

    public static func hostname() -> String {
        ProcessInfo.processInfo.hostName.lowercased()
    }

    public static func evaluate(_ request: HTTPRequest, machineHostName: String = hostname()) -> Verdict {
        let hostHeader = request.header("host")
        if let hostHeader, !isAllowedHost(hostHeader, machineHostName: machineHostName) {
            return .reject(status: 403, message: "Host not allowed")
        }
        if let origin = request.header("origin"), !isSameOrigin(origin, host: hostHeader) {
            return .reject(status: 403, message: "Cross-origin requests are not allowed")
        }
        if carriesBody(request), !isJSONContentType(request.header("content-type")) {
            return .reject(status: 415, message: "Content-Type must be application/json")
        }
        return .allow
    }

    public static func carriesBody(_ request: HTTPRequest) -> Bool {
        ["POST", "PUT", "PATCH"].contains(request.method.uppercased()) && !request.body.isEmpty
    }

    public static func isJSONContentType(_ value: String?) -> Bool {
        guard let value else { return false }
        let media = value.split(separator: ";", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        return media == "application/json"
    }

    static func splitAuthority(_ authority: String) -> (host: String, port: Int?)? {
        let trimmed = authority.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("[") {
            guard let close = trimmed.firstIndex(of: "]") else { return nil }
            let host = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
            let rest = trimmed[trimmed.index(after: close)...]
            if rest.isEmpty { return (host, nil) }
            guard rest.hasPrefix(":"), let port = Int(rest.dropFirst()) else { return nil }
            return (host, port)
        }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.count {
        case 1: return (String(parts[0]), nil)
        case 2:
            guard let port = Int(parts[1]) else { return nil }
            return (String(parts[0]), port)
        default: return nil
        }
    }

    public static func isAllowedHost(_ authority: String, machineHostName: String = hostname()) -> Bool {
        guard let (host, _) = splitAuthority(authority), !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".localhost") { return true }
        if isIPLiteral(host) { return true }
        if host.hasSuffix(".local") && host.count > ".local".count { return true }
        let machine = machineHostName.lowercased()
        guard !machine.isEmpty else { return false }
        return host == machine || host == machine + ".local" || machine == host + ".local"
    }

    static func isIPLiteral(_ host: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return inet_pton(AF_INET, host, &v4) == 1 || inet_pton(AF_INET6, host, &v6) == 1
    }

    public static func isSameOrigin(_ origin: String, host: String?) -> Bool {
        guard let host, let own = splitAuthority(host) else { return false }
        guard let components = URLComponents(string: origin), let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let originHost = components.host?.lowercased() else { return false }
        let defaultPort = scheme == "https" ? 443 : 80
        let originPort = components.port ?? defaultPort
        let ownPort = own.port ?? 80
        return originHost == own.host && originPort == ownPort
    }

    public static func isAllowedWebSocketUpgrade(_ request: HTTPRequest, machineHostName: String = hostname()) -> Bool {
        guard let host = request.header("host") else {
            return request.header("origin") == nil
        }
        guard isAllowedHost(host, machineHostName: machineHostName) else { return false }
        if let origin = request.header("origin") { return isSameOrigin(origin, host: host) }
        return true
    }
}
