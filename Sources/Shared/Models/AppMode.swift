// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
import SwiftUI

public enum AppMode: String, Codable, CaseIterable, Sendable, Hashable {
    case producerControl = "PRODUCER_CONTROL"
    case serviceFlow = "SERVICE_FLOW"
    case livePreview = "LIVE_PREVIEW"
    case messages = "MESSAGES"
    case settings = "SETTINGS"

    public var displayName: String {
        switch self {
        case .producerControl: return "Pagers"
        case .serviceFlow: return "Service Flow"
        case .livePreview: return "Live Preview"
        case .messages: return "Messages"
        case .settings: return "Settings"
        }
    }

    public enum SymbolName: Sendable, Hashable {
        case system(String)
        case custom(String)
    }

    public var icon: Image {
        switch symbolName {
        case let .system(name): return Image(systemName: name)
        case let .custom(name): return Image(name)
        }
    }

    public var symbolName: SymbolName {
        switch self {
        case .producerControl: return .custom("stoplight")
        case .serviceFlow: return .system("list.bullet.rectangle")
        case .livePreview: return .system("iphone.gen3")
        case .messages: return .system("message.fill")
        case .settings: return .system("gearshape")
        }
    }
}
