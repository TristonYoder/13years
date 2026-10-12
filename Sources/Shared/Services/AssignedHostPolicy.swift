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
