// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
import Combine
import Network
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class CueEngine: ObservableObject {
    @Published public var appMode: AppMode = .producerControl
    @Published public var roles: [RoleCue] = RoleCue.defaultRoles {
        didSet { persistRoles() }
    }
    @Published public var selectedRoleIds: Set<String> = ["default"]
    @Published public var waypoints: [Waypoint] = [] {
        didSet { persistWaypoints() }
    }
    @Published public var serviceSchedules: [ServiceSchedule] = [] {
        didSet { persistServiceSchedules() }
    }

    @Published public var planItems: [PCOTimerItem] = [] {
        didSet { persistCurrentFlow() }
    }
    @Published public var activeItemIndex: Int = 0 {
        didSet { persistCurrentFlow() }
    }
    @Published public var activeTimerItem: PCOTimerItem?
    @Published private var isActiveTimerActualOverride: Bool = false
    private var actualOverrideItemId: String?
    @Published public var isPCOConnected: Bool = false
    @Published public var pcoUserName: String? {
        didSet { UserDefaults.standard.set(pcoUserName, forKey: Self.pcoUserNameDefaultsKey) }
    }
    private static let pcoUserNameDefaultsKey = "pcoUserName"
    @Published public var pcoLastError: String?
    @Published public var pcoNoteCategories: [PCOClient.PCONoteCategory] = []
    @Published public var isPCOLiveSyncEnabled: Bool = false {
        didSet { UserDefaults.standard.set(isPCOLiveSyncEnabled, forKey: Self.pcoLiveSyncDefaultsKey) }
    }
    private static let pcoLiveSyncDefaultsKey = "isPCOLiveSyncEnabled"

    @Published public var hourFormatThreshold: HourFormatThreshold = .over90Minutes {
        didSet { UserDefaults.standard.set(hourFormatThreshold.rawValue, forKey: Self.hourFormatThresholdDefaultsKey) }
    }
    private static let hourFormatThresholdDefaultsKey = "hourFormatThreshold"

    @Published public var pcoServiceTypes: [PCOClient.PCOServiceType] = []
    @Published public var pcoPlans: [PCOClient.PCOPlanInfo] = []
    @Published public var pcoSelectedServiceTypeId: String?
    @Published public var pcoPlanFilter: PCOClient.PCOPlanFilter = .future
    @Published public var pcoDefaultServiceTypeId: String? {
        didSet { UserDefaults.standard.set(pcoDefaultServiceTypeId, forKey: Self.defaultServiceTypeDefaultsKey) }
    }
    private static let defaultServiceTypeDefaultsKey = "pcoDefaultServiceTypeId"

    @Published public var pcoOAuthTokens: OAuthTokens? {
        didSet {
            pcoClient.tokens = pcoOAuthTokens
            KeychainStore.setCodable(pcoOAuthTokens, forKey: Self.pcoTokensKeychainKey)
        }
    }
    private static let pcoTokensKeychainKey = "pcoOAuthTokens"

    @Published public var recentMessages: [InterTeamMessage] = [] {
        didSet { persistMessages() }
    }
    private static let messagesDefaultsKey = "recentMessages"

    @Published public var notificationsClearedAt: Date? {
        didSet { persistNotificationsClearedAt() }
    }
    private static let notificationsClearedDefaultsKey = "notificationsClearedAt"
    private static let maxStoredMessages = 200
    @Published public var isMasterServer: Bool = true
    @Published public var connectedMasterName: String?
    @Published public var connectedProducerHost: String?
    @Published public var connectedProducerAPIPort: Int?
    @Published public var isLANConnected: Bool = true
    @Published public var isProducerLive: Bool = false
    @Published public var hasSyncedWithProducer: Bool = false
    private var lastProducerPacketAt: Date?
    private static let producerStalenessInterval: TimeInterval = 12
    @Published public var isProxyEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isProxyEnabled, forKey: Self.proxyEnabledDefaultsKey)
            updateRelayConnection()
        }
    }
    @Published public var proxyToken: String = "" {
        didSet {
            KeychainStore.setString(proxyToken, forKey: Self.proxyTokenKeychainKey)
            updateRelayConnection()
        }
    }
    @Published public var plotipharRelayHost: String = "relay.13years.app" {
        didSet {
            UserDefaults.standard.set(plotipharRelayHost, forKey: Self.relayHostDefaultsKey)
            updateRelayConnection()
        }
    }
    private static let proxyEnabledDefaultsKey = "isProxyEnabled"
    private static let proxyTokenKeychainKey = "plotipharProxyToken"
    private static let relayHostDefaultsKey = "plotipharRelayHost"

    @Published public var isControlAPIEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isControlAPIEnabled, forKey: Self.controlAPIEnabledDefaultsKey)
            updateControlAPI()
        }
    }
    @Published public var controlAPIPort: Int = Int(ControlAPIServer.defaultPort) {
        didSet {
            UserDefaults.standard.set(controlAPIPort, forKey: Self.controlAPIPortDefaultsKey)
            updateControlAPI()
        }
    }
    @Published public var isControlAPIRunning: Bool = false
    @Published public var controlAPIClientCount: Int = 0
    private static let controlAPIEnabledDefaultsKey = "isControlAPIEnabled"
    private static let controlAPIPortDefaultsKey = "controlAPIPort"

    @Published public var plotipharPairingState: PlotipharPairingState = .idle
    @Published public var plotipharAssignmentSyncStatus: PlotipharAssignmentSyncStatus = .notSynced
    @Published public var plotipharRoles: [PlotipharClient.PlotipharRole] = []

    private static let deviceIdDefaultsKey = "cueEngineDeviceId"
    private let deviceId: String = {
        if let existing = UserDefaults.standard.string(forKey: CueEngine.deviceIdDefaultsKey) {
            return existing
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: CueEngine.deviceIdDefaultsKey)
        return id
    }()

    private let server = LocalCueServer()
    private let client = LocalCueClient()
    private let relayClient = PlotipharRelayClient()
    private let directPeerChannel = DirectPeerChannel()
    private var controlAPIServer: ControlAPIServer?
    private var controlAPIEventHub: ControlAPIEventHub?
    private let hostsControlAPI: Bool
    private let pcoClient = PCOClient()
    private let plotipharPairingClient = PlotipharPairingClient()
    private let plotipharClient = PlotipharClient()
    private var plotipharPollTask: Task<Void, Never>?
    private var timerSubscription: AnyCancellable?

    public init(isMasterServer: Bool = true, hostsControlAPI: Bool = false) {
        self.isMasterServer = isMasterServer
        self.hostsControlAPI = hostsControlAPI
        self.pcoDefaultServiceTypeId = UserDefaults.standard.string(forKey: Self.defaultServiceTypeDefaultsKey)
        self.hourFormatThreshold = UserDefaults.standard.string(forKey: Self.hourFormatThresholdDefaultsKey)
            .flatMap(HourFormatThreshold.init(rawValue:)) ?? .over90Minutes

        self.pcoOAuthTokens = KeychainStore.codable(OAuthTokens.self, forKey: Self.pcoTokensKeychainKey)
        self.pcoUserName = UserDefaults.standard.string(forKey: Self.pcoUserNameDefaultsKey)
        self.isPCOConnected = pcoOAuthTokens != nil
        KeychainStore.setString(nil, forKey: "pcoSecret")
        self.plotipharRelayHost = UserDefaults.standard.string(forKey: Self.relayHostDefaultsKey) ?? "relay.13years.app"
        self.proxyToken = KeychainStore.string(forKey: Self.proxyTokenKeychainKey) ?? ""
        self.isProxyEnabled = UserDefaults.standard.object(forKey: Self.proxyEnabledDefaultsKey) != nil
            ? UserDefaults.standard.bool(forKey: Self.proxyEnabledDefaultsKey)
            : false
        if hostsControlAPI {
            self.controlAPIPort = UserDefaults.standard.object(forKey: Self.controlAPIPortDefaultsKey) as? Int ?? Int(ControlAPIServer.defaultPort)
            self.isControlAPIEnabled = UserDefaults.standard.bool(forKey: Self.controlAPIEnabledDefaultsKey)
        }
        if !proxyToken.isEmpty {
            plotipharPairingState = .approved
        }

        restoreRoles()
        restoreWaypoints()
        restoreServiceSchedules()
        restoreMessages()
        restoreNotificationsClearedAt()
        restorePersistedFlow()
        setupDefaultPlan()
        startNetworking()
        relayClient.onPacketReceived = { [weak self] packet in
            self?.handlePacket(packet)
        }
        relayClient.onTextMessageReceived = { [weak self] data in
            guard let peerHello = PeerHello.decode(from: data) else { return }
            self?.directPeerChannel.connect(to: peerHello)
        }
        directPeerChannel.onPacketReceived = { [weak self] packet in
            self?.handlePacket(packet)
        }

        refreshPCOTokensIfNeeded()

        if UserDefaults.standard.bool(forKey: Self.pcoLiveSyncDefaultsKey) {
            enablePCOLiveSync()
        }

        updateControlAPI()
    }

    private func refreshPCOTokensIfNeeded() {
        guard let tokens = pcoOAuthTokens, tokens.isExpired else { return }
        Task {
            do {
                self.pcoOAuthTokens = try await OAuthTokenExchange.refresh(tokens.refreshToken)
            } catch {
                print("[CueEngine] PCO token refresh failed: \(error.localizedDescription)")
            }
        }
    }

    public func startNetworking() {
        AppLog.cue.info("startNetworking() — isMasterServer=\(self.isMasterServer, privacy: .public)")
        isProducerLive = false
        hasSyncedWithProducer = false
        lastProducerPacketAt = nil
        connectedProducerHost = nil
        connectedProducerAPIPort = nil
        if isMasterServer {
            client.stop()
            server.start()
            server.advertisedControlAPIPort = controlAPIPort
            server.onPacketReceived = { [weak self] packet in
                self?.handlePacket(packet)
            }
            server.onStatusChanged = { [weak self] isJoined in
                self?.isLANConnected = isJoined
            }
        } else {
            server.stop()
            client.start()
            client.onPacketReceived = { [weak self] packet in
                self?.handlePacket(packet)
            }
            client.onStatusChanged = { [weak self] isJoined in
                self?.isLANConnected = isJoined
                if !isJoined {
                    self?.isProducerLive = false
                    self?.connectedProducerHost = nil
                    self?.connectedProducerAPIPort = nil
                }
            }
            client.onMasterDiscovered = { [weak self] name in
                self?.connectedMasterName = name
                self?.requestCatchUp()
            }
            client.onConnectedHost = { [weak self] host in
                self?.connectedProducerHost = host
            }
            client.onConnectedAPIPort = { [weak self] apiPort in
                self?.connectedProducerAPIPort = apiPort
            }
            requestCatchUp()
        }
    }

    public func toggleMasterMode() {
        isMasterServer.toggle()
        startNetworking()
    }

    public func signInWithPCO() {
        Task {
            do {
                let signIn = OAuthSignIn()
                let tokens = try await signIn.signIn()
                self.pcoOAuthTokens = tokens
                self.isPCOConnected = true

                let person = try await pcoClient.fetchCurrentPerson()
                self.pcoUserName = person.name

                await fetchPCOServiceTypesAsync()
                if let defaultId = pcoDefaultServiceTypeId, pcoServiceTypes.contains(where: { $0.id == defaultId }) {
                    selectPCOServiceType(defaultId)
                }
            } catch {
                print("[CueEngine] PCO OAuth sign-in error: \(error.localizedDescription)")
            }
        }
    }

    public func signOutOfPCO() {
        isPCOLiveSyncEnabled = false
        pcoOAuthTokens = nil
        pcoUserName = nil
        isPCOConnected = false
        pcoServiceTypes = []
        pcoPlans = []
        pcoSelectedServiceTypeId = nil
    }

    public func fetchPCOPlan(serviceTypeId: String, planId: String) {
        if planId != currentPCOPlanId {
            disablePCOLiveSync()
        }
        Task {
            do {
                let (title, items) = try await pcoClient.fetchPlanItems(serviceTypeId: serviceTypeId, planId: planId)
                pcoLastError = nil
                if !items.isEmpty {
                    importFlow(title: title, items: items)
                    self.isPCOConnected = true
                    syncPlotipharAssignments()
                }
                self.pcoNoteCategories = (try? await pcoClient.fetchItemNoteCategories(serviceTypeId: serviceTypeId, planId: planId)) ?? []
            } catch {
                pcoLastError = error.localizedDescription
                print("[CueEngine] PCO sync error: \(error.localizedDescription)")
            }
        }
    }

    public func fetchPCOServiceTypes() {
        Task { await fetchPCOServiceTypesAsync() }
    }

    private func fetchPCOServiceTypesAsync() async {
        do {
            pcoServiceTypes = try await pcoClient.fetchServiceTypes()
            pcoLastError = nil
        } catch {
            print("[CueEngine] fetchPCOServiceTypes error: \(error.localizedDescription)")
            pcoLastError = error.localizedDescription
        }
    }

    public func selectPCOServiceType(_ serviceTypeId: String) {
        pcoSelectedServiceTypeId = serviceTypeId
        fetchPCOPlans()
    }

    public func fetchPCOPlans() {
        guard let serviceTypeId = pcoSelectedServiceTypeId else { return }
        Task {
            do {
                pcoPlans = try await pcoClient.fetchPlans(serviceTypeId: serviceTypeId, filter: pcoPlanFilter)
                pcoLastError = nil
            } catch {
                print("[CueEngine] fetchPCOPlans: FAILED — \(error)")
                pcoLastError = error.localizedDescription
            }
        }
    }

    public func setPlanFilter(_ filter: PCOClient.PCOPlanFilter) {
        pcoPlanFilter = filter
        fetchPCOPlans()
    }

    public func setDefaultServiceType(_ serviceTypeId: String?) {
        pcoDefaultServiceTypeId = serviceTypeId
    }

    public func startPlotipharPairing() {
        plotipharPollTask?.cancel()
        plotipharPairingState = .starting

        plotipharPollTask = Task {
            do {
                let start = try await plotipharPairingClient.startPairing(deviceName: plotipharDeviceName())
                plotipharPairingState = .waitingApproval(code: start.code, expiresAt: start.expiresAt)
                try await pollPlotipharPairing(deviceToken: start.deviceToken)
            } catch is CancellationError {
            } catch {
                plotipharPairingState = .error(error.localizedDescription)
            }
        }
    }

    public func cancelPlotipharPairing() {
        plotipharPollTask?.cancel()
        plotipharPollTask = nil
        plotipharPairingState = .idle
    }

    public func disconnectPlotiphar() {
        cancelPlotipharPairing()
        proxyToken = ""
        isProxyEnabled = false
    }

    private func updateRelayConnection() {
        relayClient.relayHost = plotipharRelayHost
        relayClient.token = proxyToken

        if isProxyEnabled && !proxyToken.isEmpty {
            relayClient.start()
            directPeerChannel.start()
            broadcastDirectPeerHello()
        } else {
            relayClient.stop()
            directPeerChannel.stop()
        }
    }

    private func broadcastDirectPeerHello() {
        guard isProxyEnabled, !proxyToken.isEmpty else { return }
        if let payload = directPeerChannel.buildHelloPayload() {
            relayClient.sendText(payload)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.broadcastDirectPeerHello()
            }
        }
    }

    private func pollPlotipharPairing(deviceToken: String) async throws {
        let pollInterval: UInt64 = 2_500_000_000

        while true {
            try await Task.sleep(nanoseconds: pollInterval)
            try Task.checkCancellation()

            let status = try await plotipharPairingClient.pollStatus(deviceToken: deviceToken)
            switch status {
            case .pending:
                continue
            case .approved(let sessionToken, _):
                proxyToken = sessionToken
                isProxyEnabled = true
                plotipharPairingState = .approved
                syncPlotipharAssignments()
                return
            case .expired:
                plotipharPairingState = .expired
                return
            }
        }
    }

    private func plotipharDeviceName() -> String {
        #if os(macOS)
        return Host.current().localizedName ?? "13 Years Producer"
        #else
        return UIDevice.current.name
        #endif
    }

    public func importFlow(title: String?, items: [PCOTimerItem]) {
        var stamped = items
        for index in stamped.indices {
            stamped[index].sequence = index + 1
            stamped[index].servicePlanTitle = title
            stamped[index].elapsedSeconds = 0
            stamped[index].isRunning = false
        }
        planItems = stamped
        if let firstSelectable = stamped.firstIndex(where: { !$0.isHeader }) {
            activeItemIndex = firstSelectable
            var item = stamped[firstSelectable]
            item.isRunning = true
            activeTimerItem = item
        } else {
            activeItemIndex = 0
            activeTimerItem = nil
        }
        broadcastTimerUpdate()
    }

    public func addPlanItem(title: String, itemType: String, lengthInSeconds: Int, isDurationActual: Bool = false) {
        var item = PCOTimerItem(
            title: title,
            itemType: itemType,
            sequence: planItems.count + 1,
            lengthInSeconds: lengthInSeconds,
            isDurationActual: isDurationActual
        )
        item.servicePlanTitle = planItems.first?.servicePlanTitle
        planItems.append(item)

        if activeTimerItem == nil && !item.isHeader {
            activeItemIndex = planItems.count - 1
            item.isRunning = true
            activeTimerItem = item
            broadcastTimerUpdate()
        }
    }

    public func updatePlanItem(id: String, title: String, itemType: String, lengthInSeconds: Int, notes: [String: String]? = nil, isDurationActual: Bool? = nil) {
        guard let index = planItems.firstIndex(where: { $0.id == id }) else { return }
        let previousLength = planItems[index].lengthInSeconds
        planItems[index].title = title
        planItems[index].itemType = itemType
        planItems[index].lengthInSeconds = lengthInSeconds
        if let notes {
            planItems[index].notes = notes
        }
        if let isDurationActual {
            planItems[index].isDurationActual = isDurationActual
        }

        if activeTimerItem?.id == id {
            activeTimerItem = planItems[index]
            broadcastTimerUpdate()
        }

        if lengthInSeconds != previousLength {
            pushItemLengthToPCO(id: id)
        }
        if let notes {
            for category in notes.keys {
                pushItemNoteToPCO(id: id, category: category)
            }
        }
    }

    public func pushItemLengthToPCO(id: String) {
        guard let item = planItems.first(where: { $0.id == id }),
              let serviceTypeId = item.pcoServiceTypeId,
              let planId = item.pcoPlanId else { return }
        Task {
            do {
                try await pcoClient.updateItemLength(serviceTypeId: serviceTypeId, planId: planId, itemId: item.id, lengthInSeconds: item.lengthInSeconds)
                pcoLastError = nil
            } catch {
                pcoLastError = error.localizedDescription
            }
        }
    }

    public func pushItemNoteToPCO(id: String, category: String) {
        guard let index = planItems.firstIndex(where: { $0.id == id }),
              let serviceTypeId = planItems[index].pcoServiceTypeId,
              let planId = planItems[index].pcoPlanId,
              let content = planItems[index].notes[category] else { return }

        let itemId = planItems[index].id
        if let existingNoteId = planItems[index].noteIds[category] {
            Task {
                do {
                    try await pcoClient.updateItemNoteContent(serviceTypeId: serviceTypeId, planId: planId, itemId: itemId, noteId: existingNoteId, content: content)
                    pcoLastError = nil
                } catch {
                    pcoLastError = error.localizedDescription
                }
            }
        } else if let categoryId = pcoNoteCategories.first(where: { $0.name == category })?.id {
            Task {
                do {
                    let newNoteId = try await pcoClient.createItemNote(serviceTypeId: serviceTypeId, planId: planId, itemId: itemId, categoryId: categoryId, content: content)
                    pcoLastError = nil
                    if let idx = planItems.firstIndex(where: { $0.id == id }) {
                        planItems[idx].noteIds[category] = newNoteId
                    }
                } catch {
                    pcoLastError = error.localizedDescription
                }
            }
        }
    }

    public func removePlanItem(id: String) {
        guard let index = planItems.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeTimerItem?.id == id
        planItems.remove(at: index)
        renumberPlanItems()

        if wasActive {
            let landingIndex = min(index, planItems.count - 1)
            if landingIndex >= 0 {
                activeItemIndex = resolveSelectableIndex(startingAt: landingIndex)
                var item = planItems[activeItemIndex]
                item.isRunning = false
                activeTimerItem = item
            } else {
                activeItemIndex = 0
                activeTimerItem = nil
            }
            broadcastTimerUpdate()
        } else if let activeId = activeTimerItem?.id, let newIndex = planItems.firstIndex(where: { $0.id == activeId }) {
            activeItemIndex = newIndex
        }
    }

    public func movePlanItems(fromOffsets: IndexSet, toOffset: Int) {
        let activeId = activeTimerItem?.id
        planItems.move(fromOffsets: fromOffsets, toOffset: toOffset)
        renumberPlanItems()

        if let activeId, let newIndex = planItems.firstIndex(where: { $0.id == activeId }) {
            activeItemIndex = newIndex
        }
    }

    public func setActivePlanItem(id: String) {
        guard let tappedIndex = planItems.firstIndex(where: { $0.id == id }) else { return }
        let index = resolveSelectableIndex(startingAt: tappedIndex)
        let previousIndex = activeItemIndex
        activeItemIndex = index
        var item = planItems[index]
        item.isRunning = true
        activeTimerItem = item
        broadcastTimerUpdate()

        let steps = realItemStepCount(from: previousIndex, to: index)
        if index > previousIndex {
            mirrorToPCOLive(direction: .next, count: steps, targetItemId: item.id)
        } else if index < previousIndex {
            mirrorToPCOLive(direction: .previous, count: steps, targetItemId: item.id)
        }
    }

    @discardableResult
    public func addWaypoint(name: String) -> Waypoint? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let slug = Waypoint.slug(for: trimmed)
        guard !slug.isEmpty, !waypoints.contains(where: { $0.slug == slug }) else { return nil }
        let waypoint = Waypoint(name: trimmed)
        waypoints.append(waypoint)
        AppLog.cue.info("addWaypoint(\"\(trimmed, privacy: .public)\") -> \(waypoint.id, privacy: .public)")
        return waypoint
    }

    public func renameWaypoint(id: String, name: String) {
        guard let index = waypoints.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newSlug = Waypoint.slug(for: trimmed)
        guard !newSlug.isEmpty,
              !waypoints.contains(where: { $0.id != id && $0.slug == newSlug }) else { return }
        waypoints[index].name = trimmed
    }

    public func removeWaypoint(id: String) {
        guard waypoints.contains(where: { $0.id == id }) else { return }
        waypoints.removeAll { $0.id == id }
        for index in planItems.indices where planItems[index].waypointIds.contains(id) {
            planItems[index].waypointIds.removeAll { $0 == id }
        }
    }

    public func waypoint(matching raw: String) -> Waypoint? {
        waypoints.first { $0.matches(raw) }
    }

    public func assignWaypoint(_ waypointId: String, toItemId itemId: String?) {
        guard waypoints.contains(where: { $0.id == waypointId }) else { return }
        for index in planItems.indices where planItems[index].waypointIds.contains(waypointId) {
            planItems[index].waypointIds.removeAll { $0 == waypointId }
        }
        if let itemId, let targetIndex = planItems.firstIndex(where: { $0.id == itemId }) {
            planItems[targetIndex].waypointIds.append(waypointId)
        }
    }

    public func setWaypointIds(_ waypointIds: [String], forItemId itemId: String) {
        guard let targetIndex = planItems.firstIndex(where: { $0.id == itemId }) else { return }
        let knownIds = Set(waypoints.map(\.id))
        var deduped: [String] = []
        for waypointId in waypointIds where knownIds.contains(waypointId) && !deduped.contains(waypointId) {
            deduped.append(waypointId)
        }
        for otherIndex in planItems.indices where otherIndex != targetIndex {
            planItems[otherIndex].waypointIds.removeAll { deduped.contains($0) }
        }
        planItems[targetIndex].waypointIds = deduped
    }

    public func itemId(forWaypointId waypointId: String) -> String? {
        planItems.first { $0.waypointIds.contains(waypointId) }?.id
    }

    public func planItem(forWaypoint raw: String) -> PCOTimerItem? {
        guard let waypoint = waypoint(matching: raw) else { return nil }
        return planItems.first { $0.waypointIds.contains(waypoint.id) }
    }

    public func waypoints(forItemId itemId: String) -> [Waypoint] {
        guard let item = planItems.first(where: { $0.id == itemId }) else { return [] }
        return waypoints.filter { item.waypointIds.contains($0.id) }
    }

    public enum WaypointFireResult: Equatable, Sendable {
        case fired(itemId: String)
        case unknownWaypoint
        case unassigned(waypointId: String)
    }

    @discardableResult
    public func fireWaypoint(_ raw: String, startTimer: Bool = true) -> WaypointFireResult {
        guard let waypoint = waypoint(matching: raw) else {
            AppLog.cue.info("fireWaypoint(\"\(raw, privacy: .public)\") -> unknown waypoint")
            return .unknownWaypoint
        }
        guard let itemId = itemId(forWaypointId: waypoint.id) else {
            AppLog.cue.info("fireWaypoint(\"\(raw, privacy: .public)\") -> waypoint \(waypoint.id, privacy: .public) has no item assigned this week")
            return .unassigned(waypointId: waypoint.id)
        }
        setActivePlanItem(id: itemId)
        if let item = activeTimerItem, item.isRunning != startTimer {
            toggleTimerRunning()
        }
        AppLog.cue.info("fireWaypoint(\"\(raw, privacy: .public)\") -> item \(itemId, privacy: .public)")
        return .fired(itemId: itemId)
    }

    private func sortedByStartsAt(_ schedules: [ServiceSchedule]) -> [ServiceSchedule] {
        schedules.sorted { $0.startsAt < $1.startsAt }
    }

    @discardableResult
    public func addServiceSchedule(
        title: String,
        startsAt: Date,
        goLiveOffsetSeconds: Int = 30 * 60,
        pcoServiceTypeId: String? = nil,
        pcoPlanId: String? = nil,
        recurrence: ServiceSchedule.Recurrence = .once,
        isEnabled: Bool = true
    ) -> ServiceSchedule? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, goLiveOffsetSeconds >= 0 else { return nil }
        let schedule = ServiceSchedule(
            title: trimmed,
            startsAt: startsAt,
            goLiveOffsetSeconds: goLiveOffsetSeconds,
            pcoServiceTypeId: pcoServiceTypeId,
            pcoPlanId: pcoPlanId,
            recurrence: recurrence,
            isEnabled: isEnabled
        )
        serviceSchedules = sortedByStartsAt(serviceSchedules + [schedule])
        AppLog.cue.info("addServiceSchedule(\"\(trimmed, privacy: .public)\") -> \(schedule.id, privacy: .public)")
        return schedule
    }

    public func updateServiceSchedule(
        id: String,
        title: String? = nil,
        startsAt: Date? = nil,
        goLiveOffsetSeconds: Int? = nil,
        pcoServiceTypeId: String?? = nil,
        pcoPlanId: String?? = nil,
        recurrence: ServiceSchedule.Recurrence? = nil,
        isEnabled: Bool? = nil
    ) {
        guard let index = serviceSchedules.firstIndex(where: { $0.id == id }) else { return }
        var schedule = serviceSchedules[index]
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { schedule.title = trimmed }
        }
        var timingChanged = false
        if let startsAt {
            schedule.startsAt = startsAt
            timingChanged = true
        }
        if let goLiveOffsetSeconds, goLiveOffsetSeconds >= 0 {
            schedule.goLiveOffsetSeconds = goLiveOffsetSeconds
            timingChanged = true
        }
        if let pcoServiceTypeId { schedule.pcoServiceTypeId = pcoServiceTypeId }
        if let pcoPlanId { schedule.pcoPlanId = pcoPlanId }
        if let recurrence { schedule.recurrence = recurrence }
        if let isEnabled { schedule.isEnabled = isEnabled }
        if timingChanged { schedule.lastFiredAt = nil }
        var updated = serviceSchedules
        updated[index] = schedule
        serviceSchedules = sortedByStartsAt(updated)
    }

    public func removeServiceSchedule(id: String) {
        serviceSchedules.removeAll { $0.id == id }
    }

    public func serviceSchedule(id: String) -> ServiceSchedule? {
        serviceSchedules.first { $0.id == id }
    }

    public var nextScheduledService: ServiceSchedule? {
        let now = Date()
        return serviceSchedules.first { $0.isEnabled && $0.goLiveAt > now }
    }

    public func goLiveWithSchedule(id: String) {
        guard let index = serviceSchedules.firstIndex(where: { $0.id == id }) else { return }
        var schedule = serviceSchedules[index]
        let now = Date()

        schedule.lastFiredAt = now

        if let serviceTypeId = schedule.pcoServiceTypeId, let planId = schedule.pcoPlanId {
            fetchPCOPlan(serviceTypeId: serviceTypeId, planId: planId)
        }
        appMode = .producerControl

        switch schedule.recurrence {
        case .weekly:
            if let next = schedule.nextOccurrence(after: now) {
                schedule.startsAt = next
            }
            schedule.lastFiredAt = nil
        case .once:
            schedule.isEnabled = false
        }

        var updated = serviceSchedules
        updated[index] = schedule
        serviceSchedules = sortedByStartsAt(updated)
        AppLog.cue.info("goLiveWithSchedule(\"\(schedule.title, privacy: .public)\") -> \(schedule.id, privacy: .public)")
    }

    private func checkServiceSchedules() {
        guard isMasterServer else { return }
        let now = Date()
        for schedule in serviceSchedules where schedule.shouldFire(at: now) {
            goLiveWithSchedule(id: schedule.id)
        }
    }

    public func enablePCOLiveSync() {
        guard let serviceTypeId = currentPCOServiceTypeId, let planId = currentPCOPlanId else {
            pcoLastError = "Sync a Planning Center plan before enabling Live sync."
            return
        }
        Task {
            await takeLiveControlIfNeeded(serviceTypeId: serviceTypeId, planId: planId)
        }
    }

    private func takeLiveControlIfNeeded(serviceTypeId: String, planId: String) async {
        guard !isPCOLiveSyncEnabled else { return }
        if await forceTakeLiveControl(serviceTypeId: serviceTypeId, planId: planId) {
            syncElapsedTimeFromPCOLive()
        }
    }

    @discardableResult
    private func forceTakeLiveControl(serviceTypeId: String, planId: String) async -> Bool {
        do {
            try await pcoClient.toggleLiveControl(serviceTypeId: serviceTypeId, planId: planId)
            pcoLastError = nil
            isPCOLiveSyncEnabled = true
            return true
        } catch {
            pcoLastError = error.localizedDescription
            isPCOLiveSyncEnabled = false
            return false
        }
    }

    public func disablePCOLiveSync() {
        guard isPCOLiveSyncEnabled else { return }
        isPCOLiveSyncEnabled = false
        guard let serviceTypeId = currentPCOServiceTypeId, let planId = currentPCOPlanId else { return }
        Task {
            do {
                try await pcoClient.toggleLiveControl(serviceTypeId: serviceTypeId, planId: planId)
            } catch {
                print("[CueEngine] Failed to release PCO Live control: \(error.localizedDescription)")
            }
        }
    }

    private func syncElapsedTimeFromPCOLive() {
        guard isPCOLiveSyncEnabled,
              let serviceTypeId = currentPCOServiceTypeId,
              let planId = currentPCOPlanId else { return }
        Task {
            do {
                guard let currentItemTime = try await pcoClient.fetchCurrentItemTime(serviceTypeId: serviceTypeId, planId: planId) else { return }

                guard currentItemTime.itemId == activeTimerItem?.id,
                      let liveStartAt = currentItemTime.liveStartAt else { return }

                let elapsed = max(0, Int(Date().timeIntervalSince(liveStartAt)))
                if var item = activeTimerItem {
                    item.elapsedSeconds = elapsed
                    item.isRunning = true
                    activeTimerItem = item
                }
            } catch {
                pcoLastError = error.localizedDescription
            }
        }
    }

    private var currentPCOServiceTypeId: String? {
        activeTimerItem?.pcoServiceTypeId ?? planItems.first?.pcoServiceTypeId
    }

    private var currentPCOPlanId: String? {
        activeTimerItem?.pcoPlanId ?? planItems.first?.pcoPlanId
    }

    private func mirrorToPCOLive(direction: PCOClient.PCOLiveDirection, count: Int = 1, targetItemId: String? = nil) {
        guard count > 0,
              let serviceTypeId = currentPCOServiceTypeId,
              let planId = currentPCOPlanId else { return }
        Task {
            await takeLiveControlIfNeeded(serviceTypeId: serviceTypeId, planId: planId)
            guard isPCOLiveSyncEnabled else { return }

            var remainingSteps = count
            var alreadyReasserted = false
            while remainingSteps > 0 {
                do {
                    try await pcoClient.stepLiveItem(serviceTypeId: serviceTypeId, planId: planId, direction: direction)
                    remainingSteps -= 1
                } catch {
                    if !alreadyReasserted {
                        alreadyReasserted = true
                        if await forceTakeLiveControl(serviceTypeId: serviceTypeId, planId: planId) {
                            continue
                        }
                    }
                    pcoLastError = error.localizedDescription
                    break
                }
            }
            await verifyPCOPosition(serviceTypeId: serviceTypeId, planId: planId, targetItemId: targetItemId)
        }
    }

    private func verifyPCOPosition(
        serviceTypeId: String,
        planId: String,
        targetItemId: String?,
        alreadyCorrected: Bool = false
    ) async {
        guard isPCOLiveSyncEnabled else { return }
        do {
            guard let currentItemTime = try await pcoClient.fetchCurrentItemTime(serviceTypeId: serviceTypeId, planId: planId) else { return }

            if let targetItemId, currentItemTime.itemId != targetItemId, !alreadyCorrected,
               let targetIndex = planItems.firstIndex(where: { $0.id == targetItemId }),
               let actualIndex = planItems.firstIndex(where: { $0.id == currentItemTime.itemId }) {
                let correctionSteps = realItemStepCount(from: actualIndex, to: targetIndex)
                if correctionSteps > 0 {
                    let correctionDirection: PCOClient.PCOLiveDirection = targetIndex > actualIndex ? .next : .previous
                    for _ in 0..<correctionSteps {
                        try await pcoClient.stepLiveItem(serviceTypeId: serviceTypeId, planId: planId, direction: correctionDirection)
                    }
                    await verifyPCOPosition(serviceTypeId: serviceTypeId, planId: planId, targetItemId: targetItemId, alreadyCorrected: true)
                    return
                }
            }

            guard currentItemTime.itemId == activeTimerItem?.id, let liveStartAt = currentItemTime.liveStartAt else { return }
            let elapsed = max(0, Int(Date().timeIntervalSince(liveStartAt)))
            if var item = activeTimerItem {
                item.elapsedSeconds = elapsed
                item.isRunning = true
                activeTimerItem = item
            }
        } catch {
            pcoLastError = error.localizedDescription
        }
    }

    private func renumberPlanItems() {
        for index in planItems.indices {
            planItems[index].sequence = index + 1
        }
    }

    public func adjustTimerRemainingTime(bySeconds delta: Int) {
        guard var item = activeTimerItem else { return }
        item.adjustRemainingTime(bySeconds: delta)
        self.activeTimerItem = item
        broadcastTimerUpdate()

        if let index = planItems.firstIndex(where: { $0.id == item.id }) {
            planItems[index].lengthInSeconds = item.lengthInSeconds
        }
        pushItemLengthToPCO(id: item.id)
    }

    public func setTimerRemainingTime(seconds: Int) {
        guard var item = activeTimerItem else { return }
        item.setRemainingTime(seconds: seconds)
        self.activeTimerItem = item
        broadcastTimerUpdate()

        if let index = planItems.firstIndex(where: { $0.id == item.id }) {
            planItems[index].lengthInSeconds = item.lengthInSeconds
        }
        pushItemLengthToPCO(id: item.id)
    }

    public func setDurationIsActual(id: String, isActual: Bool) {
        if let index = planItems.firstIndex(where: { $0.id == id }) {
            planItems[index].isDurationActual = isActual
        }
        if activeTimerItem?.id == id {
            activeTimerItem?.isDurationActual = isActual
        }
    }

    public func setActiveTimerActualOverride(_ isActual: Bool) {
        guard let item = activeTimerItem else { return }
        isActiveTimerActualOverride = isActual
        actualOverrideItemId = isActual ? item.id : nil
        broadcastState()
    }

    public var activeTimerActualForDisplay: Bool {
        guard let item = activeTimerItem else { return false }
        if actualOverrideItemId == item.id { return isActiveTimerActualOverride }
        return item.isDurationActual
    }

    private var activeTimerItemForBroadcast: PCOTimerItem? {
        guard var item = activeTimerItem else { return nil }
        item.isDurationActual = activeTimerActualForDisplay
        return item
    }

    public func nextPlanItem() {
        guard !planItems.isEmpty, let targetIndex = nextSelectableIndex(after: activeItemIndex) else { return }
        let steps = realItemStepCount(from: activeItemIndex, to: targetIndex)
        activeItemIndex = targetIndex
        var item = planItems[activeItemIndex]
        item.servicePlanTitle = activeTimerItem?.servicePlanTitle
        item.isRunning = true
        activeTimerItem = item
        broadcastTimerUpdate()
        mirrorToPCOLive(direction: .next, count: steps, targetItemId: item.id)
    }

    public func previousPlanItem() {
        guard !planItems.isEmpty, let targetIndex = previousSelectableIndex(before: activeItemIndex) else { return }
        let steps = realItemStepCount(from: activeItemIndex, to: targetIndex)
        activeItemIndex = targetIndex
        var item = planItems[activeItemIndex]
        item.servicePlanTitle = activeTimerItem?.servicePlanTitle
        item.isRunning = true
        activeTimerItem = item
        broadcastTimerUpdate()
        mirrorToPCOLive(direction: .previous, count: steps, targetItemId: item.id)
    }

    private func nextSelectableIndex(after index: Int) -> Int? {
        var candidate = index + 1
        while candidate < planItems.count {
            if !planItems[candidate].isHeader { return candidate }
            candidate += 1
        }
        return nil
    }

    private func previousSelectableIndex(before index: Int) -> Int? {
        var candidate = index - 1
        while candidate >= 0 {
            if !planItems[candidate].isHeader { return candidate }
            candidate -= 1
        }
        return nil
    }

    private func realItemStepCount(from: Int, to: Int) -> Int {
        guard from != to, planItems.indices.contains(from), planItems.indices.contains(to) else { return 0 }
        let range = from < to ? (from + 1)...to : to...(from - 1)
        return planItems[range].filter { !$0.isHeader }.count
    }

    private func resolveSelectableIndex(startingAt index: Int) -> Int {
        guard planItems.indices.contains(index) else { return index }
        if !planItems[index].isHeader { return index }
        if let forward = nextSelectableIndex(after: index - 1) { return forward }
        if let backward = previousSelectableIndex(before: index + 1) { return backward }
        return index
    }

    public var isAtEndOfPlan: Bool {
        !planItems.isEmpty && nextSelectableIndex(after: activeItemIndex) == nil
    }

    public var canLoadNextService: Bool {
        currentPCOServiceTypeId != nil && currentPCOPlanId != nil
    }

    public func loadNextService() {
        guard let serviceTypeId = currentPCOServiceTypeId, let planId = currentPCOPlanId else { return }
        Task {
            do {
                guard let nextPlanId = try await pcoClient.fetchNextPlanId(serviceTypeId: serviceTypeId, planId: planId) else {
                    pcoLastError = "No next service scheduled yet in Planning Center."
                    return
                }
                pcoLastError = nil
                fetchPCOPlan(serviceTypeId: serviceTypeId, planId: nextPlanId)
            } catch {
                pcoLastError = error.localizedDescription
            }
        }
    }

    public func toggleTimerRunning() {
        guard var item = activeTimerItem, !item.isHeader else { return }
        item.isRunning.toggle()
        activeTimerItem = item
        broadcastTimerUpdate()
    }

    public func resetTimer() {
        guard var item = activeTimerItem, !item.isHeader else { return }
        item.elapsedSeconds = 0
        activeTimerItem = item
        broadcastTimerUpdate()

        guard isPCOLiveSyncEnabled,
              let serviceTypeId = currentPCOServiceTypeId,
              let planId = currentPCOPlanId else { return }
        Task {
            await takeLiveControlIfNeeded(serviceTypeId: serviceTypeId, planId: planId)
            guard isPCOLiveSyncEnabled else { return }
            do {
                try await pcoClient.stepLiveItem(serviceTypeId: serviceTypeId, planId: planId, direction: .previous)
                try await pcoClient.stepLiveItem(serviceTypeId: serviceTypeId, planId: planId, direction: .next)
                pcoLastError = nil
            } catch {
                pcoLastError = error.localizedDescription
            }
            syncElapsedTimeFromPCOLive()
        }
    }

    public func toggleRoleSelection(_ roleId: String) {
        if selectedRoleIds.contains(roleId) {
            if selectedRoleIds.count > 1 {
                selectedRoleIds.remove(roleId)
            }
        } else {
            selectedRoleIds.insert(roleId)
        }
    }

    public func setCueForSelectedRoles(_ state: CueState) {
        for index in roles.indices {
            if selectedRoleIds.contains(roles[index].id) {
                roles[index].state = state
                roles[index].lastUpdated = Date()
            }
        }
        broadcastState()
    }

    public func setCueForRole(id: String, state: CueState) {
        if let index = roles.firstIndex(where: { $0.id == id }) {
            roles[index].state = state
            roles[index].lastUpdated = Date()
            broadcastState()
        }
    }

    public func setNoteCategory(forRoleId roleId: String, category: String, isOn: Bool) {
        guard let index = roles.firstIndex(where: { $0.id == roleId }) else { return }
        if isOn {
            if !roles[index].assignedNoteCategories.contains(category) {
                roles[index].assignedNoteCategories.append(category)
            }
        } else {
            roles[index].assignedNoteCategories.removeAll { $0 == category }
        }
        broadcastState()
    }

    public func setPersonName(forRoleId roleId: String, personName: String?) {
        guard let index = roles.firstIndex(where: { $0.id == roleId }) else { return }
        roles[index].personName = personName
        broadcastState()
    }

    @discardableResult
    public func addRole(name: String) -> RoleCue {
        let role = RoleCue(name: name)
        roles.append(role)
        broadcastState()
        return role
    }

    public func renameRole(id: String, name: String) {
        guard let index = roles.firstIndex(where: { $0.id == id }) else { return }
        roles[index].name = name
        broadcastState()
    }

    public func removeRole(id: String) {
        guard let index = roles.firstIndex(where: { $0.id == id }) else { return }
        roles.remove(at: index)
        selectedRoleIds.remove(id)
        broadcastState()
    }

    public func setPlotipharRoleId(forRoleId roleId: String, plotipharRoleId: String?) {
        guard let index = roles.firstIndex(where: { $0.id == roleId }) else { return }
        roles[index].plotipharRoleId = plotipharRoleId
    }

    public func syncPlotipharAssignments() {
        guard isProxyEnabled, !proxyToken.isEmpty else {
            plotipharAssignmentSyncStatus = .notPaired
            return
        }
        guard let pcoPlanId = currentPCOPlanId else { return }

        plotipharClient.sessionToken = proxyToken
        Task {
            do {
                let events = try await plotipharClient.fetchEvents()
                guard let match = events.first(where: { $0.pcoPlanId == pcoPlanId }) else {
                    plotipharAssignmentSyncStatus = .noMatchingEvent
                    return
                }
                applyPlotipharAssignments(match.roleAssignments)
                plotipharRoles = (try? await plotipharClient.fetchRoles()) ?? plotipharRoles
                plotipharAssignmentSyncStatus = .synced(eventId: match.id)
                broadcastState()
            } catch {
                plotipharAssignmentSyncStatus = .error(error.localizedDescription)
            }
        }
    }

    func applyPlotipharAssignments(_ assignments: [PlotipharClient.PlotipharRoleAssignment]) {
        for assignment in assignments {
            guard let index = roles.firstIndex(where: { $0.plotipharRoleId == assignment.roleId }) else { continue }
            guard roles[index].personName?.isEmpty ?? true else { continue }
            roles[index].personName = assignment.personName
        }
    }

    public func clearAllCues() {
        for index in roles.indices {
            roles[index].state = .off
            roles[index].lastUpdated = Date()
        }
        broadcastState()
    }

    public func sendMessage(_ text: String, targetRoleId: String? = nil, senderRoleId: String? = nil, isHighPriority: Bool = false) {
        guard !text.isEmpty else { return }
        let senderName: String
        if let senderRoleId, let role = roles.first(where: { $0.id == senderRoleId }) {
            senderName = role.name
        } else {
            senderName = isMasterServer ? "Producer" : "Crew"
        }
        let msg = InterTeamMessage(
            sender: senderName,
            targetRoleId: targetRoleId,
            senderRoleId: senderRoleId,
            text: text,
            isHighPriority: isHighPriority
        )
        addMessages([msg])

        let packet = CuePacket(type: .messageBroadcast, senderId: deviceId, message: msg)
        if isMasterServer {
            server.broadcast(packet: packet)
        } else {
            client.broadcast(packet: packet)
        }
        broadcastToRelay(packet)
    }

    public func clearActiveNotification() {
        notificationsClearedAt = Date()
    }

    public func activeNotification(forRoleId roleId: String?) -> InterTeamMessage? {
        let cutoff = notificationsClearedAt
        return recentMessages.first { message in
            guard message.targetRoleId == nil || message.targetRoleId == roleId else { return false }
            guard let cutoff else { return true }
            return message.timestamp > cutoff
        }
    }

    public func clearMessageHistory() {
        recentMessages = []
        notificationsClearedAt = nil
        let packet = CuePacket(type: .clearMessages, senderId: deviceId)
        if isMasterServer {
            server.broadcast(packet: packet)
        } else {
            client.broadcast(packet: packet)
        }
        broadcastToRelay(packet)
    }

    @discardableResult
    public func pingDevice(atIP ipString: String) -> Bool {
        guard let selfAddress = DirectPeerChannel.localIPv4Addresses().first else {
            AppLog.networking.error("pingDevice: couldn't determine this device's own LAN IP")
            return false
        }
        guard let payload = try? JSONSerialization.data(withJSONObject: [
            "type": "ASSIGN_PRODUCER",
            "host": selfAddress,
        ]) else { return false }
        guard let port = NWEndpoint.Port(rawValue: LANUnicastServer.assignPort) else { return false }

        let connection = NWConnection(host: NWEndpoint.Host(ipString), port: port, using: .udp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: payload, completion: .contentProcessed { error in
                    if let error {
                        AppLog.networking.error("pingDevice: send failed: \(String(describing: error), privacy: .public)")
                    }
                    connection.cancel()
                })
            case .failed(let error):
                AppLog.networking.error("pingDevice: connection failed: \(String(describing: error), privacy: .public)")
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .utility))
        AppLog.networking.info("pingDevice: sending ASSIGN_PRODUCER (host=\(selfAddress, privacy: .public)) to \(ipString, privacy: .public)")
        return true
    }

    public func forgetAssignedProducer() {
        client.forgetAssignedHost()
    }

    private func requestCatchUp() {
        guard !isMasterServer else { return }
        client.broadcast(packet: CuePacket(type: .ping, senderId: deviceId))
    }

    private static let rolesDefaultsKey = "persistedRoles"

    private func persistRoles() {
        guard let data = try? JSONEncoder().encode(roles) else { return }
        UserDefaults.standard.set(data, forKey: Self.rolesDefaultsKey)
    }

    private func restoreRoles() {
        guard let data = UserDefaults.standard.data(forKey: Self.rolesDefaultsKey),
              let decoded = try? JSONDecoder().decode([RoleCue].self, from: data),
              !decoded.isEmpty else { return }
        roles = decoded
    }

    private static let waypointsDefaultsKey = "waypoints"
    private static let legacyTagsDefaultsKey = "serviceTags"

    private func persistWaypoints() {
        guard let data = try? JSONEncoder().encode(waypoints) else { return }
        UserDefaults.standard.set(data, forKey: Self.waypointsDefaultsKey)
    }

    private func restoreWaypoints() {
        if let data = UserDefaults.standard.data(forKey: Self.waypointsDefaultsKey),
           let decoded = try? JSONDecoder().decode([Waypoint].self, from: data) {
            waypoints = decoded
            return
        }

        guard let legacy = UserDefaults.standard.data(forKey: Self.legacyTagsDefaultsKey),
              let decoded = try? JSONDecoder().decode([Waypoint].self, from: legacy) else { return }
        waypoints = decoded
        UserDefaults.standard.removeObject(forKey: Self.legacyTagsDefaultsKey)
        AppLog.cue.info("migrated \(decoded.count, privacy: .public) waypoint(s) from the legacy \"serviceTags\" key")
    }

    private static let serviceSchedulesDefaultsKey = "serviceSchedules"

    private func persistServiceSchedules() {
        guard let data = try? JSONEncoder().encode(serviceSchedules) else { return }
        UserDefaults.standard.set(data, forKey: Self.serviceSchedulesDefaultsKey)
    }

    private func restoreServiceSchedules() {
        guard let data = UserDefaults.standard.data(forKey: Self.serviceSchedulesDefaultsKey),
              let decoded = try? JSONDecoder().decode([ServiceSchedule].self, from: data) else { return }
        serviceSchedules = sortedByStartsAt(decoded)
    }

    private func persistNotificationsClearedAt() {
        if let notificationsClearedAt {
            UserDefaults.standard.set(notificationsClearedAt, forKey: Self.notificationsClearedDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.notificationsClearedDefaultsKey)
        }
    }

    private func restoreNotificationsClearedAt() {
        notificationsClearedAt = UserDefaults.standard.object(forKey: Self.notificationsClearedDefaultsKey) as? Date
    }

    private func persistMessages() {
        guard let data = try? JSONEncoder().encode(recentMessages) else { return }
        UserDefaults.standard.set(data, forKey: Self.messagesDefaultsKey)
    }

    private func restoreMessages() {
        guard let data = UserDefaults.standard.data(forKey: Self.messagesDefaultsKey),
              let decoded = try? JSONDecoder().decode([InterTeamMessage].self, from: data) else { return }
        recentMessages = decoded
    }

    func addMessages(_ incoming: [InterTeamMessage]) {
        let existingIds = Set(recentMessages.map(\.id))
        let newOnes = incoming.filter { !existingIds.contains($0.id) }
        guard !newOnes.isEmpty else { return }
        recentMessages.append(contentsOf: newOnes)
        recentMessages.sort { $0.timestamp > $1.timestamp }
        if recentMessages.count > Self.maxStoredMessages {
            recentMessages.removeLast(recentMessages.count - Self.maxStoredMessages)
        }
    }

    private struct PersistedFlow: Codable {
        let items: [PCOTimerItem]
        let activeItemIndex: Int
    }
    private static let persistedFlowDefaultsKey = "persistedFlow"

    private func persistCurrentFlow() {
        guard !planItems.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.persistedFlowDefaultsKey)
            return
        }
        let flow = PersistedFlow(items: planItems, activeItemIndex: activeItemIndex)
        guard let data = try? JSONEncoder().encode(flow) else { return }
        UserDefaults.standard.set(data, forKey: Self.persistedFlowDefaultsKey)
    }

    private func restorePersistedFlow() {
        guard let data = UserDefaults.standard.data(forKey: Self.persistedFlowDefaultsKey),
              let flow = try? JSONDecoder().decode(PersistedFlow.self, from: data),
              !flow.items.isEmpty else { return }
        planItems = flow.items
        activeItemIndex = min(max(flow.activeItemIndex, 0), flow.items.count - 1)
        var restoredItem = flow.items[activeItemIndex]
        restoredItem.isRunning = false
        activeTimerItem = restoredItem
    }

    private func setupDefaultPlan() {
        timerSubscription = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tickTimer()
            }
    }

    private var pcoLiveSyncTickCount = 0
    private var heartbeatTickCount = 0

    private func tickTimer() {
        heartbeatTickCount += 1
        if heartbeatTickCount % 10 == 0 {
            AppLog.networking.debug("heartbeat — isMasterServer=\(self.isMasterServer, privacy: .public) connectedMasterName=\(self.connectedMasterName ?? "none", privacy: .public) activeItem=\(self.activeTimerItem?.title ?? "none", privacy: .public)")
        }

        if isPCOLiveSyncEnabled {
            pcoLiveSyncTickCount += 1
            if pcoLiveSyncTickCount % 5 == 0 {
                syncElapsedTimeFromPCOLive()
            }
        }

        if isMasterServer && heartbeatTickCount % 5 == 0 {
            broadcastState()
        }

        if isMasterServer && heartbeatTickCount % 5 == 0 {
            checkServiceSchedules()
        }

        if !isMasterServer {
            if let lastProducerPacketAt {
                isProducerLive = Date().timeIntervalSince(lastProducerPacketAt) < Self.producerStalenessInterval
            } else {
                isProducerLive = false
            }
        }

        guard var item = activeTimerItem, item.isRunning else { return }
        item.elapsedSeconds += 1
        self.activeTimerItem = item

        if isMasterServer && item.elapsedSeconds % 5 == 0 {
            let packet = CuePacket(type: .timerUpdate, senderId: deviceId, timerItem: activeTimerItemForBroadcast)
            server.broadcast(packet: packet)
            broadcastToRelay(packet)
        }
    }

    private func broadcastState() {
        let packet = CuePacket(type: .cueUpdate, senderId: deviceId, roleCues: roles, timerItem: activeTimerItemForBroadcast)
        AppLog.cue.debug("broadcastState() — isMasterServer=\(self.isMasterServer, privacy: .public)")

        if isMasterServer {
            server.broadcast(packet: packet)
        }

        broadcastToRelay(packet)
    }

    private func broadcastCatchUp() {
        let packet = CuePacket(type: .pong, senderId: deviceId, roleCues: roles, timerItem: activeTimerItemForBroadcast, messages: recentMessages)
        AppLog.cue.debug("broadcastCatchUp() — isMasterServer=\(self.isMasterServer, privacy: .public) messages=\(self.recentMessages.count, privacy: .public)")

        if isMasterServer {
            server.broadcast(packet: packet)
        }

        broadcastToRelay(packet)
    }

    private func broadcastTimerUpdate() {
        guard let item = activeTimerItemForBroadcast else { return }
        let packet = CuePacket(type: .timerUpdate, senderId: deviceId, timerItem: item)
        AppLog.cue.debug("broadcastTimerUpdate() — item=\"\(item.title, privacy: .public)\" remaining=\(item.remainingSeconds, privacy: .public)s isMasterServer=\(self.isMasterServer, privacy: .public)")
        if isMasterServer {
            server.broadcast(packet: packet)
        }
        broadcastToRelay(packet)
    }

    private func broadcastToRelay(_ packet: CuePacket) {
        guard isProxyEnabled, !proxyToken.isEmpty else { return }
        relayClient.broadcast(packet: packet)
        directPeerChannel.send(packet: packet)
    }

    private func updateControlAPI() {
        guard hostsControlAPI else { return }

        if isControlAPIEnabled {
            server.advertisedControlAPIPort = controlAPIPort
            server.advertisingTXTDidChange()
            let apiserver = controlAPIServer ?? makeControlAPIServer()
            apiserver.start(port: UInt16(clamping: controlAPIPort))
            controlAPIEventHub?.start()
        } else {
            controlAPIServer?.stop()
            controlAPIEventHub?.stop()
            isControlAPIRunning = false
            controlAPIClientCount = 0
        }
    }

    private func makeControlAPIServer() -> ControlAPIServer {
        let router = ControlAPIRouter(engine: self, connectedClientCount: { [weak self] in
            self?.controlAPIClientCount ?? 0
        })
        let server = ControlAPIServer(router: router)
        server.onStatusChanged = { [weak self] isListening in
            self?.isControlAPIRunning = isListening
        }
        server.onClientCountChanged = { [weak self] count in
            self?.controlAPIClientCount = count
        }
        controlAPIServer = server
        controlAPIEventHub = ControlAPIEventHub(engine: self, server: server, router: router)
        return server
    }

    private func handlePacket(_ packet: CuePacket) {
        guard packet.senderId != deviceId else { return }
        AppLog.cue.debug("handlePacket() type=\(packet.type.rawValue, privacy: .public) from=\(packet.senderId, privacy: .public) roleCues=\(packet.roleCues?.count ?? 0, privacy: .public) timerItem=\(packet.timerItem?.title ?? "nil", privacy: .public)")

        switch packet.type {
        case .cueUpdate, .timerUpdate, .pong:
            lastProducerPacketAt = Date()
            hasSyncedWithProducer = true
            isProducerLive = true
        default:
            break
        }

        switch packet.type {
        case .cueUpdate:
            if let updatedRoles = packet.roleCues {
                self.roles = updatedRoles
            }
            if let timer = packet.timerItem {
                self.activeTimerItem = timer
            }
            if let messages = packet.messages {
                addMessages(messages)
            }
        case .timerUpdate:
            if let timer = packet.timerItem {
                self.activeTimerItem = timer
            }
        case .messageBroadcast:
            if let msg = packet.message {
                addMessages([msg])
            }
        case .clearMessages:
            recentMessages = []
        case .ping:
            if isMasterServer {
                broadcastCatchUp()
            }
        case .pong:
            if let updatedRoles = packet.roleCues {
                self.roles = updatedRoles
            }
            if let timer = packet.timerItem {
                self.activeTimerItem = timer
            }
            if let messages = packet.messages {
                addMessages(messages)
            }
        default:
            break
        }
    }
}
