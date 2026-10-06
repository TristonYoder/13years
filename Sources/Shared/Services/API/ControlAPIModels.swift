// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum ControlAPIJSON {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public struct ControlAPIState: Codable, Sendable {
    public var appMode: String
    public var network: NetworkStatus
    public var roles: [RoleCue]
    public var selectedRoleIds: [String]
    public var timer: ActiveTimer?
    public var plan: PlanStatus
    public var messages: [InterTeamMessage]
    public var notificationsClearedAt: Date?
    public var pco: PCOStatus
    public var plotiphar: PlotipharStatus
    public var settings: SettingsStatus
    public var waypoints: [WaypointStatus]
    public var schedules: ScheduleStatus

    public struct NetworkStatus: Codable, Sendable {
        public var isMasterServer: Bool
        public var isLANConnected: Bool
        public var isProducerLive: Bool
        public var hasSyncedWithProducer: Bool
        public var connectedMasterName: String?
        public var lanPort: Int
        public var relayEnabled: Bool
        public var relayHost: String
    }

    public struct ActiveTimer: Codable, Sendable {
        public var item: PCOTimerItem
        public var index: Int
        public var isRunning: Bool
        public var remainingSeconds: Int
        public var isOvertime: Bool
        public var formattedRemaining: String
        public var isDurationActualForDisplay: Bool
    }

    public struct PlanStatus: Codable, Sendable {
        public var title: String?
        public var items: [PCOTimerItem]
        public var activeItemIndex: Int
        public var isAtEndOfPlan: Bool
        public var canLoadNextService: Bool
        public var pcoServiceTypeId: String?
        public var pcoPlanId: String?
    }

    public struct PCOStatus: Codable, Sendable {
        public var isConnected: Bool
        public var userName: String?
        public var isLiveSyncEnabled: Bool
        public var lastError: String?
        public var selectedServiceTypeId: String?
        public var defaultServiceTypeId: String?
        public var planFilter: String
        public var serviceTypes: [IdentifiedName]
        public var plans: [PlanInfo]
        public var noteCategories: [IdentifiedName]

        public struct PlanInfo: Codable, Sendable {
            public var id: String
            public var title: String
            public var dates: String?
        }
    }

    public struct PlotipharStatus: Codable, Sendable {
        public var pairingState: String
        public var pairingCode: String?
        public var pairingExpiresAt: Date?
        public var pairingError: String?
        public var assignmentSyncStatus: String
        public var assignmentSyncEventId: String?
        public var assignmentSyncError: String?
        public var roles: [IdentifiedName]
    }

    public struct SettingsStatus: Codable, Sendable {
        public var hourFormatThreshold: String
        public var controlAPIPort: Int
        public var connectedAPIClients: Int
    }

    public struct IdentifiedName: Codable, Sendable {
        public var id: String
        public var name: String
    }

    public struct WaypointStatus: Codable, Sendable {
        public var id: String
        public var name: String
        public var slug: String
        public var itemId: String?
        public var itemTitle: String?
        public var itemIndex: Int?
    }

    public struct ScheduleStatus: Codable, Sendable {
        public var entries: [Entry]
        public var nextId: String?

        public struct Entry: Codable, Sendable {
            public var id: String
            public var title: String
            public var startsAt: Date
            public var goLiveAt: Date
            public var goLiveOffsetSeconds: Int
            public var goLiveOffsetMinutes: Int
            public var pcoServiceTypeId: String?
            public var pcoPlanId: String?
            public var recurrence: String
            public var isEnabled: Bool
            public var lastFiredAt: Date?
        }
    }
}

public struct ControlAPIEvent<Payload: Encodable>: Encodable {
    public var event: String
    public var data: Payload

    public init(event: String, data: Payload) {
        self.event = event
        self.data = data
    }
}

public struct ControlAPICommand: Decodable, Sendable {
    public var id: String?
    public var op: String
    public var body: Data?

    private enum CodingKeys: String, CodingKey { case id, op, body }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        op = try container.decode(String.self, forKey: .op)
        if container.contains(.body) {
            let raw = try container.decode(AnyJSON.self, forKey: .body)
            body = try? JSONEncoder().encode(raw)
        } else {
            body = nil
        }
    }
}

