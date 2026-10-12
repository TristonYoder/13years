// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class ControlAPIRouter {
    private unowned let engine: CueEngine
    private let connectedClientCount: @MainActor () -> Int
    private var revision = 0
    private var activeConnection: ControlAPIConnection?
    private var activeReceivedAtMs: Int?

    public init(engine: CueEngine, connectedClientCount: @escaping @MainActor () -> Int = { 0 }) {
        self.engine = engine
        self.connectedClientCount = connectedClientCount
    }

    public func handle(_ request: HTTPRequest, receivedAtMs: Int? = nil) -> HTTPResponse {
        if let response = WebPager.route(request) { return response }
        activeReceivedAtMs = receivedAtMs
        defer { activeReceivedAtMs = nil }

        let segments = request.path.split(separator: "/").map(String.init)
        guard segments.first == "v1" else {
            return Self.error(404, "Unknown path", detail: "Every route lives under /v1, apart from the web pager at \(WebPager.path).")
        }
        return dispatch(method: request.method.uppercased(), route: Array(segments.dropFirst()), body: request.body)
    }

    public func handleCommand(_ command: ControlAPICommand, connection: ControlAPIConnection? = nil, receivedAtMs: Int? = nil) -> ControlAPICommandReply {
        activeConnection = connection
        activeReceivedAtMs = receivedAtMs
        defer {
            activeConnection = nil
            activeReceivedAtMs = nil
        }
        let route = command.op
            .split(whereSeparator: { $0 == "." || $0 == "/" })
            .map(String.init)
            .filter { $0 != "v1" }

        guard !route.isEmpty else {
            return ControlAPICommandReply(id: command.id, status: 400, error: "Missing op")
        }

        let response = dispatch(method: "ANY", route: route, body: command.body ?? Data())
        let payload = try? JSONDecoder().decode(AnyJSON.self, from: response.body)
        if response.status >= 400 {
            var message = "Request failed"
            if case .object(let fields)? = payload, case .string(let text)? = fields["error"] {
                message = text
            }
            return ControlAPICommandReply(id: command.id, status: response.status, data: payload, error: message)
        }
        return ControlAPICommandReply(id: command.id, status: response.status, data: payload)
    }

    private func dispatch(method: String, route: [String], body: Data) -> HTTPResponse {
        switch route.count {
        case 1:
            return dispatchOne(method: method, route[0], body)
        case 2:
            return dispatchTwo(method: method, (route[0], route[1]), body)
        case 3:
            return dispatchThree(method: method, (route[0], route[1], route[2]), body)
        case 4:
            return dispatchFour(method: method, (route[0], route[1], route[2], route[3]), body)
        default:
            return Self.error(404, "Unknown path")
        }
    }

    private func dispatchOne(method: String, _ segment: String, _ body: Data) -> HTTPResponse {
        switch segment {
        case "health":
            guard allows(method, "GET") else { return methodNotAllowed() }
            return json(health())

        case "timer":
            guard allows(method, "GET") else { return methodNotAllowed() }
            return json(timerSnapshot())

        case "state":
            guard allows(method, "GET") else { return methodNotAllowed() }
            return json(snapshot())

        case "sync":
            guard allows(method, "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.SyncBody.self, body) else { return badBody() }
            let receivedAt = activeReceivedAtMs ?? Self.nowMs()
            return json(ControlAPISyncReply(t0: request.t0, t1: receivedAt, t2: Self.nowMs()))

        case "proto":
            guard allows(method, "POST") else { return methodNotAllowed() }
            guard let connection = activeConnection else {
                return Self.error(400, "proto is a WebSocket op", detail: "Send it as {\"op\":\"proto\",\"body\":{\"version\":2}} on /v1/socket.")
            }
            guard let request = decode(ControlAPIRequests.ProtoBody.self, body) else { return badBody() }
            guard ControlAPIConnection.supportedVersions.contains(request.version) else {
                return Self.error(400, "Unsupported protocol version", detail: "Supported: 1, 2")
            }
            connection.protocolVersion = request.version
            return json(["version": request.version])

        case "roles":
            if allows(method, "GET") { return json(engine.roles) }
            guard allows(method, "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.RoleCreateBody.self, body) else { return badBody() }
            let trimmed = request.name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return Self.error(400, "Role name cannot be empty") }
            if let tooLong = tooLong(trimmed, ContentLimits.name, "Role name") { return tooLong }
            guard engine.roles.count < ContentLimits.maxRoles else { return limitReached("roles", ContentLimits.maxRoles) }
            let role = engine.addRole(name: trimmed)
            return json(role, status: 201)

        case "selection":
            if allows(method, "GET") { return json(engine.selectedRoleIds.sorted()) }
            guard allows(method, "PUT", "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.SelectionBody.self, body) else { return badBody() }
            guard request.roleIds.count <= ContentLimits.maxRoles else { return Self.error(400, "Too many role ids", detail: "At most \(ContentLimits.maxRoles).") }
            let known = Set(engine.roles.map(\.id))
            let unknown = request.roleIds.filter { !known.contains($0) }
            guard unknown.isEmpty else {
                return Self.error(404, "Unknown role id", detail: unknown.joined(separator: ", "))
            }
            engine.selectedRoleIds = Set(request.roleIds)
            return json(snapshot())

        case "plan":
            guard allows(method, "GET") else { return methodNotAllowed() }
            return json(planStatus())

        case "messages":
            if allows(method, "GET") { return json(engine.recentMessages) }
            if allows(method, "DELETE") {
                engine.clearMessageHistory()
                return json(engine.recentMessages)
            }
            guard allows(method, "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.MessageBody.self, body) else { return badBody() }
            let text = request.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return Self.error(400, "Message text cannot be empty") }
            if let tooLong = tooLong(text, ContentLimits.messageText, "Message text") { return tooLong }
            if let tooLong = tooLong(request.targetRoleId ?? "", ContentLimits.identifier, "targetRoleId") { return tooLong }
            if let tooLong = tooLong(request.senderRoleId ?? "", ContentLimits.identifier, "senderRoleId") { return tooLong }
            engine.sendMessage(
                text,
                targetRoleId: request.targetRoleId,
                senderRoleId: request.senderRoleId,
                isHighPriority: request.isHighPriority ?? false
            )
            return json(engine.recentMessages, status: 201)

        case "pco":
            guard allows(method, "GET") else { return methodNotAllowed() }
            return json(pcoStatus())

        case "plotiphar":
            guard allows(method, "GET") else { return methodNotAllowed() }
            return json(plotipharStatus())

        case "relay":
            guard allows(method, "PUT", "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.RelayBody.self, body) else { return badBody() }
            if let host = request.host?.trimmingCharacters(in: .whitespaces), !host.isEmpty {
                guard engine.setRelayHost(host) else {
                    return Self.error(400, "Invalid relay host", detail: "Use a hostname or a wss:// or https:// address. Plain ws:// and http:// are not allowed.")
                }
            }
            if let enabled = request.enabled {
                guard !enabled || !engine.proxyToken.isEmpty else {
                    return Self.error(409, "Not paired with Plotiphar", detail: "Start pairing first: POST /v1/plotiphar/pair/start")
                }
                engine.isProxyEnabled = enabled
            }
            return json(snapshot())

        case "settings":
            if allows(method, "GET") { return json(settingsStatus()) }
            guard allows(method, "PUT", "PATCH", "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.SettingsBody.self, body) else { return badBody() }
            if let raw = request.hourFormatThreshold {
                guard let threshold = HourFormatThreshold(rawValue: raw) else {
                    return Self.error(400, "Unknown hourFormatThreshold", detail: HourFormatThreshold.allCases.map(\.rawValue).joined(separator: ", "))
                }
                engine.hourFormatThreshold = threshold
            }
            return json(settingsStatus())

        case "waypoints":
            if allows(method, "GET") { return json(waypointStatuses()) }
            guard allows(method, "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.WaypointCreateBody.self, body) else { return badBody() }
            let trimmed = request.name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return Self.error(400, "Waypoint name cannot be empty") }
            if let tooLong = tooLong(trimmed, ContentLimits.name, "Waypoint name") { return tooLong }
            guard engine.waypoints.count < ContentLimits.maxWaypoints else { return limitReached("waypoints", ContentLimits.maxWaypoints) }
            let slug = Waypoint.slug(for: trimmed)
            if let existing = engine.waypoints.first(where: { $0.slug == slug }) {
                return Self.error(409, "A waypoint with this name already exists", detail: existing.name)
            }
            guard let waypoint = engine.addWaypoint(name: trimmed) else {
                return Self.error(400, "Could not create waypoint", detail: trimmed)
            }
            return json(waypointStatus(for: waypoint), status: 201)

        case "schedules":
            if allows(method, "GET") { return json(scheduleStatus()) }
            guard allows(method, "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.ScheduleCreateBody.self, body) else { return badBody() }
            let title = request.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return Self.error(400, "Schedule title cannot be empty") }
            if let tooLong = tooLong(title, ContentLimits.title, "Schedule title") { return tooLong }
            if let tooLong = tooLong(request.pcoServiceTypeId ?? "", ContentLimits.identifier, "pcoServiceTypeId") { return tooLong }
            if let tooLong = tooLong(request.pcoPlanId ?? "", ContentLimits.identifier, "pcoPlanId") { return tooLong }
            guard engine.serviceSchedules.count < ContentLimits.maxSchedules else { return limitReached("schedules", ContentLimits.maxSchedules) }
            let offsetSeconds: Int
            if let minutes = request.goLiveOffsetMinutes {
                guard let seconds = Self.offsetSeconds(fromMinutes: minutes) else { return offsetOutOfRange() }
                offsetSeconds = seconds
            } else if let seconds = request.goLiveOffsetSeconds {
                guard TimerLimits.isValidLength(seconds) else { return offsetOutOfRange() }
                offsetSeconds = seconds
            } else {
                offsetSeconds = 30 * 60
            }
            let recurrence: ServiceSchedule.Recurrence
            if let raw = request.recurrence {
                guard let parsed = Self.recurrence(raw) else {
                    return Self.error(400, "Unknown recurrence", detail: ServiceSchedule.Recurrence.allCases.map(\.rawValue).joined(separator: ", "))
                }
                recurrence = parsed
            } else {
                recurrence = .once
            }
            guard let schedule = engine.addServiceSchedule(
                title: title,
                startsAt: request.startsAt,
                goLiveOffsetSeconds: offsetSeconds,
                pcoServiceTypeId: request.pcoServiceTypeId,
                pcoPlanId: request.pcoPlanId,
                recurrence: recurrence,
                isEnabled: request.isEnabled ?? true
            ) else {
                return Self.error(400, "Could not create schedule", detail: "Title must be non-empty and the lead time must not be negative.")
            }
            return json(scheduleEntry(schedule), status: 201)

        default:
            return Self.error(404, "Unknown path")
        }
    }

    private func dispatchTwo(method: String, _ route: (String, String), _ body: Data) -> HTTPResponse {
        switch route {
        case ("cues", "selected"):
            guard allows(method, "POST", "PUT") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.CueBody.self, body) else { return badBody() }
            guard let state = Self.cueState(request.state) else { return unknownCueState() }
            guard engine.roles.contains(where: { engine.selectedRoleIds.contains($0.id) }) else {
                return Self.error(409, "No roles are selected", detail: "Set the selection first: PUT /v1/selection {\"roleIds\": [...]}")
            }
            engine.setCueForSelectedRoles(state)
            return json(snapshot())

        case ("cues", "clear"):
            guard allows(method, "POST", "DELETE") else { return methodNotAllowed() }
            engine.clearAllCues()
            return json(snapshot())

        case ("messages", "dismiss"):
            guard allows(method, "POST", "DELETE") else { return methodNotAllowed() }
            engine.clearActiveNotification()
            return json(snapshot())

        case ("timer", "start"), ("timer", "pause"), ("timer", "toggle"):
            guard allows(method, "POST") else { return methodNotAllowed() }
            guard let item = engine.activeTimerItem else { return noActiveItem() }
            let shouldRun: Bool
            switch route.1 {
            case "start": shouldRun = true
            case "pause": shouldRun = false
            default: shouldRun = !item.isRunning
            }
            if item.isRunning != shouldRun {
                engine.toggleTimerRunning()
            }
            return json(snapshot())

        case ("timer", "reset"):
            guard allows(method, "POST") else { return methodNotAllowed() }
            guard engine.activeTimerItem != nil else { return noActiveItem() }
            engine.resetTimer()
            return json(snapshot())

        case ("timer", "adjust"):
            guard allows(method, "POST") else { return methodNotAllowed() }
            guard engine.activeTimerItem != nil else { return noActiveItem() }
            guard let request = decode(ControlAPIRequests.TimerAdjustBody.self, body) else { return badBody() }
            guard TimerLimits.isValidDelta(request.seconds) else {
                return Self.error(400, "seconds out of range", detail: "Between -\(TimerLimits.maxSeconds) and \(TimerLimits.maxSeconds).")
            }
            engine.adjustTimerRemainingTime(bySeconds: request.seconds)
            return json(snapshot())

        case ("timer", "remaining"):
            guard allows(method, "PUT", "POST") else { return methodNotAllowed() }
            guard engine.activeTimerItem != nil else { return noActiveItem() }
            guard let request = decode(ControlAPIRequests.TimerRemainingBody.self, body) else { return badBody() }
            if let input = request.input {
                guard let action = TimerInputParser.parse(input) else {
                    return Self.error(400, "Could not parse time input", detail: input)
                }
                switch action {
                case .setAbsolute(let seconds):
                    engine.setTimerRemainingTime(seconds: seconds)
                case .adjustRelative(let delta):
                    engine.adjustTimerRemainingTime(bySeconds: delta)
                }
            } else if let seconds = request.seconds {
                guard TimerLimits.isValidLength(seconds) else {
                    return Self.error(400, "seconds out of range", detail: "Between 0 and \(TimerLimits.maxSeconds).")
                }
                engine.setTimerRemainingTime(seconds: seconds)
            } else {
                return Self.error(400, "Provide either seconds or input")
            }
            return json(snapshot())

        case ("timer", "actual-override"):
            guard allows(method, "POST", "PUT") else { return methodNotAllowed() }
            guard engine.activeTimerItem != nil else { return noActiveItem() }
            guard let request = decode(ControlAPIRequests.FlagBody.self, body), let isActual = request.isActual else { return badBody() }
            engine.setActiveTimerActualOverride(isActual)
            return json(snapshot())

        case ("plan", "next"):
            guard allows(method, "POST") else { return methodNotAllowed() }
            engine.nextPlanItem(startTimer: decode(ControlAPIRequests.PlanStepBody.self, body)?.startTimer ?? true)
            return json(snapshot())

        case ("plan", "previous"):
            guard allows(method, "POST") else { return methodNotAllowed() }
            engine.previousPlanItem(startTimer: decode(ControlAPIRequests.PlanStepBody.self, body)?.startTimer ?? true)
            return json(snapshot())

        case ("plan", "next-service"):
            guard allows(method, "POST") else { return methodNotAllowed() }
            guard engine.canLoadNextService else {
                return Self.error(409, "No Planning Center plan is loaded", detail: "Only a PCO-synced flow knows what service comes next.")
            }
            engine.loadNextService()
            return accepted()

        case ("plan", "active"):
            if allows(method, "GET") {
                guard let timer = activeTimer() else { return noActiveItem() }
                return json(timer)
            }
            guard allows(method, "POST", "PUT") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.PlanActiveBody.self, body) else { return badBody() }
            guard engine.planItems.contains(where: { $0.id == request.itemId }) else {
                return Self.error(404, "Unknown plan item id", detail: request.itemId)
            }
            engine.setActivePlanItem(id: request.itemId)
            return json(snapshot())

        case ("plan", "items"):
            guard allows(method, "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.PlanItemCreateBody.self, body) else { return badBody() }
            let title = request.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return Self.error(400, "Item title cannot be empty") }
            if let tooLong = tooLong(title, ContentLimits.title, "Item title") { return tooLong }
            if let tooLong = tooLong(request.itemType ?? "", ContentLimits.name, "itemType") { return tooLong }
            let length = request.lengthInSeconds ?? 300
            guard TimerLimits.isValidLength(length) else { return lengthOutOfRange() }
            guard engine.planItems.count < ContentLimits.maxPlanItems else { return limitReached("plan items", ContentLimits.maxPlanItems) }
            engine.addPlanItem(
                title: title,
                itemType: request.itemType ?? "Item",
                lengthInSeconds: length,
                isDurationActual: request.isDurationActual ?? false
            )
            return json(planStatus(), status: 201)

        case ("plan", "import"):
            guard allows(method, "POST", "PUT") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.PlanImportBody.self, body) else { return badBody() }
            let items = ServiceFlowImporter.parse(request.text)
            guard !items.isEmpty else {
                return Self.error(400, "Nothing to import", detail: "Expected one item per line: Title | Type | Duration")
            }
            guard items.count <= ContentLimits.maxPlanItems else { return limitReached("plan items", ContentLimits.maxPlanItems) }
            if items.contains(where: { $0.title.count > ContentLimits.title || $0.itemType.count > ContentLimits.name }) {
                return Self.error(400, "An imported title or type is too long", detail: "Titles: \(ContentLimits.title) characters, types: \(ContentLimits.name).")
            }
            if let tooLong = tooLong(request.title ?? "", ContentLimits.title, "Plan title") { return tooLong }
            engine.importFlow(title: request.title, items: items)
            return json(planStatus(), status: 201)

        case ("pco", "sign-in"):
            guard allows(method, "POST") else { return methodNotAllowed() }
            engine.signInWithPCO()
            return accepted()

        case ("pco", "sign-out"):
            guard allows(method, "POST", "DELETE") else { return methodNotAllowed() }
            engine.signOutOfPCO()
            return json(pcoStatus())

        case ("pco", "service-types"):
            guard allows(method, "GET") else { return methodNotAllowed() }
            return json(engine.pcoServiceTypes.map { ControlAPIState.IdentifiedName(id: $0.id, name: $0.name) })

        case ("pco", "service-type"):
            guard allows(method, "PUT", "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.IdBody.self, body) else { return badBody() }
            if let id = request.id, !id.isEmpty {
                engine.selectPCOServiceType(id)
            } else {
                engine.clearPCOServiceTypeSelection()
            }
            return accepted(pcoStatus())

        case ("pco", "default-service-type"):
            guard allows(method, "PUT", "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.IdBody.self, body) else { return badBody() }
            engine.setDefaultServiceType(request.id)
            return json(pcoStatus())

        case ("pco", "plans"):
            guard allows(method, "GET") else { return methodNotAllowed() }
            return json(engine.pcoPlans.map { ControlAPIState.PCOStatus.PlanInfo(id: $0.id, title: $0.title, dates: $0.dates) })

        case ("pco", "plan-filter"):
            guard allows(method, "PUT", "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.PlanFilterBody.self, body) else { return badBody() }
            guard let filter = PCOClient.PCOPlanFilter(rawValue: request.filter) else {
                return Self.error(400, "Unknown plan filter", detail: PCOClient.PCOPlanFilter.allCases.map(\.rawValue).joined(separator: ", "))
            }
            engine.setPlanFilter(filter)
            return accepted(pcoStatus())

        case ("pco", "sync"):
            guard allows(method, "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.PCOSyncBody.self, body) else { return badBody() }
            engine.fetchPCOPlan(serviceTypeId: request.serviceTypeId, planId: request.planId)
            return accepted()

        case ("pco", "live-sync"):
            guard allows(method, "PUT", "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.FlagBody.self, body), let enabled = request.enabled else { return badBody() }
            if enabled {
                engine.enablePCOLiveSync()
            } else {
                engine.disablePCOLiveSync()
            }
            return accepted(pcoStatus())

        case ("plotiphar", "disconnect"):
            guard allows(method, "POST", "DELETE") else { return methodNotAllowed() }
            engine.disconnectPlotiphar()
            return json(plotipharStatus())

        case ("network", "ping"):
            guard allows(method, "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.PingBody.self, body) else { return badBody() }
            let ip = request.ip.trimmingCharacters(in: .whitespaces)
            guard !ip.isEmpty else { return Self.error(400, "Provide an IP address") }
            guard AssignedHostPolicy.isAcceptable(ip) else {
                return Self.error(400, "Not a local address", detail: "Use a private, link-local or loopback IPv4 address, or a .local name.")
            }
            guard engine.pingDevice(atIP: ip) else {
                return Self.error(503, "Could not determine this device's own LAN address")
            }
            return accepted()

        case ("network", "forget-producer"):
            guard allows(method, "POST", "DELETE") else { return methodNotAllowed() }
            engine.forgetAssignedProducer()
            return json(snapshot())

        case ("network", "master"):
            guard allows(method, "PUT", "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.FlagBody.self, body), let isMaster = request.isMaster else { return badBody() }
            if engine.isMasterServer != isMaster {
                engine.toggleMasterMode()
            }
            return json(snapshot())

        case ("ui", "mode"):
            if allows(method, "GET") { return json(["mode": engine.appMode.rawValue]) }
            guard allows(method, "PUT", "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.ModeBody.self, body) else { return badBody() }
            guard let mode = Self.appMode(request.mode) else {
                return Self.error(400, "Unknown mode", detail: AppMode.allCases.map(\.rawValue).joined(separator: ", "))
            }
            engine.appMode = mode
            return json(["mode": mode.rawValue])

        case ("roles", let roleId):
            guard let index = engine.roles.firstIndex(where: { $0.id == roleId }) else {
                return Self.error(404, "Unknown role id", detail: roleId)
            }
            if allows(method, "GET") { return json(engine.roles[index]) }
            if allows(method, "DELETE") {
                engine.removeRole(id: roleId)
                return json(engine.roles)
            }
            guard allows(method, "PATCH", "PUT", "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.RoleUpdateBody.self, body) else { return badBody() }
            return updateRole(id: roleId, with: request)

        case ("waypoints", "next") where method == "POST":
            let startTimer = decode(ControlAPIRequests.WaypointFireBody.self, body)?.startTimer ?? true
            guard engine.fireNextWaypoint(startTimer: startTimer) != nil else {
                return Self.error(409, "No waypoint ahead of the active item")
            }
            return json(snapshot())

        case ("waypoints", let waypointRef):
            guard let waypoint = engine.waypoint(matching: waypointRef) else {
                return Self.error(404, "Unknown waypoint", detail: waypointRef)
            }
            if allows(method, "GET") { return json(waypointStatus(for: waypoint)) }
            if allows(method, "DELETE") {
                engine.removeWaypoint(id: waypoint.id)
                return json(waypointStatuses())
            }
            guard allows(method, "PATCH", "PUT", "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.WaypointUpdateBody.self, body) else { return badBody() }
            if let name = request.name {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return Self.error(400, "Waypoint name cannot be empty") }
                if let tooLong = tooLong(trimmed, ContentLimits.name, "Waypoint name") { return tooLong }
                let newSlug = Waypoint.slug(for: trimmed)
                if let collision = engine.waypoints.first(where: { $0.id != waypoint.id && $0.slug == newSlug }) {
                    return Self.error(409, "A different waypoint already uses this name", detail: collision.name)
                }
                engine.renameWaypoint(id: waypoint.id, name: trimmed)
            }
            guard let updated = engine.waypoint(matching: waypoint.id) else {
                return Self.error(404, "Unknown waypoint", detail: waypoint.id)
            }
            return json(waypointStatus(for: updated))

        case ("schedules", let scheduleId):
            guard let schedule = engine.serviceSchedule(id: scheduleId) else {
                return Self.error(404, "Unknown schedule id", detail: scheduleId)
            }
            if allows(method, "GET") { return json(scheduleEntry(schedule)) }
            if allows(method, "DELETE") {
                engine.removeServiceSchedule(id: scheduleId)
                return json(scheduleStatus())
            }
            guard allows(method, "PATCH", "PUT", "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.ScheduleUpdateBody.self, body) else { return badBody() }
            if let title = request.title, let tooLong = tooLong(title, ContentLimits.title, "Schedule title") { return tooLong }
            if let tooLong = tooLong(request.pcoServiceTypeId ?? "", ContentLimits.identifier, "pcoServiceTypeId") { return tooLong }
            if let tooLong = tooLong(request.pcoPlanId ?? "", ContentLimits.identifier, "pcoPlanId") { return tooLong }
            var offsetSeconds: Int?
            if let minutes = request.goLiveOffsetMinutes {
                guard let seconds = Self.offsetSeconds(fromMinutes: minutes) else { return offsetOutOfRange() }
                offsetSeconds = seconds
            } else if let seconds = request.goLiveOffsetSeconds {
                guard TimerLimits.isValidLength(seconds) else { return offsetOutOfRange() }
                offsetSeconds = seconds
            }
            var recurrence: ServiceSchedule.Recurrence?
            if let raw = request.recurrence {
                guard let parsed = Self.recurrence(raw) else {
                    return Self.error(400, "Unknown recurrence", detail: ServiceSchedule.Recurrence.allCases.map(\.rawValue).joined(separator: ", "))
                }
                recurrence = parsed
            }
            var pcoServiceTypeId: String??
            if let raw = request.pcoServiceTypeId {
                pcoServiceTypeId = raw.isEmpty ? .some(nil) : .some(raw)
            }
            var pcoPlanId: String??
            if let raw = request.pcoPlanId {
                pcoPlanId = raw.isEmpty ? .some(nil) : .some(raw)
            }
            engine.updateServiceSchedule(
                id: scheduleId,
                title: request.title,
                startsAt: request.startsAt,
                goLiveOffsetSeconds: offsetSeconds,
                pcoServiceTypeId: pcoServiceTypeId,
                pcoPlanId: pcoPlanId,
                recurrence: recurrence,
                isEnabled: request.isEnabled
            )
            guard let updated = engine.serviceSchedule(id: scheduleId) else {
                return Self.error(404, "Unknown schedule id", detail: scheduleId)
            }
            return json(scheduleEntry(updated))

        default:
            return Self.error(404, "Unknown path")
        }
    }

    private func dispatchThree(method: String, _ route: (String, String, String), _ body: Data) -> HTTPResponse {
        switch route {
        case ("pco", "service-types", "refresh"):
            guard allows(method, "POST") else { return methodNotAllowed() }
            engine.fetchPCOServiceTypes()
            return accepted()

        case ("pco", "plans", "refresh"):
            guard allows(method, "POST") else { return methodNotAllowed() }
            guard engine.pcoSelectedServiceTypeId != nil else {
                return Self.error(409, "No service type selected", detail: "PUT /v1/pco/service-type first.")
            }
            engine.fetchPCOPlans()
            return accepted()

        case ("plotiphar", "pair", "start"):
            guard allows(method, "POST") else { return methodNotAllowed() }
            engine.startPlotipharPairing()
            return accepted(plotipharStatus())

        case ("plotiphar", "pair", "cancel"):
            guard allows(method, "POST", "DELETE") else { return methodNotAllowed() }
            engine.cancelPlotipharPairing()
            return json(plotipharStatus())

        case ("plotiphar", "assignments", "sync"):
            guard allows(method, "POST") else { return methodNotAllowed() }
            engine.syncPlotipharAssignments()
            return accepted(plotipharStatus())

        case ("plan", "items", "reorder"):
            guard allows(method, "POST", "PUT") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.PlanReorderBody.self, body) else { return badBody() }
            return reorderPlanItems(to: request.itemIds)

        case ("roles", let roleId, "cue"):
            guard allows(method, "POST", "PUT") else { return methodNotAllowed() }
            guard engine.roles.contains(where: { $0.id == roleId }) else {
                return Self.error(404, "Unknown role id", detail: roleId)
            }
            guard let request = decode(ControlAPIRequests.CueBody.self, body) else { return badBody() }
            guard let state = Self.cueState(request.state) else { return unknownCueState() }
            engine.setCueForRole(id: roleId, state: state)
            return json(snapshot())

        case ("plan", "items", let itemId):
            guard engine.planItems.contains(where: { $0.id == itemId }) else {
                return Self.error(404, "Unknown plan item id", detail: itemId)
            }
            if allows(method, "GET") {
                return json(engine.planItems.first(where: { $0.id == itemId }))
            }
            if allows(method, "DELETE") {
                engine.removePlanItem(id: itemId)
                return json(planStatus())
            }
            guard allows(method, "PATCH", "PUT", "POST") else { return methodNotAllowed() }
            guard let request = decode(ControlAPIRequests.PlanItemUpdateBody.self, body) else { return badBody() }
            return updatePlanItem(id: itemId, with: request)

        case ("waypoints", let waypointRef, "go"):
            guard allows(method, "POST") else { return methodNotAllowed() }
            let startTimer = decode(ControlAPIRequests.WaypointFireBody.self, body)?.startTimer ?? true
            switch engine.fireWaypoint(waypointRef, startTimer: startTimer) {
            case .fired:
                return json(snapshot())
            case .unknownWaypoint:
                return Self.error(404, "Unknown waypoint", detail: "\(waypointRef) — see GET /v1/waypoints for the library.")
            case .unassigned(let waypointId):
                return Self.error(409, "Waypoint exists but no item in the current plan carries it", detail: waypointId)
            }

        case ("waypoints", let waypointRef, "assign"):
            guard allows(method, "POST", "PUT") else { return methodNotAllowed() }
            guard let waypoint = engine.waypoint(matching: waypointRef) else {
                return Self.error(404, "Unknown waypoint", detail: waypointRef)
            }
            guard let request = decode(ControlAPIRequests.WaypointAssignBody.self, body) else { return badBody() }
            if let itemId = request.itemId {
                guard engine.planItems.contains(where: { $0.id == itemId }) else {
                    return Self.error(404, "Unknown plan item id", detail: itemId)
                }
                engine.assignWaypoint(waypoint.id, toItemId: itemId)
            } else {
                engine.assignWaypoint(waypoint.id, toItemId: nil)
            }
            guard let updated = engine.waypoint(matching: waypoint.id) else {
                return Self.error(404, "Unknown waypoint", detail: waypoint.id)
            }
            return json(waypointStatus(for: updated))

        case ("schedules", let scheduleId, "go-live"):
            guard allows(method, "POST") else { return methodNotAllowed() }
            guard engine.serviceSchedule(id: scheduleId) != nil else {
                return Self.error(404, "Unknown schedule id", detail: scheduleId)
            }
            engine.goLiveWithSchedule(id: scheduleId)
            return accepted()

        default:
            return Self.error(404, "Unknown path")
        }
    }

    private func dispatchFour(method: String, _ route: (String, String, String, String), _ body: Data) -> HTTPResponse {
        switch route {
        case ("plan", "items", let itemId, "duration-actual"):
            guard allows(method, "POST", "PUT") else { return methodNotAllowed() }
            guard engine.planItems.contains(where: { $0.id == itemId }) else {
                return Self.error(404, "Unknown plan item id", detail: itemId)
            }
            guard let request = decode(ControlAPIRequests.FlagBody.self, body), let isActual = request.isActual else { return badBody() }
            engine.setDurationIsActual(id: itemId, isActual: isActual)
            return json(planStatus())

        case ("plan", "items", let itemId, "waypoints"):
            guard allows(method, "POST", "PUT") else { return methodNotAllowed() }
            guard engine.planItems.contains(where: { $0.id == itemId }) else {
                return Self.error(404, "Unknown plan item id", detail: itemId)
            }
            guard let request = decode(ControlAPIRequests.PlanItemWaypointsBody.self, body) else { return badBody() }
            var resolvedWaypointIds: [String] = []
            for raw in request.waypoints {
                guard let waypoint = engine.waypoint(matching: raw) else {
                    return Self.error(404, "Unknown waypoint", detail: raw)
                }
                resolvedWaypointIds.append(waypoint.id)
            }
            engine.setWaypointIds(resolvedWaypointIds, forItemId: itemId)
            return json(engine.planItems.first(where: { $0.id == itemId }))

        default:
            return Self.error(404, "Unknown path")
        }
    }

    private func updateRole(id: String, with request: ControlAPIRequests.RoleUpdateBody) -> HTTPResponse {
        if let name = request.name, let tooLong = tooLong(name.trimmingCharacters(in: .whitespaces), ContentLimits.name, "Role name") { return tooLong }
        if let tooLong = tooLong(request.personName ?? "", ContentLimits.name, "personName") { return tooLong }
        if let tooLong = tooLong(request.plotipharRoleId ?? "", ContentLimits.identifier, "plotipharRoleId") { return tooLong }
        if let categories = request.assignedNoteCategories {
            guard categories.count <= ContentLimits.maxNoteCategories else {
                return Self.error(400, "Too many note categories", detail: "At most \(ContentLimits.maxNoteCategories).")
            }
            for category in categories {
                if let tooLong = tooLong(category, ContentLimits.identifier, "Note category") { return tooLong }
            }
        }
        if let name = request.name?.trimmingCharacters(in: .whitespaces) {
            guard !name.isEmpty else { return Self.error(400, "Role name cannot be empty") }
            engine.renameRole(id: id, name: name)
        }
        if let personName = request.personName {
            engine.setPersonName(forRoleId: id, personName: personName.isEmpty ? nil : personName)
        }
        if let plotipharRoleId = request.plotipharRoleId {
            engine.setPlotipharRoleId(forRoleId: id, plotipharRoleId: plotipharRoleId.isEmpty ? nil : plotipharRoleId)
        }
        if let categories = request.assignedNoteCategories {
            let current = Set(engine.roles.first(where: { $0.id == id })?.assignedNoteCategories ?? [])
            let desired = Set(categories)
            for category in desired.subtracting(current) {
                engine.setNoteCategory(forRoleId: id, category: category, isOn: true)
            }
            for category in current.subtracting(desired) {
                engine.setNoteCategory(forRoleId: id, category: category, isOn: false)
            }
        }
        if let rawState = request.state {
            guard let state = Self.cueState(rawState) else { return unknownCueState() }
            engine.setCueForRole(id: id, state: state)
        }
        guard let updated = engine.roles.first(where: { $0.id == id }) else {
            return Self.error(404, "Unknown role id", detail: id)
        }
        return json(updated)
    }

    private func updatePlanItem(id: String, with request: ControlAPIRequests.PlanItemUpdateBody) -> HTTPResponse {
        guard let existing = engine.planItems.first(where: { $0.id == id }) else {
            return Self.error(404, "Unknown plan item id", detail: id)
        }
        if let title = request.title {
            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return Self.error(400, "Item title cannot be empty") }
            if let tooLong = tooLong(title, ContentLimits.title, "Item title") { return tooLong }
        }
        if let tooLong = tooLong(request.itemType ?? "", ContentLimits.name, "itemType") { return tooLong }
        if let length = request.lengthInSeconds, !TimerLimits.isValidLength(length) { return lengthOutOfRange() }
        if let notes = request.notes {
            guard notes.count <= ContentLimits.maxNoteCategories else {
                return Self.error(400, "Too many notes", detail: "At most \(ContentLimits.maxNoteCategories) categories.")
            }
            for (key, value) in notes {
                if let tooLong = tooLong(key, ContentLimits.identifier, "Note category") { return tooLong }
                if let tooLong = tooLong(value, ContentLimits.noteValue, "Note value") { return tooLong }
            }
        }
        engine.updatePlanItem(
            id: id,
            title: request.title ?? existing.title,
            itemType: request.itemType ?? existing.itemType,
            lengthInSeconds: request.lengthInSeconds ?? existing.lengthInSeconds,
            notes: request.notes,
            isDurationActual: request.isDurationActual
        )
        return json(engine.planItems.first(where: { $0.id == id }))
    }

    private func reorderPlanItems(to itemIds: [String]) -> HTTPResponse {
        let current = engine.planItems.map(\.id)
        guard Set(itemIds) == Set(current), itemIds.count == current.count else {
            return Self.error(400, "itemIds must list every current plan item exactly once")
        }
        for targetIndex in itemIds.indices {
            guard let sourceIndex = engine.planItems.firstIndex(where: { $0.id == itemIds[targetIndex] }) else { continue }
            guard sourceIndex != targetIndex else { continue }
            engine.movePlanItems(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }
        return json(planStatus())
    }

    public func timerSnapshot() -> ControlAPITimerState {
        revision += 1
        return ControlAPITimerState(rev: revision, serverNowMs: Self.nowMs(), timer: activeTimer(), epoch: engine.syncV2.epoch)
    }

    private static func nowMs() -> Int {
        Int((Date().timeIntervalSince1970 * 1000).rounded())
    }

    public func snapshot() -> ControlAPIState {
        revision += 1
        return makeState(rev: revision, serverNowMs: Self.nowMs(), includeTimer: true)
    }

    func nonTimerFingerprint() -> Int {
        let state = makeState(rev: 0, serverNowMs: 0, includeTimer: false)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(state) else { return Int.random(in: Int.min...Int.max) }
        return data.hashValue
    }

    private func makeState(rev: Int, serverNowMs: Int, includeTimer: Bool) -> ControlAPIState {
        ControlAPIState(
            rev: rev,
            serverNowMs: serverNowMs,
            appMode: engine.appMode.rawValue,
            network: ControlAPIState.NetworkStatus(
                isMasterServer: engine.isMasterServer,
                isLANConnected: engine.isLANConnected,
                isProducerLive: engine.isProducerLive,
                hasSyncedWithProducer: engine.hasSyncedWithProducer,
                connectedMasterName: engine.connectedMasterName,
                lanPort: Int(LANUnicastServer.port),
                relayEnabled: engine.isProxyEnabled,
                relayHost: engine.plotipharRelayHost
            ),
            roles: engine.roles,
            selectedRoleIds: engine.selectedRoleIds.sorted(),
            timer: includeTimer ? activeTimer() : nil,
            plan: planStatus(),
            messages: engine.recentMessages,
            notificationsClearedAt: engine.notificationsClearedAt,
            pco: pcoStatus(),
            plotiphar: plotipharStatus(),
            settings: settingsStatus(),
            waypoints: waypointStatuses(),
            schedules: scheduleStatus(),
            epoch: engine.syncV2.epoch
        )
    }

    private func activeTimer() -> ControlAPIState.ActiveTimer? {
        let anchor = engine.currentAnchor
        guard let item = engine.activeTimerItem else { return nil }
        return ControlAPIState.ActiveTimer(
            item: item,
            index: engine.activeItemIndex,
            isRunning: item.isRunning,
            remainingSeconds: item.remainingSeconds,
            isOvertime: item.isOvertime,
            formattedRemaining: TimeFormatting.string(forSeconds: item.remainingSeconds, threshold: engine.hourFormatThreshold),
            isDurationActualForDisplay: engine.activeTimerActualForDisplay,
            anchor: anchor
        )
    }

    public func digest() -> ControlAPIDigest {
        ControlAPIDigest(
            rev: revision,
            serverNowMs: Self.nowMs(),
            hashes: SyncHash.Hashes(
                roles: SyncHash.roles(engine.roles),
                timer: SyncHash.timer(engine.currentAnchor),
                plan: SyncHash.plan(items: engine.planItems, activeItemIndex: engine.activeItemIndex),
                messages: SyncHash.messages(engine.recentMessages)
            ),
            epoch: engine.syncV2.epoch
        )
    }

    private func planStatus() -> ControlAPIState.PlanStatus {
        ControlAPIState.PlanStatus(
            title: engine.activeTimerItem?.servicePlanTitle ?? engine.planItems.first?.servicePlanTitle,
            items: engine.planItems,
            activeItemIndex: engine.activeItemIndex,
            isAtEndOfPlan: engine.isAtEndOfPlan,
            canLoadNextService: engine.canLoadNextService,
            pcoServiceTypeId: engine.activeTimerItem?.pcoServiceTypeId ?? engine.planItems.first?.pcoServiceTypeId,
            pcoPlanId: engine.activeTimerItem?.pcoPlanId ?? engine.planItems.first?.pcoPlanId
        )
    }

    private func pcoStatus() -> ControlAPIState.PCOStatus {
        ControlAPIState.PCOStatus(
            isConnected: engine.isPCOConnected,
            userName: engine.pcoUserName,
            isLiveSyncEnabled: engine.isPCOLiveSyncEnabled,
            lastError: engine.pcoLastError,
            selectedServiceTypeId: engine.pcoSelectedServiceTypeId,
            defaultServiceTypeId: engine.pcoDefaultServiceTypeId,
            planFilter: engine.pcoPlanFilter.rawValue,
            serviceTypes: engine.pcoServiceTypes.map { ControlAPIState.IdentifiedName(id: $0.id, name: $0.name) },
            plans: engine.pcoPlans.map { ControlAPIState.PCOStatus.PlanInfo(id: $0.id, title: $0.title, dates: $0.dates) },
            noteCategories: engine.pcoNoteCategories.map { ControlAPIState.IdentifiedName(id: $0.id, name: $0.name) }
        )
    }

    private func plotipharStatus() -> ControlAPIState.PlotipharStatus {
        var pairingState = "idle"
        var code: String?
        var expiresAt: Date?
        var pairingError: String?
        switch engine.plotipharPairingState {
        case .idle: pairingState = "idle"
        case .starting: pairingState = "starting"
        case .waitingApproval(let pairingCode, let expiry):
            pairingState = "waitingApproval"
            code = pairingCode
            expiresAt = expiry
        case .approved: pairingState = "approved"
        case .expired: pairingState = "expired"
        case .error(let message):
            pairingState = "error"
            pairingError = message
        }

        var syncStatus = "notSynced"
        var eventId: String?
        var syncError: String?
        switch engine.plotipharAssignmentSyncStatus {
        case .notSynced: syncStatus = "notSynced"
        case .notPaired: syncStatus = "notPaired"
        case .noMatchingEvent: syncStatus = "noMatchingEvent"
        case .synced(let id):
            syncStatus = "synced"
            eventId = id
        case .error(let message):
            syncStatus = "error"
            syncError = message
        }

        return ControlAPIState.PlotipharStatus(
            pairingState: pairingState,
            pairingCode: code,
            pairingExpiresAt: expiresAt,
            pairingError: pairingError,
            assignmentSyncStatus: syncStatus,
            assignmentSyncEventId: eventId,
            assignmentSyncError: syncError,
            roles: engine.plotipharRoles.map { ControlAPIState.IdentifiedName(id: $0.id, name: $0.name) }
        )
    }

    private func waypointStatus(for waypoint: Waypoint) -> ControlAPIState.WaypointStatus {
        let itemId = engine.itemId(forWaypointId: waypoint.id)
        let itemIndex = itemId.flatMap { id in engine.planItems.firstIndex(where: { $0.id == id }) }
        return ControlAPIState.WaypointStatus(
            id: waypoint.id,
            name: waypoint.name,
            slug: waypoint.slug,
            itemId: itemId,
            itemTitle: itemIndex.map { engine.planItems[$0].title },
            itemIndex: itemIndex
        )
    }

    private func waypointStatuses() -> [ControlAPIState.WaypointStatus] {
        engine.waypoints.map { waypointStatus(for: $0) }
    }

    private func scheduleEntry(_ schedule: ServiceSchedule) -> ControlAPIState.ScheduleStatus.Entry {
        ControlAPIState.ScheduleStatus.Entry(
            id: schedule.id,
            title: schedule.title,
            startsAt: schedule.startsAt,
            goLiveAt: schedule.goLiveAt,
            goLiveOffsetSeconds: schedule.goLiveOffsetSeconds,
            goLiveOffsetMinutes: schedule.goLiveOffsetMinutes,
            pcoServiceTypeId: schedule.pcoServiceTypeId,
            pcoPlanId: schedule.pcoPlanId,
            recurrence: schedule.recurrence.rawValue,
            isEnabled: schedule.isEnabled,
            lastFiredAt: schedule.lastFiredAt
        )
    }

    private func scheduleStatus() -> ControlAPIState.ScheduleStatus {
        ControlAPIState.ScheduleStatus(
            entries: engine.serviceSchedules.map(scheduleEntry),
            nextId: engine.nextScheduledService?.id
        )
    }

    private func settingsStatus() -> ControlAPIState.SettingsStatus {
        ControlAPIState.SettingsStatus(
            hourFormatThreshold: engine.hourFormatThreshold.rawValue,
            controlAPIPort: engine.controlAPIPort,
            connectedAPIClients: connectedClientCount()
        )
    }

    private func health() -> [String: String] {
        [
            "service": "13 Years Control API",
            "version": Self.apiVersion,
            "device": Self.deviceName(),
            "role": engine.isMasterServer ? "master" : "client",
            "deviceId": engine.deviceId,
        ]
    }

    private func tooLong(_ value: String, _ limit: Int, _ field: String) -> HTTPResponse? {
        ContentValidation.tooLong(value, limit: limit, field: field).map { Self.error(400, $0.message, detail: $0.detail) }
    }

    private func limitReached(_ what: String, _ limit: Int) -> HTTPResponse {
        Self.error(409, "Limit reached", detail: "At most \(limit) \(what).")
    }

    private func offsetOutOfRange() -> HTTPResponse {
        Self.error(400, "Lead time out of range", detail: "Between 0 and \(TimerLimits.maxSeconds) seconds.")
    }

    private func lengthOutOfRange() -> HTTPResponse {
        Self.error(400, "lengthInSeconds out of range", detail: "Between 0 and \(TimerLimits.maxSeconds).")
    }

    static func offsetSeconds(fromMinutes minutes: Int) -> Int? {
        guard let seconds = TimerLimits.seconds(fromMinutes: minutes), TimerLimits.isValidLength(seconds) else { return nil }
        return seconds
    }

    public static let apiVersion = "1.0.0"

    private static func deviceName() -> String {
        #if os(macOS)
        return Host.current().localizedName ?? "13 Years Producer"
        #else
        return UIDevice.current.name
        #endif
    }

    private func allows(_ method: String, _ allowed: String...) -> Bool {
        method == "ANY" || allowed.contains(method)
    }

    private static func cueState(_ raw: String) -> CueState? {
        CueState(rawValue: raw.uppercased())
    }

    private static func appMode(_ raw: String) -> AppMode? {
        let normalized = raw.replacingOccurrences(of: "_", with: "").lowercased()
        return AppMode.allCases.first { $0.rawValue.replacingOccurrences(of: "_", with: "").lowercased() == normalized }
    }

    private static func recurrence(_ raw: String) -> ServiceSchedule.Recurrence? {
        ServiceSchedule.Recurrence.allCases.first { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ body: Data) -> T? {
        guard !body.isEmpty else { return nil }
        return try? ControlAPIJSON.decoder.decode(type, from: body)
    }

    private func json<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        guard let data = try? ControlAPIJSON.encoder.encode(value) else {
            return Self.error(500, "Failed to encode response")
        }
        return .json(status: status, body: data)
    }

    private func accepted() -> HTTPResponse {
        json(snapshot(), status: 202)
    }

    private func accepted<T: Encodable>(_ value: T) -> HTTPResponse {
        json(value, status: 202)
    }

    private func methodNotAllowed() -> HTTPResponse {
        Self.error(405, "Method not allowed for this route")
    }

    private func badBody() -> HTTPResponse {
        Self.error(400, "Malformed or missing JSON body")
    }

    private func noActiveItem() -> HTTPResponse {
        Self.error(409, "No active plan item", detail: "Load or import a service flow first.")
    }

    private func unknownCueState() -> HTTPResponse {
        Self.error(400, "Unknown cue state", detail: CueState.allCases.map(\.rawValue).joined(separator: ", "))
    }

    nonisolated static func error(_ status: Int, _ message: String, detail: String? = nil) -> HTTPResponse {
        let body = (try? ControlAPIJSON.encoder.encode(ControlAPIErrorBody(error: message, detail: detail))) ?? Data()
        return .json(status: status, body: body)
    }
}
