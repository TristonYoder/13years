// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum RemoteLANMode: String, CaseIterable, Sendable {
    case controlOnly
    case introducer
    case localRelay

    public static let defaultsKey = "remoteLANMode"

    public var displayName: String {
        switch self {
        case .controlOnly: return "Control Only"
        case .introducer: return "Introducer"
        case .localRelay: return "Local Relay"
        }
    }

    public var summary: String {
        switch self {
        case .controlOnly:
            return "This Producer only controls the clock; pagers on this network are not served."
        case .introducer:
            return "Advertises the clock server on this network so pagers connect to it directly (the server must be reachable from this network)."
        case .localRelay:
            return "Pagers on this network connect to this Producer, which relays their feed to and from the clock server."
        }
    }

    public static func stored(in defaults: UserDefaults = .standard) -> RemoteLANMode {
        defaults.string(forKey: defaultsKey).flatMap(RemoteLANMode.init(rawValue:)) ?? .controlOnly
    }

    public static func store(_ mode: RemoteLANMode, in defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: defaultsKey)
    }
}
