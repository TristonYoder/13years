// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

@MainActor
public protocol RemoteProducerCommanding: AnyObject {
    func send(_ command: RemoteCommand)
    func request(_ command: RemoteCommand) async throws -> Data
    var assignContext: RemoteAssignContext? { get }
}

public extension RemoteProducerCommanding {
    var assignContext: RemoteAssignContext? { nil }
}

public enum RemoteCommand: Equatable, Sendable {
    case cueSelected(CueState)
    case cueRole(id: String, state: CueState)
    case clearCues
    case select(roleIds: [String])
    case timerStart
    case timerPause
    case timerReset
    case timerAdjust(seconds: Int)
    case timerRemaining(seconds: Int)
    case timerActualOverride(Bool)
    case planNext(startTimer: Bool)
    case planPrevious(startTimer: Bool)
    case planActivate(itemId: String)
    case planNextService
    case planItemAdd(title: String, itemType: String, lengthInSeconds: Int, isDurationActual: Bool)
    case planItemUpdate(id: String, body: Data)
    case planItemRemove(id: String)
    case planReorder(itemIds: [String])
    case planImport(text: String, title: String?)
    case itemDurationActual(itemId: String, isActual: Bool)
    case itemWaypoints(itemId: String, waypointIds: [String])
    case waypointCreate(name: String)
    case waypointCreateAndAssign(name: String, itemId: String)
    case waypointRename(ref: String, name: String)
    case waypointDelete(ref: String)
    case waypointAssign(ref: String, itemId: String?)
    case waypointGo(ref: String, startTimer: Bool)
    case waypointNext(startTimer: Bool)
    case roleCreate(name: String)
    case roleUpdate(id: String, body: Data)
    case roleDelete(id: String)
    case scheduleCreate(body: Data)
    case scheduleUpdate(id: String, body: Data)
    case scheduleDelete(id: String)
    case scheduleGoLive(id: String)
    case message(text: String, targetRoleId: String?, senderRoleId: String?, isHighPriority: Bool)
    case dismissNotification
    case clearMessages
    case pcoSync(serviceTypeId: String, planId: String)
    case pcoSelectServiceType(id: String?)
    case pcoRefreshServiceTypes
    case pcoSignOut
    case pcoAuthorize
    case pcoAuthorizeComplete(code: String, state: String)
    case pcoRefreshPlans
    case pcoPlanFilter(String)
    case pcoDefaultServiceType(id: String?)
    case pcoLiveSync(Bool)
    case pcoChangesAccept(revision: String?)
    case pcoChangesDismiss(revision: String?)
    case pcoChangesCheck
    case pcoPlanContextRefresh
    case eventTimeCreate(name: String?, day: String?, startTime: String?)
    case eventTimeUpdate(id: String, name: String, day: String, startTime: String)
    case eventTimeDelete(id: String)
    case eventTimeLive(id: String)
    case eventTimeNext
    case loadDocument(body: Data)
    case hourFormat(String)
    case clockFormat(String)

    public var isIdempotent: Bool {
        switch self {
        case .planNext, .planPrevious, .timerAdjust, .message, .roleCreate, .scheduleCreate, .planItemAdd,
             .waypointCreate, .waypointCreateAndAssign, .waypointNext, .planNextService, .eventTimeCreate, .eventTimeNext, .planImport, .loadDocument:
            return false
        default:
            return true
        }
    }

    public struct Request: Equatable, Sendable {
        public var method: String
        public var path: String
        public var body: Data?
    }