public struct ControlAPICommandReply: Encodable, Sendable {
    public var id: String?
    public var status: Int
    public var data: AnyJSON?
    public var error: String?

    public init(id: String?, status: Int, data: AnyJSON? = nil, error: String? = nil) {
        self.id = id
        self.status = status
        self.data = data
        self.error = error
    }
}

public enum AnyJSON: Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AnyJSON].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AnyJSON].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

public struct ControlAPIErrorBody: Encodable, Sendable {
    public var error: String
    public var detail: String?

    public init(error: String, detail: String? = nil) {
        self.error = error
        self.detail = detail
    }
}

public enum ControlAPIRequests {
    public struct CueBody: Decodable, Sendable {
        public var state: String
    }

    public struct SelectionBody: Decodable, Sendable {
        public var roleIds: [String]
    }

    public struct RoleCreateBody: Decodable, Sendable {
        public var name: String
    }

    public struct RoleUpdateBody: Decodable, Sendable {
        public var name: String?
        public var personName: String?
        public var plotipharRoleId: String?
        public var assignedNoteCategories: [String]?
        public var state: String?
    }

    public struct TimerAdjustBody: Decodable, Sendable {
        public var seconds: Int
    }

    public struct TimerRemainingBody: Decodable, Sendable {
        public var seconds: Int?
        public var input: String?
    }

    public struct FlagBody: Decodable, Sendable {
        public var isActual: Bool?
        public var enabled: Bool?
        public var isMaster: Bool?
    }

    public struct PlanActiveBody: Decodable, Sendable {
        public var itemId: String
    }

    public struct PlanItemCreateBody: Decodable, Sendable {
        public var title: String
        public var itemType: String?
        public var lengthInSeconds: Int?
        public var isDurationActual: Bool?
    }

    public struct PlanItemUpdateBody: Decodable, Sendable {
        public var title: String?
        public var itemType: String?
        public var lengthInSeconds: Int?
        public var notes: [String: String]?
        public var isDurationActual: Bool?
    }

    public struct PlanReorderBody: Decodable, Sendable {
        public var itemIds: [String]
    }

    public struct PlanImportBody: Decodable, Sendable {
        public var text: String
        public var title: String?
    }

    public struct PCOSyncBody: Decodable, Sendable {
        public var serviceTypeId: String
        public var planId: String
    }

    public struct IdBody: Decodable, Sendable {
        public var id: String?
    }

    public struct PlanFilterBody: Decodable, Sendable {
        public var filter: String
    }

    public struct MessageBody: Codable, Sendable {
        public var text: String
        public var targetRoleId: String?
        public var senderRoleId: String?
        public var isHighPriority: Bool?
    }

    public struct RelayBody: Decodable, Sendable {
        public var enabled: Bool?
        public var host: String?
    }

    public struct PingBody: Decodable, Sendable {
        public var ip: String
    }

    public struct SettingsBody: Decodable, Sendable {
        public var hourFormatThreshold: String?
    }

    public struct ModeBody: Decodable, Sendable {
        public var mode: String
    }

    public struct WaypointCreateBody: Decodable, Sendable {
        public var name: String
    }

    public struct WaypointUpdateBody: Decodable, Sendable {
        public var name: String?
    }

    public struct WaypointAssignBody: Decodable, Sendable {
        public var itemId: String?
    }

    public struct WaypointFireBody: Decodable, Sendable {
        public var startTimer: Bool?
    }

    public struct PlanItemWaypointsBody: Decodable, Sendable {
        public var waypoints: [String]
    }

    public struct ScheduleCreateBody: Decodable, Sendable {
        public var title: String
        public var startsAt: Date
        public var goLiveOffsetSeconds: Int?
        public var goLiveOffsetMinutes: Int?
        public var pcoServiceTypeId: String?
        public var pcoPlanId: String?
        public var recurrence: String?
        public var isEnabled: Bool?
    }

    public struct ScheduleUpdateBody: Decodable, Sendable {
        public var title: String?
        public var startsAt: Date?
        public var goLiveOffsetSeconds: Int?
        public var goLiveOffsetMinutes: Int?
        public var pcoServiceTypeId: String?
        public var pcoPlanId: String?
        public var recurrence: String?
        public var isEnabled: Bool?
    }
}