    public var request: Request {
        switch self {
        case .cueSelected(let state):
            return Self.post("cues/selected", ["state": state.rawValue])
        case .cueRole(let id, let state):
            return Self.post("roles/\(Self.segment(id))/cue", ["state": state.rawValue])
        case .clearCues:
            return Self.post("cues/clear")
        case .select(let roleIds):
            return Request(method: "PUT", path: "/v1/selection", body: Self.json(["roleIds": roleIds]))
        case .timerStart:
            return Self.post("timer/start")
        case .timerPause:
            return Self.post("timer/pause")
        case .timerReset:
            return Self.post("timer/reset")
        case .timerAdjust(let seconds):
            return Self.post("timer/adjust", ["seconds": seconds])
        case .timerRemaining(let seconds):
            return Self.post("timer/remaining", ["seconds": seconds])
        case .timerActualOverride(let isActual):
            return Self.post("timer/actual-override", ["isActual": isActual])
        case .planNext(let startTimer):
            return Self.post("plan/next", ["startTimer": startTimer])
        case .planPrevious(let startTimer):
            return Self.post("plan/previous", ["startTimer": startTimer])
        case .planActivate(let itemId):
            return Self.post("plan/active", ["itemId": itemId])
        case .planNextService:
            return Self.post("plan/next-service")
        case .planItemAdd(let title, let itemType, let length, let isActual):
            return Self.post("plan/items", ["title": title, "itemType": itemType, "lengthInSeconds": length, "isDurationActual": isActual])
        case .planItemUpdate(let id, let body):
            return Request(method: "POST", path: "/v1/plan/items/\(Self.segment(id))", body: body)
        case .planItemRemove(let id):
            return Request(method: "DELETE", path: "/v1/plan/items/\(Self.segment(id))", body: nil)
        case .planReorder(let itemIds):
            return Self.post("plan/items/reorder", ["itemIds": itemIds])
        case .planImport(let text, let title):
            var fields: [String: Any] = ["text": text]
            if let title { fields["title"] = title }
            return Self.post("plan/import", fields)
        case .itemDurationActual(let itemId, let isActual):
            return Self.post("plan/items/\(Self.segment(itemId))/duration-actual", ["isActual": isActual])
        case .itemWaypoints(let itemId, let waypointIds):
            return Self.post("plan/items/\(Self.segment(itemId))/waypoints", ["waypoints": waypointIds])
        case .waypointCreate(let name), .waypointCreateAndAssign(let name, _):
            return Self.post("waypoints", ["name": name])
        case .waypointRename(let ref, let name):
            return Request(method: "PATCH", path: "/v1/waypoints/\(Self.segment(ref))", body: Self.json(["name": name]))
        case .waypointDelete(let ref):
            return Request(method: "DELETE", path: "/v1/waypoints/\(Self.segment(ref))", body: nil)
        case .waypointAssign(let ref, let itemId):
            return Self.post("waypoints/\(Self.segment(ref))/assign", itemId.map { ["itemId": $0] } ?? [:])
        case .waypointGo(let ref, let startTimer):
            return Self.post("waypoints/\(Self.segment(ref))/go", ["startTimer": startTimer])
        case .waypointNext(let startTimer):
            return Self.post("waypoints/next", ["startTimer": startTimer])
        case .roleCreate(let name):
            return Self.post("roles", ["name": name])
        case .roleUpdate(let id, let body):
            return Request(method: "PATCH", path: "/v1/roles/\(Self.segment(id))", body: body)
        case .roleDelete(let id):
            return Request(method: "DELETE", path: "/v1/roles/\(Self.segment(id))", body: nil)
        case .scheduleCreate(let body):
            return Request(method: "POST", path: "/v1/schedules", body: body)
        case .scheduleUpdate(let id, let body):
            return Request(method: "PATCH", path: "/v1/schedules/\(Self.segment(id))", body: body)
        case .scheduleDelete(let id):
            return Request(method: "DELETE", path: "/v1/schedules/\(Self.segment(id))", body: nil)
        case .scheduleGoLive(let id):
            return Self.post("schedules/\(Self.segment(id))/go-live")
        case .message(let text, let targetRoleId, let senderRoleId, let isHighPriority):
            var fields: [String: Any] = ["text": text, "isHighPriority": isHighPriority]
            if let targetRoleId { fields["targetRoleId"] = targetRoleId }
            if let senderRoleId { fields["senderRoleId"] = senderRoleId }
            return Self.post("messages", fields)
        case .dismissNotification:
            return Self.post("messages/dismiss")
        case .clearMessages:
            return Request(method: "DELETE", path: "/v1/messages", body: nil)
        case .pcoSync(let serviceTypeId, let planId):
            return Self.post("pco/sync", ["serviceTypeId": serviceTypeId, "planId": planId])
        case .pcoSelectServiceType(let id):
            return Self.post("pco/service-type", ["id": id ?? NSNull()])
        case .pcoSignOut:
            return Self.post("pco/sign-out")
        case .pcoAuthorize:
            return Self.post("pco/authorize")
        case .pcoAuthorizeComplete(let code, let state):
            return Self.post("pco/authorize/complete", ["code": code, "state": state])
        case .pcoRefreshServiceTypes:
            return Self.post("pco/service-types/refresh")
        case .pcoRefreshPlans:
            return Self.post("pco/plans/refresh")
        case .pcoPlanFilter(let filter):
            return Self.post("pco/plan-filter", ["filter": filter])
        case .pcoDefaultServiceType(let id):
            return Self.post("pco/default-service-type", ["id": id ?? NSNull()])
        case .pcoLiveSync(let enabled):
            return Self.post("pco/live-sync", ["enabled": enabled])
        case .pcoChangesAccept(let revision):
            return Self.post("pco/changes/accept", ["revision": revision ?? NSNull()])
        case .pcoChangesDismiss(let revision):
            return Self.post("pco/changes/dismiss", ["revision": revision ?? NSNull()])
        case .pcoPlanContextRefresh:
            return Self.post("pco/plan-context/refresh")
        case .pcoChangesCheck:
            return Self.post("pco/changes/check")
        case .eventTimeCreate(let name, let day, let startTime):
            return Self.post("event-times", ["name": name ?? NSNull(), "day": day ?? NSNull(), "startTime": startTime ?? NSNull()])
        case .eventTimeUpdate(let id, let name, let day, let startTime):
            return Request(method: "PATCH", path: "/v1/event-times/\(Self.segment(id))", body: Self.json(["name": name, "day": day, "startTime": startTime]))
        case .eventTimeDelete(let id):
            return Request(method: "DELETE", path: "/v1/event-times/\(Self.segment(id))", body: nil)
        case .eventTimeLive(let id):
            return Self.post("event-times/live", ["id": id])
        case .eventTimeNext:
            return Self.post("event-times/next")
        case .loadDocument(let body):
            return Request(method: "PUT", path: "/v1/document", body: body)
        case .hourFormat(let raw):
            return Request(method: "PUT", path: "/v1/settings", body: Self.json(["hourFormatThreshold": raw]))
        case .clockFormat(let raw):
            return Request(method: "PUT", path: "/v1/settings", body: Self.json(["clockFormat": raw]))
        }
    }

    public static func body(_ fields: [String: Any]) -> Data {
        json(fields)
    }

    private static func post(_ path: String, _ fields: [String: Any]? = nil) -> Request {
        Request(method: "POST", path: "/v1/" + path, body: fields.map(json))
    }

    private static func json(_ fields: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])) ?? Data()
    }

    private static let segmentAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func segment(_ raw: String) -> String {
        raw.addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? raw
    }
}
