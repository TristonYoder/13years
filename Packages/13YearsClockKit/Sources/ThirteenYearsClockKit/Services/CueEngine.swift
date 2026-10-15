// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif
#if canImport(Network)
import Network
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class CueEngine: ObservableObject {
    @Published public var appMode: AppMode = .producerControl
    @Published public var currentDocumentURL: URL?
    @Published public var selectedMessageThreadId: String = "all"
    @Published private var messageReadAt: [String: Date] = [:]
    @Published public var roles: [RoleCue] = RoleCue.defaultRoles {
        didSet {
            persistRoles()
            rebroadcastIfNextItemChanged()
        }
    }
    @Published public var selectedRoleIds: Set<String> = ["default"]
    @Published public var waypoints: [Waypoint] = [] {
        didSet { persistWaypoints() }
    }
    @Published public var serviceSchedules: [ServiceSchedule] = [] {
        didSet { persistServiceSchedules() }
    }

    @Published public var planItems: [PCOTimerItem] = [] {
        didSet {
            persistCurrentFlow()
            rebroadcastIfNextItemChanged()
        }
    }
    @Published public var activeItemIndex: Int = 0 {
        didSet { persistCurrentFlow() }
    }
    @Published public var activeTimerItem: PCOTimerItem?
    @Published public var nextItem: PCOTimerItem?
    @Published var isActiveTimerActualOverride: Bool = false
    var actualOverrideItemId: String?
    @Published public var isPCOConnected: Bool = false
    @Published public var pcoUserName: String? {
        didSet { write(pcoUserName, forKey: Self.pcoUserNameDefaultsKey) }
    }
    private static let pcoUserNameDefaultsKey = "pcoUserName"
    @Published public var pcoLastError: String?
    @Published public var pcoNoteCategories: [PCOClient.PCONoteCategory] = []
    @Published public var isPCOLiveSyncEnabled: Bool = false {
        didSet { write(isPCOLiveSyncEnabled, forKey: Self.pcoLiveSyncDefaultsKey) }
    }
    private static let pcoLiveSyncDefaultsKey = "isPCOLiveSyncEnabled"

    @Published public var hourFormatThreshold: HourFormatThreshold = .over90Minutes {
        didSet { write(hourFormatThreshold.rawValue, forKey: Self.hourFormatThresholdDefaultsKey) }
    }
    private static let hourFormatThresholdDefaultsKey = "hourFormatThreshold"

    @Published public var pcoServiceTypes: [PCOClient.PCOServiceType] = []
    @Published public var pcoPlans: [PCOClient.PCOPlanInfo] = []
    @Published public var eventTimes: [EventTime] = [] {
        didSet { if eventTimes != oldValue { persistCurrentFlow() } }
    }
    @Published public var liveEventTimeId: String? {
        didSet { if liveEventTimeId != oldValue { persistCurrentFlow() } }
    }
    @Published public var isChangingEventTime: Bool = false
    @Published public var pcoSelectedServiceTypeId: String?
    @Published public var pcoPlanFilter: PCOClient.PCOPlanFilter = .future
    @Published public var pcoDefaultServiceTypeId: String? {
        didSet { write(pcoDefaultServiceTypeId, forKey: Self.defaultServiceTypeDefaultsKey) }
    }
    private static let defaultServiceTypeDefaultsKey = "pcoDefaultServiceTypeId"

    @Published public var pcoOAuthTokens: OAuthTokens? {
        didSet {
            pcoClient.tokens = pcoOAuthTokens
            if !isRemoteMirror { KeychainStore.setCodable(pcoOAuthTokens, forKey: Self.pcoTokensKeychainKey) }
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
    @Published public internal(set) var producerClockOffsetMs: Double?
    @Published public internal(set) var producerUTCOffsetSeconds: Int?
    @Published public var connectedMasterName: String?
    @Published public var connectedProducerHost: String?
    @Published public var connectedProducerAPIPort: Int?
    @Published public var isLANConnected: Bool = true
    @Published public private(set) var manualProducerHost: String? = LANUnicastClient.savedManualHost()
    @Published public internal(set) var producerLinkStatus: ProducerLinkStatus = .idle
    @Published public var isProducerLive: Bool = false
    @Published public var hasSyncedWithProducer: Bool = false
    @Published public internal(set) var producerSignal: ProducerSignal = .lost
    var lastProducerPacketMono: Double?
    @Published public var isProxyEnabled: Bool = false {
        didSet {
            write(isProxyEnabled, forKey: Self.proxyEnabledDefaultsKey)
            updateRelayConnection()
        }
    }
    @Published public var proxyToken: String = "" {
        didSet {
            if !isRemoteMirror { KeychainStore.setString(proxyToken, forKey: Self.proxyTokenKeychainKey) }
            updateRelayConnection()
        }
    }
    @Published public private(set) var plotipharRelayHost: String = RelayHostPolicy.defaultHost {
        didSet {
            write(plotipharRelayHost, forKey: Self.relayHostDefaultsKey)
            updateRelayConnection()
        }
    }
    private static let proxyEnabledDefaultsKey = "isProxyEnabled"
    private static let proxyTokenKeychainKey = "plotipharProxyToken"
    private static let relayHostDefaultsKey = "plotipharRelayHost"

    @Published public var isControlAPIEnabled: Bool = false {
        didSet {
            write(isControlAPIEnabled, forKey: Self.controlAPIEnabledDefaultsKey)
            updateControlAPI()
        }
    }
    @Published public var controlAPIPort: Int = Int(ControlAPIServer.defaultPort) {
        didSet {
            write(controlAPIPort, forKey: Self.controlAPIPortDefaultsKey)
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

    nonisolated private static let deviceIdDefaultsKey = "cueEngineDeviceId"
    let deviceId: String
    public var deviceIdentifier: String { deviceId }
    var timeZoneProvider: () -> TimeZone = { TimeZone.current }

    func stampUtcOffset(_ packet: inout CuePacket) {
        packet.utcOffsetSeconds = timeZoneProvider().secondsFromGMT()
    }

    nonisolated public static func persistentDeviceId() -> String {
        if let existing = UserDefaults.standard.string(forKey: CueEngine.deviceIdDefaultsKey) {
            return existing
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: CueEngine.deviceIdDefaultsKey)
        return id
    }

    public let isRemoteMirror: Bool
    public weak var remoteCommands: RemoteProducerCommanding?
    var pendingPCOSignIn: PendingPCOSignIn?
    var pcoTokenExchange: @Sendable (_ code: String, _ verifier: String) async throws -> OAuthTokens = { code, verifier in
        try await OAuthTokenExchange.exchange(code: code, verifier: verifier)
    }
    var pcoSignInClock: () -> Date = { Date() }
    var pcoSignInFollowUp: ((CueEngine) async throws -> Void)?
    @Published public var remoteProducerName: String?
    @Published public var remoteControllerCount: Int = 0

    let server = LocalCueServer()
    let client = LocalCueClient()
    private let relayClient = PlotipharRelayClient()
    private let directPeerChannel = DirectPeerChannel()
    #if canImport(Network)
    private var controlAPIServer: ControlAPIServer?
    private var controlAPIEventHub: ControlAPIEventHub?
    #endif
    private let hostsControlAPI: Bool
    private let pcoClient = PCOClient()
    private let plotipharPairingClient = PlotipharPairingClient()
    private let plotipharClient = PlotipharClient()
    private var plotipharPollTask: Task<Void, Never>?
    private var tickTimerHandle: MainLoopTimer?
    private var clockChangeObserver: NSObjectProtocol?
    var syncV2 = SyncV2State()
    var outboundObserver: ((CuePacket, OutboundTarget) -> Void)?

    public init(mirroring commands: RemoteProducerCommanding?) {
        self.isMasterServer = true
        self.hostsControlAPI = false
        self.isRemoteMirror = true
        self.remoteCommands = commands
        self.deviceId = UUID().uuidString
        self.roles = []
        self.selectedRoleIds = []
    }

    public init(isMasterServer: Bool = true, hostsControlAPI: Bool = false, startsNetworking: Bool = true, defersLANServing: Bool = false) {
        self.isMasterServer = isMasterServer
        self.isLANServingHeld = defersLANServing
        self.hostsControlAPI = hostsControlAPI
        self.isRemoteMirror = false
        self.deviceId = Self.persistentDeviceId()
        self.pcoDefaultServiceTypeId = UserDefaults.standard.string(forKey: Self.defaultServiceTypeDefaultsKey)
        self.hourFormatThreshold = UserDefaults.standard.string(forKey: Self.hourFormatThresholdDefaultsKey)
            .flatMap(HourFormatThreshold.init(rawValue:)) ?? .over90Minutes

        self.pcoOAuthTokens = KeychainStore.codable(OAuthTokens.self, forKey: Self.pcoTokensKeychainKey)
        self.pcoUserName = UserDefaults.standard.string(forKey: Self.pcoUserNameDefaultsKey)
        self.isPCOConnected = pcoOAuthTokens != nil
        KeychainStore.setString(nil, forKey: "pcoSecret")
        self.plotipharRelayHost = UserDefaults.standard.string(forKey: Self.relayHostDefaultsKey).flatMap(RelayHostPolicy.normalized) ?? RelayHostPolicy.defaultHost
        self.proxyToken = KeychainStore.string(forKey: Self.proxyTokenKeychainKey) ?? ""
        self.isProxyEnabled = UserDefaults.standard.object(forKey: Self.proxyEnabledDefaultsKey) != nil
            ? UserDefaults.standard.bool(forKey: Self.proxyEnabledDefaultsKey)
            : false
        if hostsControlAPI {
            self.controlAPIPort = UserDefaults.standard.object(forKey: Self.controlAPIPortDefaultsKey) as? Int ?? Int(ControlAPIServer.defaultPort)
            self.isControlAPIEnabled = UserDefaults.standard.bool(forKey: Self.controlAPIEnabledDefaultsKey)
        }
        if FeatureFlags.plotiphar && !proxyToken.isEmpty {
            plotipharPairingState = .approved
        }

        restoreRoles()
        restoreWaypoints()
        restoreServiceSchedules()
        restoreMessages()
        restoreNotificationsClearedAt()
        restorePersistedFlow()
        setupDefaultPlan()
        if startsNetworking { startNetworking() }
        relayClient.onPacketReceived = { [weak self] packet in
            self?.handlePacket(packet, origin: .relay)
        }
        relayClient.onConnected = { [weak self] in
            self?.relayDidConnect()
        }
        relayClient.onDisconnected = { [weak self] in
            self?.relayDidDisconnect()
        }
        #if canImport(Darwin)
        clockChangeObserver = NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemClockDidChange() }
        }
        #endif
        relayClient.onTextMessageReceived = { [weak self] data in
            guard let peerHello = PeerHello.decode(from: data) else { return }
            self?.directPeerChannel.connect(to: peerHello)
        }
        directPeerChannel.onPacketReceived = { [weak self] packet in
            self?.handlePacket(packet, origin: .relay)
        }

        refreshPCOTokensIfNeeded()

        if UserDefaults.standard.bool(forKey: Self.pcoLiveSyncDefaultsKey) {
            enablePCOLiveSync()
        }

        updateControlAPI()
    }

    private func write(_ value: Any?, forKey key: String) {
        guard !isRemoteMirror else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private func erase(forKey key: String) {
        guard !isRemoteMirror else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func refreshPCOTokensIfNeeded() {
        guard let tokens = pcoOAuthTokens, tokens.isExpired else { return }
        Task {
            do {
                self.pcoOAuthTokens = try await OAuthTokenExchange.refresh(tokens.refreshToken)
            } catch {
                AppLog.cue.error("CueEngine: PCO token refresh failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    public private(set) var isLANServingSuspended = false
    public private(set) var isLANServingHeld = false

    public private(set) var isLANServing = false

    public var isLANServingBlocked: Bool { isLANServingSuspended || isLANServingHeld }

    public func setLANServingSuspended(_ suspended: Bool) {
        guard !isRemoteMirror, isLANServingSuspended != suspended else { return }
        isLANServingSuspended = suspended
        applyLANServingGate()
    }

    public func setLANServingHeld(_ held: Bool) {
        guard !isRemoteMirror, isLANServingHeld != held else { return }
        isLANServingHeld = held
        applyLANServingGate()
    }

    private func applyLANServingGate() {
        if isLANServingBlocked {
            server.stop()
            isLANServing = false
        } else if isMasterServer {
            startNetworking()
        }
    }

    public func startNetworking() {
        guard !isRemoteMirror else { return }
        AppLog.cue.info("startNetworking() — isMasterServer=\(self.isMasterServer, privacy: .public)")
        isProducerLive = false
        refreshProducerClockOffset()
        hasSyncedWithProducer = false
        resetClientSyncState()
        syncV2.anchor = nil
        syncV2.lastBroadcastRoles = nil
        syncV2.relayHasV2Peer = false
        cancelProducerDisplayTick()
        lastProducerPacketMono = nil
        producerSignal = isMasterServer ? .live : .lost
        connectedProducerHost = nil
        connectedProducerAPIPort = nil
        if isMasterServer {
            client.stop()
            if isLANServingBlocked {
                server.stop()
                isLANServing = false
                return
            }
            server.start()
            isLANServing = true
            server.advertisedControlAPIPort = hostsControlAPI && isControlAPIEnabled ? controlAPIPort : nil
            server.advertisedDeviceId = deviceId
            server.onPacketReceived = { [weak self] packet, connection in
                self?.handlePacket(packet, origin: .lanServer(connection))
            }
            server.onStatusChanged = { [weak self] isJoined in
                self?.isLANConnected = isJoined
            }
        } else {
            server.stop()
            isLANServing = false
            client.start()
            client.onPacketReceived = { [weak self] packet in
                self?.handlePacket(packet, origin: .lanClient)
            }
            client.onStatusChanged = { [weak self] isJoined in
                self?.lanClientStatusChanged(isJoined)
            }
            client.onLinkStatusChanged = { [weak self] status in
                self?.producerLinkStatus = status
            }
            client.onMasterDiscovered = { [weak self] name in
                self?.connectedMasterName = name
                self?.syncV2.estimator.clearSamples()
                self?.requestCatchUp()
                self?.startSyncBurst()
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
        guard !isRemoteMirror else { return }
        isMasterServer.toggle()
        startNetworking()
    }

    public func signInWithPCO() {
        if isRemoteMirror {
            signInWithPCOThroughRemote()
            return
        }
        Task {
            do {
                let signIn = OAuthSignIn()
                let tokens = try await signIn.signIn()
                try await finishPCOSignIn(with: tokens)
            } catch {
                AppLog.cue.error("CueEngine: PCO OAuth sign-in error: \(error.localizedDescription, privacy: .private)")
                if case OAuthError.userCancelled = error { return }
                self.pcoLastError = error.localizedDescription
            }
        }
    }

    func finishPCOSignIn(with tokens: OAuthTokens) async throws {
        pcoOAuthTokens = tokens
        isPCOConnected = true
        pcoLastError = nil
        if let pcoSignInFollowUp {
            try await pcoSignInFollowUp(self)
            return
        }
        let person = try await pcoClient.fetchCurrentPerson()
        pcoUserName = person.name

        await fetchPCOServiceTypesAsync()
        if let defaultId = pcoDefaultServiceTypeId, pcoServiceTypes.contains(where: { $0.id == defaultId }) {
            selectPCOServiceType(defaultId)
        }
    }

    public func signOutOfPCO() {
        if isRemoteMirror {
            remoteCommands?.send(.pcoSignOut)
            return
        }
        isPCOLiveSyncEnabled = false
        pcoOAuthTokens = nil
        pcoUserName = nil
        isPCOConnected = false
        pcoServiceTypes = []
        pcoPlans = []
        pcoSelectedServiceTypeId = nil
    }

    public func fetchPCOPlan(serviceTypeId: String, planId: String) {
        if isRemoteMirror {
            remoteCommands?.send(.pcoSync(serviceTypeId: serviceTypeId, planId: planId))
            return
        }
        if planId != currentPCOPlanId {
            disablePCOLiveSync()
            eventTimes.removeAll { $0.pcoPlanTimeId != nil }
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
                await refreshPCOPlanTimes(serviceTypeId: serviceTypeId, planId: planId)
            } catch {
                pcoLastError = error.localizedDescription
                AppLog.cue.error("CueEngine: PCO sync error: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    public func clearPCOServiceTypeSelection() {
        if isRemoteMirror {
            remoteCommands?.send(.pcoSelectServiceType(id: nil))
            return
        }
        pcoSelectedServiceTypeId = nil
    }

    public func fetchPCOServiceTypes() {
        if isRemoteMirror {
            remoteCommands?.send(.pcoRefreshServiceTypes)
            return
        }
        Task { await fetchPCOServiceTypesAsync() }
    }

    private func fetchPCOServiceTypesAsync() async {
        do {
            pcoServiceTypes = try await pcoClient.fetchServiceTypes()
            pcoLastError = nil
        } catch {
            AppLog.cue.error("CueEngine: fetchPCOServiceTypes error: \(error.localizedDescription, privacy: .private)")
            pcoLastError = error.localizedDescription
        }
    }

    public func selectPCOServiceType(_ serviceTypeId: String) {
        if isRemoteMirror {
            remoteCommands?.send(.pcoSelectServiceType(id: serviceTypeId))
            return
        }
        pcoSelectedServiceTypeId = serviceTypeId
        fetchPCOPlans()
    }

    public func fetchPCOPlans() {
        if isRemoteMirror {
            remoteCommands?.send(.pcoRefreshPlans)
            return
        }
        guard let serviceTypeId = pcoSelectedServiceTypeId else { return }
        Task {
            do {
                pcoPlans = try await pcoClient.fetchPlans(serviceTypeId: serviceTypeId, filter: pcoPlanFilter)
                pcoLastError = nil
            } catch {
                AppLog.cue.error("CueEngine: fetchPCOPlans: FAILED — \(String(describing: error), privacy: .private)")
                pcoLastError = error.localizedDescription
            }
        }
    }

    public func setPlanFilter(_ filter: PCOClient.PCOPlanFilter) {
        if isRemoteMirror {
            remoteCommands?.send(.pcoPlanFilter(filter.rawValue))
            return
        }
        pcoPlanFilter = filter
        fetchPCOPlans()
    }

    public func setDefaultServiceType(_ serviceTypeId: String?) {
        if isRemoteMirror {
            remoteCommands?.send(.pcoDefaultServiceType(id: serviceTypeId))
            return
        }
        pcoDefaultServiceTypeId = serviceTypeId
    }

    public func startPlotipharPairing() {
        guard FeatureFlags.plotiphar, !isRemoteMirror else { return }
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
        guard !isRemoteMirror else { return }
        plotipharPollTask?.cancel()
        plotipharPollTask = nil
        plotipharPairingState = .idle
    }

    @discardableResult
    public func setRelayHost(_ raw: String) -> Bool {
        guard !isRemoteMirror, let host = RelayHostPolicy.normalized(raw) else { return false }
        guard host.caseInsensitiveCompare(plotipharRelayHost) != .orderedSame else { return true }
        cancelPlotipharPairing()
        isProxyEnabled = false
        proxyToken = ""
        plotipharRelayHost = host
        return true
    }

    public func disconnectPlotiphar() {
        guard !isRemoteMirror else { return }
        cancelPlotipharPairing()
        proxyToken = ""
        isProxyEnabled = false
    }

    private func updateRelayConnection() {
        guard !isRemoteMirror else { return }
        relayClient.relayHost = plotipharRelayHost
        relayClient.token = proxyToken

        if FeatureFlags.plotiphar && isProxyEnabled && !proxyToken.isEmpty {
            relayClient.start()
            directPeerChannel.start()
            broadcastDirectPeerHello()
        } else {
            relayClient.stop()
            directPeerChannel.stop()
        }
    }

    private func broadcastDirectPeerHello() {
        guard FeatureFlags.plotiphar, isProxyEnabled, !proxyToken.isEmpty else { return }
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
        #elseif canImport(UIKit)
        return UIDevice.current.name
        #else
        return ProcessInfo.processInfo.environment["THIRTEEN_NAME"] ?? ProcessInfo.processInfo.hostName
        #endif
    }

    public func makeDocument() -> ProducerDocument {
        ProducerDocument(
            roles: roles,
            selectedRoleIds: selectedRoleIds.sorted(),
            waypoints: waypoints,
            serviceSchedules: serviceSchedules,
            planItems: planItems,
            activeItemIndex: activeItemIndex,
            eventTimes: eventTimes,
            liveEventTimeId: liveEventTimeId,
            settings: .init(
                hourFormatThreshold: hourFormatThreshold,
                pcoDefaultServiceTypeId: pcoDefaultServiceTypeId,
                plotipharRelayHost: plotipharRelayHost
            )
        )
    }

    public func resetToNewDocument() {
        guard !isRemoteMirror else { return }
        var blank = makeDocument()
        blank.roles = []
        blank.selectedRoleIds = nil
        blank.waypoints = []
        blank.serviceSchedules = []
        blank.planItems = []
        blank.activeItemIndex = 0
        blank.eventTimes = []
        blank.liveEventTimeId = nil
        apply(blank)
        currentDocumentURL = nil
    }

    public func apply(_ document: ProducerDocument) {
        guard !isRemoteMirror else { return }
        applyConfiguration(of: document)
        applyPlan(of: document)
        broadcastTimerUpdate()
    }

    func applyConfiguration(of document: ProducerDocument) {
        roles = document.roles.isEmpty
            ? RoleCue.defaultRoles
            : document.roles.map { role in
                var role = role
                role.state = .off
                return role
            }
        let knownRoleIds = Set(roles.map(\.id))
        let restored = document.selectedRoleIds.map(Set.init) ?? selectedRoleIds
        selectedRoleIds = restored.intersection(knownRoleIds)
        if selectedRoleIds.isEmpty, let first = roles.first { selectedRoleIds = [first.id] }

        waypoints = document.waypoints
        serviceSchedules = sortedByStartsAt(document.serviceSchedules)
        hourFormatThreshold = document.settings.hourFormatThreshold
        pcoDefaultServiceTypeId = document.settings.pcoDefaultServiceTypeId
    }

    func applyPlan(of document: ProducerDocument) {
        restoreEventTimes(document.eventTimes, liveId: document.liveEventTimeId)
        var items = document.planItems
        for index in items.indices { items[index].isRunning = false }
        planItems = items
        if items.isEmpty {
            activeItemIndex = 0
            activeTimerItem = nil
        } else {
            activeItemIndex = min(max(document.activeItemIndex, 0), items.count - 1)
            activeTimerItem = items[activeItemIndex]
        }
    }

    public func importFlow(title: String?, items: [PCOTimerItem]) {
        if isRemoteMirror {
            _ = loadPlanIntoRemote(title: title, items: items)
            return
        }
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
        if isRemoteMirror {
            remoteCommands?.send(.planItemAdd(title: title, itemType: itemType, lengthInSeconds: lengthInSeconds, isDurationActual: isDurationActual))
            return
        }
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
        if isRemoteMirror {
            var fields: [String: Any] = ["title": title, "itemType": itemType, "lengthInSeconds": lengthInSeconds]
            if let notes { fields["notes"] = notes }
            if let isDurationActual { fields["isDurationActual"] = isDurationActual }
            remoteCommands?.send(.planItemUpdate(id: id, body: RemoteCommand.body(fields)))
            return
        }
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
        guard !isRemoteMirror else { return }
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
        guard !isRemoteMirror else { return }
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
        if isRemoteMirror {
            remoteCommands?.send(.planItemRemove(id: id))
            return
        }
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
        if isRemoteMirror {
            var reordered = planItems
            reordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
            remoteCommands?.send(.planReorder(itemIds: reordered.map(\.id)))
            return
        }
        let activeId = activeTimerItem?.id
        planItems.move(fromOffsets: fromOffsets, toOffset: toOffset)
        renumberPlanItems()

        if let activeId, let newIndex = planItems.firstIndex(where: { $0.id == activeId }) {
            activeItemIndex = newIndex
        }
    }

    public func setActivePlanItem(id: String) {
        if isRemoteMirror {
            remoteCommands?.send(.planActivate(itemId: id))
            return
        }
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
        if isRemoteMirror {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            remoteCommands?.send(.waypointCreate(name: trimmed))
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let slug = Waypoint.slug(for: trimmed)
        guard !slug.isEmpty, !waypoints.contains(where: { $0.slug == slug }) else { return nil }
        let waypoint = Waypoint(name: trimmed)
        waypoints.append(waypoint)
        AppLog.cue.info("addWaypoint(\"\(trimmed, privacy: .private)\") -> \(waypoint.id, privacy: .public)")
        return waypoint
    }

    public func renameWaypoint(id: String, name: String) {
        if isRemoteMirror {
            remoteCommands?.send(.waypointRename(ref: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines)))
            return
        }
        guard let index = waypoints.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newSlug = Waypoint.slug(for: trimmed)
        guard !newSlug.isEmpty,
              !waypoints.contains(where: { $0.id != id && $0.slug == newSlug }) else { return }
        waypoints[index].name = trimmed
    }

    public func removeWaypoint(id: String) {
        if isRemoteMirror {
            remoteCommands?.send(.waypointDelete(ref: id))
            return
        }
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
        if isRemoteMirror {
            remoteCommands?.send(.waypointAssign(ref: waypointId, itemId: itemId))
            return
        }
        guard waypoints.contains(where: { $0.id == waypointId }) else { return }
        for index in planItems.indices where planItems[index].waypointIds.contains(waypointId) {
            planItems[index].waypointIds.removeAll { $0 == waypointId }
        }
        if let itemId, let targetIndex = planItems.firstIndex(where: { $0.id == itemId }) {
            planItems[targetIndex].waypointIds.append(waypointId)
        }
    }

    public func setWaypointIds(_ waypointIds: [String], forItemId itemId: String) {
        if isRemoteMirror {
            remoteCommands?.send(.itemWaypoints(itemId: itemId, waypointIds: waypointIds))
            return
        }
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

    public func createWaypointAndAssign(name: String, toItemId itemId: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isRemoteMirror {
            remoteCommands?.send(.waypointCreateAndAssign(name: trimmed, itemId: itemId))
            return
        }
        if let waypoint = addWaypoint(name: trimmed) {
            assignWaypoint(waypoint.id, toItemId: itemId)
        }
    }

    @discardableResult
    public func fireWaypoint(_ raw: String, startTimer: Bool = true) -> WaypointFireResult {
        if isRemoteMirror {
            guard let waypoint = waypoint(matching: raw) else { return .unknownWaypoint }
            guard let itemId = itemId(forWaypointId: waypoint.id) else { return .unassigned(waypointId: waypoint.id) }
            remoteCommands?.send(.waypointGo(ref: waypoint.id, startTimer: startTimer))
            return .fired(itemId: itemId)
        }
        guard let waypoint = waypoint(matching: raw) else {
            AppLog.cue.info("fireWaypoint(\"\(raw, privacy: .private)\") -> unknown waypoint")
            return .unknownWaypoint
        }
        guard let itemId = itemId(forWaypointId: waypoint.id) else {
            AppLog.cue.info("fireWaypoint(\"\(raw, privacy: .private)\") -> waypoint \(waypoint.id, privacy: .public) has no item assigned this week")
            return .unassigned(waypointId: waypoint.id)
        }
        setActivePlanItem(id: itemId)
        if let item = activeTimerItem, item.isRunning != startTimer {
            toggleTimerRunning()
        }
        AppLog.cue.info("fireWaypoint(\"\(raw, privacy: .private)\") -> item \(itemId, privacy: .public)")
        return .fired(itemId: itemId)
    }

    public func nextWaypointItemId() -> String? {
        guard activeItemIndex + 1 < planItems.count else { return nil }
        return planItems[(activeItemIndex + 1)...].first { !$0.waypointIds.isEmpty }?.id
    }

    @discardableResult
    public func fireNextWaypoint(startTimer: Bool = true) -> String? {
        if isRemoteMirror {
            guard let itemId = nextWaypointItemId() else { return nil }
            remoteCommands?.send(.waypointNext(startTimer: startTimer))
            return itemId
        }
        guard let itemId = nextWaypointItemId() else { return nil }
        setActivePlanItem(id: itemId)
        if let item = activeTimerItem, item.isRunning != startTimer {
            toggleTimerRunning()
        }
        return itemId
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
        if isRemoteMirror {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty, goLiveOffsetSeconds >= 0 else { return nil }
            var fields: [String: Any] = [
                "title": trimmedTitle,
                "startsAt": ISO8601DateFormatter().string(from: startsAt),
                "goLiveOffsetSeconds": goLiveOffsetSeconds,
                "recurrence": recurrence.rawValue,
                "isEnabled": isEnabled,
            ]
            if let pcoServiceTypeId { fields["pcoServiceTypeId"] = pcoServiceTypeId }
            if let pcoPlanId { fields["pcoPlanId"] = pcoPlanId }
            remoteCommands?.send(.scheduleCreate(body: RemoteCommand.body(fields)))
            return nil
        }
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
        AppLog.cue.info("addServiceSchedule(\"\(trimmed, privacy: .private)\") -> \(schedule.id, privacy: .public)")
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
        if isRemoteMirror {
            var fields: [String: Any] = [:]
            if let title { fields["title"] = title }
            if let startsAt { fields["startsAt"] = ISO8601DateFormatter().string(from: startsAt) }
            if let goLiveOffsetSeconds { fields["goLiveOffsetSeconds"] = goLiveOffsetSeconds }
            if let pcoServiceTypeId { fields["pcoServiceTypeId"] = pcoServiceTypeId ?? "" }
            if let pcoPlanId { fields["pcoPlanId"] = pcoPlanId ?? "" }
            if let recurrence { fields["recurrence"] = recurrence.rawValue }
            if let isEnabled { fields["isEnabled"] = isEnabled }
            remoteCommands?.send(.scheduleUpdate(id: id, body: RemoteCommand.body(fields)))
            return
        }
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
        if isRemoteMirror {
            remoteCommands?.send(.scheduleDelete(id: id))
            return
        }
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
        if isRemoteMirror {
            remoteCommands?.send(.scheduleGoLive(id: id))
            return
        }
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
        AppLog.cue.info("goLiveWithSchedule(\"\(schedule.title, privacy: .private)\") -> \(schedule.id, privacy: .public)")
    }

    private func checkServiceSchedules() {
        guard !isRemoteMirror else { return }
        guard isMasterServer else { return }
        let now = Date()
        for schedule in serviceSchedules where schedule.shouldFire(at: now) {
            goLiveWithSchedule(id: schedule.id)
        }
    }

    public func enablePCOLiveSync() {
        if isRemoteMirror {
            remoteCommands?.send(.pcoLiveSync(true))
            return
        }
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
            if !eventTimes.contains(where: { $0.pcoPlanTimeId != nil }) {
                await refreshPCOPlanTimes(serviceTypeId: serviceTypeId, planId: planId)
            }
            syncElapsedTimeFromPCOLive()
        }
    }

    private func refreshPCOPlanTimes(serviceTypeId: String, planId: String) async {
        do {
            let times = try await pcoClient.fetchPlanTimes(serviceTypeId: serviceTypeId, planId: planId)
                .filter(\.isService)
            guard currentPCOPlanId == planId, !times.isEmpty else { return }
            let previousLive = liveEventTime?.pcoPlanTimeId
            eventTimes = times.map { time in
                EventTime(
                    id: time.id,
                    name: time.name,
                    day: time.startsAt.map { EventDay(date: $0) },
                    startTime: time.startsAt.map { TimeOfDay(date: $0) },
                    pcoPlanTimeId: time.id
                )
            }
            liveEventTimeId = eventTimes.first(where: { $0.pcoPlanTimeId == previousLive })?.id
        } catch {
            AppLog.cue.error("CueEngine: fetchPlanTimes error: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func noteLivePCOPlanTime(_ planTimeId: String?) {
        guard let planTimeId,
              let match = eventTimes.first(where: { $0.pcoPlanTimeId == planTimeId }),
              liveEventTimeId != match.id else { return }
        liveEventTimeId = match.id
    }

    func jumpPCOLive(toEventTime eventTimeId: String, itemId targetItemId: String) {
        guard isPCOLiveSyncEnabled,
              let targetPlanTimeId = eventTimes.first(where: { $0.id == eventTimeId })?.pcoPlanTimeId,
              let serviceTypeId = currentPCOServiceTypeId,
              let planId = currentPCOPlanId,
              !isChangingEventTime else { return }
        isChangingEventTime = true
        Task {
            defer { isChangingEventTime = false }
            await takeLiveControlIfNeeded(serviceTypeId: serviceTypeId, planId: planId)
            guard isPCOLiveSyncEnabled else { return }
            let pcoTimes = eventTimes.compactMap(\.pcoPlanTimeId)
            let timeOrder = Dictionary(pcoTimes.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
            guard let targetTime = timeOrder[targetPlanTimeId],
                  let targetItem = planItems.firstIndex(where: { $0.id == targetItemId }) else { return }

            let maxSteps = (planItems.count + 1) * (pcoTimes.count + 1)
            var lastDirection: PCOClient.PCOLiveDirection?
            do {
                for _ in 0..<maxSteps {
                    guard let current = try await pcoClient.fetchCurrentItemTime(serviceTypeId: serviceTypeId, planId: planId) else { break }
                    guard let currentTime = current.planTimeId.flatMap({ timeOrder[$0] }) else { break }
                    let currentItem = current.itemId.flatMap { id in planItems.firstIndex(where: { $0.id == id }) } ?? -1
                    if currentTime == targetTime && currentItem == targetItem {
                        syncElapsedTimeFromPCOLive()
                        break
                    }
                    let direction: PCOClient.PCOLiveDirection =
                        (currentTime, currentItem) < (targetTime, targetItem) ? .next : .previous
                    if let lastDirection, lastDirection != direction { break }
                    lastDirection = direction
                    try await pcoClient.stepLiveItem(serviceTypeId: serviceTypeId, planId: planId, direction: direction)
                }
                pcoLastError = nil
            } catch {
                pcoLastError = error.localizedDescription
            }
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
        if isRemoteMirror {
            remoteCommands?.send(.pcoLiveSync(false))
            return
        }
        guard isPCOLiveSyncEnabled else { return }
        isPCOLiveSyncEnabled = false
        guard let serviceTypeId = currentPCOServiceTypeId, let planId = currentPCOPlanId else { return }
        Task {
            do {
                try await pcoClient.toggleLiveControl(serviceTypeId: serviceTypeId, planId: planId)
            } catch {
                AppLog.cue.error("CueEngine: Failed to release PCO Live control: \(error.localizedDescription, privacy: .private)")
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
                noteLivePCOPlanTime(currentItemTime.planTimeId)

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

    var currentPCOServiceTypeId: String? {
        activeTimerItem?.pcoServiceTypeId ?? planItems.first?.pcoServiceTypeId
    }

    var currentPCOPlanId: String? {
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
            noteLivePCOPlanTime(currentItemTime.planTimeId)

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
        if isRemoteMirror {
            remoteCommands?.send(.timerAdjust(seconds: delta))
            return
        }
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
        if isRemoteMirror {
            remoteCommands?.send(.timerRemaining(seconds: seconds))
            return
        }
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
        if isRemoteMirror {
            remoteCommands?.send(.itemDurationActual(itemId: id, isActual: isActual))
            return
        }
        if let index = planItems.firstIndex(where: { $0.id == id }) {
            planItems[index].isDurationActual = isActual
        }
        if activeTimerItem?.id == id {
            activeTimerItem?.isDurationActual = isActual
            refreshTimerAnchor()
            publishTimerAnchorToV2()
        }
    }

    public func setActiveTimerActualOverride(_ isActual: Bool) {
        if isRemoteMirror {
            remoteCommands?.send(.timerActualOverride(isActual))
            return
        }
        guard let item = activeTimerItem else { return }
        isActiveTimerActualOverride = isActual
        actualOverrideItemId = isActual ? item.id : nil
        broadcastState()
        refreshTimerAnchor()
        publishTimerAnchorToV2()
    }

    public var activeTimerActualForDisplay: Bool {
        guard let item = activeTimerItem else { return false }
        if actualOverrideItemId == item.id { return isActiveTimerActualOverride }
        return item.isDurationActual
    }

    var activeTimerItemForBroadcast: PCOTimerItem? {
        guard var item = activeTimerItem else { return nil }
        item.isDurationActual = activeTimerActualForDisplay
        return item
    }

    public func nextPlanItem(startTimer: Bool = true) {
        if isRemoteMirror {
            remoteCommands?.send(.planNext(startTimer: startTimer))
            return
        }
        guard !planItems.isEmpty, let targetIndex = nextSelectableIndex(after: activeItemIndex) else { return }
        let steps = realItemStepCount(from: activeItemIndex, to: targetIndex)
        activeItemIndex = targetIndex
        var item = planItems[activeItemIndex]
        item.servicePlanTitle = activeTimerItem?.servicePlanTitle
        item.isRunning = startTimer
        activeTimerItem = item
        broadcastTimerUpdate()
        mirrorToPCOLive(direction: .next, count: steps, targetItemId: item.id)
    }

    public func previousPlanItem(startTimer: Bool = true) {
        if isRemoteMirror {
            remoteCommands?.send(.planPrevious(startTimer: startTimer))
            return
        }
        guard !planItems.isEmpty, let targetIndex = previousSelectableIndex(before: activeItemIndex) else { return }
        let steps = realItemStepCount(from: activeItemIndex, to: targetIndex)
        activeItemIndex = targetIndex
        var item = planItems[activeItemIndex]
        item.servicePlanTitle = activeTimerItem?.servicePlanTitle
        item.isRunning = startTimer
        activeTimerItem = item
        broadcastTimerUpdate()
        mirrorToPCOLive(direction: .previous, count: steps, targetItemId: item.id)
    }

    var derivedNextPlanItem: PCOTimerItem? {
        guard activeTimerItem != nil, planItems.indices.contains(activeItemIndex),
              let index = nextSelectableIndex(after: activeItemIndex) else { return nil }
        return planItems[index]
    }

    var nextItemForBroadcast: CueNextItem? {
        guard let item = derivedNextPlanItem else { return nil }
        return CueNextItem(item: item, noteCategories: Set(roles.flatMap(\.assignedNoteCategories)))
    }

    private func rebroadcastIfNextItemChanged() {
        guard isMasterServer, !isRemoteMirror, let active = activeTimerItem,
              planItems.indices.contains(activeItemIndex), planItems[activeItemIndex].id == active.id,
              nextItemForBroadcast != syncV2.lastNextItem else { return }
        broadcastTimerUpdate()
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

    public var isAtStartOfPlan: Bool {
        planItems.isEmpty || previousSelectableIndex(before: activeItemIndex) == nil
    }

    public var canLoadNextService: Bool {
        currentPCOServiceTypeId != nil && currentPCOPlanId != nil
    }

    public func loadNextService() {
        if isRemoteMirror {
            remoteCommands?.send(.planNextService)
            return
        }
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
        if isRemoteMirror {
            guard let item = activeTimerItem, !item.isHeader else { return }
            remoteCommands?.send(item.isRunning ? .timerPause : .timerStart)
            return
        }
        guard var item = activeTimerItem, !item.isHeader else { return }
        item.isRunning.toggle()
        activeTimerItem = item
        broadcastTimerUpdate()
    }

    public func resetTimer() {
        if isRemoteMirror {
            guard let item = activeTimerItem, !item.isHeader else { return }
            remoteCommands?.send(.timerReset)
            return
        }
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
        if isRemoteMirror {
            var next = selectedRoleIds
            if next.contains(roleId) {
                guard next.count > 1 else { return }
                next.remove(roleId)
            } else {
                next.insert(roleId)
            }
            selectedRoleIds = next
            remoteCommands?.send(.select(roleIds: next.sorted()))
            return
        }
        if selectedRoleIds.contains(roleId) {
            if selectedRoleIds.count > 1 {
                selectedRoleIds.remove(roleId)
            }
        } else {
            selectedRoleIds.insert(roleId)
        }
    }

    public func setCueForSelectedRoles(_ state: CueState) {
        if isRemoteMirror {
            for id in selectedRoleIds.sorted() {
                remoteCommands?.send(.cueRole(id: id, state: state))
            }
            return
        }
        for index in roles.indices {
            if selectedRoleIds.contains(roles[index].id) {
                roles[index].state = state
                roles[index].lastUpdated = Date()
            }
        }
        broadcastState()
    }

    public func setCueForRole(id: String, state: CueState) {
        if isRemoteMirror {
            remoteCommands?.send(.cueRole(id: id, state: state))
            return
        }
        if let index = roles.firstIndex(where: { $0.id == id }) {
            roles[index].state = state
            roles[index].lastUpdated = Date()
            broadcastState()
        }
    }

    public func setNoteCategory(forRoleId roleId: String, category: String, isOn: Bool) {
        if isRemoteMirror {
            guard let role = roles.first(where: { $0.id == roleId }) else { return }
            var categories = role.assignedNoteCategories
            if isOn {
                if !categories.contains(category) { categories.append(category) }
            } else {
                categories.removeAll { $0 == category }
            }
            remoteCommands?.send(.roleUpdate(id: roleId, body: RemoteCommand.body(["assignedNoteCategories": categories])))
            return
        }
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
        if isRemoteMirror {
            remoteCommands?.send(.roleUpdate(id: roleId, body: RemoteCommand.body(["personName": personName ?? ""])))
            return
        }
        guard let index = roles.firstIndex(where: { $0.id == roleId }) else { return }
        roles[index].personName = personName
        broadcastState()
    }

    @discardableResult
    public func addRole(name: String) -> RoleCue {
        if isRemoteMirror {
            remoteCommands?.send(.roleCreate(name: name))
            return RoleCue(name: name)
        }
        let role = RoleCue(name: name)
        roles.append(role)
        broadcastState()
        return role
    }

    public func renameRole(id: String, name: String) {
        if isRemoteMirror {
            remoteCommands?.send(.roleUpdate(id: id, body: RemoteCommand.body(["name": name])))
            return
        }
        guard let index = roles.firstIndex(where: { $0.id == id }) else { return }
        roles[index].name = name
        broadcastState()
    }

    public func removeRole(id: String) {
        if isRemoteMirror {
            remoteCommands?.send(.roleDelete(id: id))
            return
        }
        guard let index = roles.firstIndex(where: { $0.id == id }) else { return }
        roles.remove(at: index)
        selectedRoleIds.remove(id)
        broadcastState()
    }

    public func setPlotipharRoleId(forRoleId roleId: String, plotipharRoleId: String?) {
        guard !isRemoteMirror else { return }
        guard let index = roles.firstIndex(where: { $0.id == roleId }) else { return }
        roles[index].plotipharRoleId = plotipharRoleId
    }

    public func syncPlotipharAssignments() {
        guard FeatureFlags.plotiphar, !isRemoteMirror else { return }
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
        if isRemoteMirror {
            remoteCommands?.send(.clearCues)
            return
        }
        for index in roles.indices {
            roles[index].state = .off
            roles[index].lastUpdated = Date()
        }
        broadcastState()
    }

    public func sendMessage(_ text: String, targetRoleId: String? = nil, senderRoleId: String? = nil, isHighPriority: Bool = false) {
        if isRemoteMirror {
            guard !text.isEmpty else { return }
            remoteCommands?.send(.message(text: text, targetRoleId: targetRoleId, senderRoleId: senderRoleId, isHighPriority: isHighPriority))
            return
        }
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
        emit(packet, .lan(.all))
        emit(packet, .relay)
        if isMasterServer { _ = nextRev() }
    }

    public func hasUnreadMessage(forRoleId roleId: String) -> Bool {
        let readAt = messageReadAt[roleId] ?? .distantPast
        return recentMessages.contains { $0.senderRoleId == roleId && $0.timestamp > readAt }
    }

    public func markThreadRead(roleId: String) {
        guard hasUnreadMessage(forRoleId: roleId) else { return }
        messageReadAt[roleId] = Date()
    }

    public func openMessageThread(forRoleId roleId: String) {
        selectedMessageThreadId = roleId
        markThreadRead(roleId: roleId)
        appMode = .messages
    }

    public func clearActiveNotification() {
        if isRemoteMirror {
            remoteCommands?.send(.dismissNotification)
            return
        }
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
        if isRemoteMirror {
            remoteCommands?.send(.clearMessages)
            return
        }
        recentMessages = []
        notificationsClearedAt = nil
        let packet = CuePacket(type: .clearMessages, senderId: deviceId)
        emit(packet, .lan(.all))
        emit(packet, .relay)
        if isMasterServer { _ = nextRev() }
    }

    @discardableResult
    public func pingDevice(atIP ipString: String) -> Bool {
        let context = isRemoteMirror ? remoteCommands?.assignContext : nil
        guard let plan = AssignProducerPolicy.plan(
            selfAddress: LocalNetworkAddress.ipv4String(),
            remote: context,
            resolveServer: AssignProducerPolicy.resolveIPv4
        ) else {
            AppLog.networking.error("pingDevice: couldn't determine the address to assign")
            return false
        }
        let selfAddress = plan.host
        guard let payload = try? JSONSerialization.data(withJSONObject: plan.jsonObject) else { return false }
        #if canImport(Network)
        guard let port = NWEndpoint.Port(rawValue: LANUnicastServer.assignPort) else { return false }

        let connection = NWConnection(host: NWEndpoint.Host(ipString), port: port, using: .udp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: payload, completion: .contentProcessed { error in
                    if let error {
                        AppLog.networking.error("pingDevice: send failed: \(String(describing: error), privacy: .private)")
                    }
                    connection.cancel()
                })
            case .failed(let error):
                AppLog.networking.error("pingDevice: connection failed: \(String(describing: error), privacy: .private)")
                connection.cancel()
            case .waiting:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .utility))
        AppLog.networking.info("pingDevice: sending ASSIGN_PRODUCER (host=\(selfAddress, privacy: .private)) to \(ipString, privacy: .private)")
        #else
        guard Self.sendAssignPing(payload, to: ipString) else { return false }
        AppLog.networking.info("pingDevice: sending ASSIGN_PRODUCER (host=\(selfAddress, privacy: .private)) to \(ipString, privacy: .private)")
        #endif
        return true
    }

    @discardableResult
    public func setManualProducerHost(_ input: String) -> ManualHostValidation {
        let result = ManualHostPolicy.validate(input)
        guard !isRemoteMirror else { return result }
        switch result {
        case .valid:
            let endpoint = result.endpoint
            manualProducerHost = endpoint
            client.setManualHost(endpoint)
        case .empty:
            clearManualProducerHost()
        case .invalid:
            break
        }
        return result
    }

    public func clearManualProducerHost() {
        guard !isRemoteMirror else { return }
        manualProducerHost = nil
        producerLinkStatus = .idle
        client.setManualHost(nil)
    }

    public func forgetAssignedProducer() {
        guard !isRemoteMirror else { return }
        client.forgetAssignedHost()
    }

    func requestCatchUp() {
        guard !isMasterServer else { return }
        var ping = CuePacket(type: .ping, senderId: deviceId)
        ping.proto = CuePacket.protocolVersion
        emit(ping, .lan(.all))
        emit(ping, .relay)
    }

    private static let rolesDefaultsKey = "persistedRoles"

    private func persistRoles() {
        guard !isRemoteMirror else { return }
        guard let data = try? JSONEncoder().encode(roles) else { return }
        write(data, forKey: Self.rolesDefaultsKey)
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
        guard !isRemoteMirror else { return }
        guard let data = try? JSONEncoder().encode(waypoints) else { return }
        write(data, forKey: Self.waypointsDefaultsKey)
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
        erase(forKey: Self.legacyTagsDefaultsKey)
        AppLog.cue.info("migrated \(decoded.count, privacy: .public) waypoint(s) from the legacy \"serviceTags\" key")
    }

    private static let serviceSchedulesDefaultsKey = "serviceSchedules"

    private func persistServiceSchedules() {
        guard !isRemoteMirror else { return }
        guard let data = try? JSONEncoder().encode(serviceSchedules) else { return }
        write(data, forKey: Self.serviceSchedulesDefaultsKey)
    }

    private func restoreServiceSchedules() {
        guard let data = UserDefaults.standard.data(forKey: Self.serviceSchedulesDefaultsKey),
              let decoded = try? JSONDecoder().decode([ServiceSchedule].self, from: data) else { return }
        serviceSchedules = sortedByStartsAt(decoded)
    }

    private func persistNotificationsClearedAt() {
        guard !isRemoteMirror else { return }
        if let notificationsClearedAt {
            write(notificationsClearedAt, forKey: Self.notificationsClearedDefaultsKey)
        } else {
            erase(forKey: Self.notificationsClearedDefaultsKey)
        }
    }

    private func restoreNotificationsClearedAt() {
        notificationsClearedAt = UserDefaults.standard.object(forKey: Self.notificationsClearedDefaultsKey) as? Date
    }

    private func persistMessages() {
        guard !isRemoteMirror else { return }
        guard let data = try? JSONEncoder().encode(recentMessages) else { return }
        write(data, forKey: Self.messagesDefaultsKey)
    }

    private func restoreMessages() {
        guard let data = UserDefaults.standard.data(forKey: Self.messagesDefaultsKey),
              let decoded = try? JSONDecoder().decode([InterTeamMessage].self, from: data) else { return }
        recentMessages = decoded
    }

    func addMessages(_ incoming: [InterTeamMessage]) {
        let existingIds = Set(recentMessages.map(\.id))
        let newOnes = incoming.prefix(Self.maxStoredMessages).map { $0.clampedForStorage() }.filter { !existingIds.contains($0.id) }
        guard !newOnes.isEmpty else { return }
        recentMessages.append(contentsOf: newOnes)
        recentMessages = SyncHash.sortedNewestFirst(recentMessages)
        if recentMessages.count > Self.maxStoredMessages {
            recentMessages.removeLast(recentMessages.count - Self.maxStoredMessages)
        }
    }

    private struct PersistedFlow: Codable {
        let items: [PCOTimerItem]
        let activeItemIndex: Int
        var eventTimes: [EventTime]?
        var liveEventTimeId: String?
    }
    private static let persistedFlowDefaultsKey = "persistedFlow"

    private func persistCurrentFlow() {
        guard !isRemoteMirror else { return }
        guard !planItems.isEmpty || !eventTimes.isEmpty else {
            erase(forKey: Self.persistedFlowDefaultsKey)
            return
        }
        let flow = PersistedFlow(items: planItems, activeItemIndex: activeItemIndex, eventTimes: eventTimes, liveEventTimeId: liveEventTimeId)
        guard let data = try? JSONEncoder().encode(flow) else { return }
        write(data, forKey: Self.persistedFlowDefaultsKey)
    }

    private func restorePersistedFlow() {
        guard let data = UserDefaults.standard.data(forKey: Self.persistedFlowDefaultsKey),
              let flow = try? JSONDecoder().decode(PersistedFlow.self, from: data) else { return }
        restoreEventTimes(flow.eventTimes ?? [], liveId: flow.liveEventTimeId)
        guard !flow.items.isEmpty else { return }
        planItems = flow.items
        activeItemIndex = min(max(flow.activeItemIndex, 0), flow.items.count - 1)
        var restoredItem = flow.items[activeItemIndex]
        restoredItem.isRunning = false
        activeTimerItem = restoredItem
    }

    private func setupDefaultPlan() {
        tickTimerHandle?.invalidate()
        tickTimerHandle = MainLoopTimer.repeating(every: 1.0) { [weak self] in
            self?.tickTimer()
        }
    }

    private var pcoLiveSyncTickCount = 0
    var heartbeatTickCount = 0

    private struct LegacyTimerAnchor {
        let itemId: String
        let startedAt: Date
        let elapsedAtStart: Int
        var lastWritten: Int
    }

    private var legacyTimerAnchor: LegacyTimerAnchor?
    var timerClock: () -> Date = { Date() }
    #if canImport(Darwin)
    var monotonicMsClock: () -> Double = { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000 }
    #else
    var monotonicMsClock: () -> Double = { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000 }
    #endif

    func lanClientStatusChanged(_ isJoined: Bool) {
        isLANConnected = isJoined
        if !isJoined {
            connectedProducerHost = nil
            connectedProducerAPIPort = nil
        }
    }

    func noteProducerPacket() {
        lastProducerPacketMono = monotonicMs
        hasSyncedWithProducer = true
        evaluateProducerSignal()
    }

    func evaluateProducerSignal() {
        guard !isMasterServer else {
            if producerSignal != .live { producerSignal = .live }
            return
        }
        let silence = lastProducerPacketMono.map { max(0, monotonicMs - $0) / 1000 }
        let staleAfter = syncV2.producerIsV2 ? ProducerSignal.staleAfter : ProducerSignal.legacyStaleAfter
        let signal = ProducerSignal(silence: silence, staleAfter: staleAfter)
        if producerSignal != signal {
            let enteredLost = signal == .lost && producerSignal != .lost && lastProducerPacketMono != nil
            producerSignal = signal
            if enteredLost { resetClientSyncState() }
        }
        let live = signal != .lost
        if isProducerLive != live { isProducerLive = live }
    }

    func tickTimer() {
        guard !isRemoteMirror else { return }
        heartbeatTickCount += 1
        if heartbeatTickCount % 10 == 0 {
            AppLog.networking.debug("heartbeat — isMasterServer=\(self.isMasterServer, privacy: .public) connectedMasterName=\(self.connectedMasterName ?? "none", privacy: .private) activeItem=\(self.activeTimerItem?.title ?? "none", privacy: .private)")
        }

        if isPCOLiveSyncEnabled {
            pcoLiveSyncTickCount += 1
            if pcoLiveSyncTickCount % 5 == 0 {
                syncElapsedTimeFromPCOLive()
            }
        }

        if isMasterServer && heartbeatTickCount % 5 == 0 {
            broadcastLegacyState()
        }

        if isMasterServer && heartbeatTickCount % 5 == 0 {
            checkServiceSchedules()
        }

        if !isMasterServer {
            evaluateProducerSignal()
            if producerSignal == .lost, lastProducerPacketMono != nil, isLANConnected, !isRemoteMirror {
                lastProducerPacketMono = nil
                client.reconnectNow()
            }
        } else if producerSignal != .live {
            producerSignal = .live
        }

        v2HeartbeatTick()

        if isMasterServer {
            evaluateMasterTimer()
            if !isRemoteMirror, syncV2.producerWorkItem == nil { armProducerDisplayTick() }
        } else if !(syncV2.producerIsV2 && syncV2.held != nil) {
            accrueLegacyTimer()
        }

        if isMasterServer, activeTimerItem?.isRunning == true, heartbeatTickCount % 5 == 0 {
            var packet = CuePacket(type: .timerUpdate, senderId: deviceId, timerItem: activeTimerItemForBroadcast)
            packet.nextItem = nextItemForBroadcast
            stampUtcOffset(&packet)
            emit(packet, .lan(.legacy))
            emit(packet, .relay)
        }
    }

    private func accrueLegacyTimer() {
        guard var item = activeTimerItem, item.isRunning else {
            legacyTimerAnchor = nil
            return
        }

        let now = timerClock()
        if var anchor = legacyTimerAnchor, anchor.itemId == item.id, anchor.lastWritten == item.elapsedSeconds {
            let elapsed = anchor.elapsedAtStart.saturatingAdding(max(0, Int(max(-1e12, min(1e12, now.timeIntervalSince(anchor.startedAt))))))
            anchor.lastWritten = elapsed
            legacyTimerAnchor = anchor
            item.elapsedSeconds = elapsed
        } else {
            legacyTimerAnchor = LegacyTimerAnchor(
                itemId: item.id,
                startedAt: now,
                elapsedAtStart: item.elapsedSeconds,
                lastWritten: item.elapsedSeconds
            )
        }
        self.activeTimerItem = item
    }

    private func broadcastState() {
        broadcastLegacyState()
        emitV2Roles()
    }

    private func broadcastLegacyState() {
        var packet = CuePacket(type: .cueUpdate, senderId: deviceId, roleCues: roles, timerItem: activeTimerItemForBroadcast)
        packet.nextItem = nextItemForBroadcast
        AppLog.cue.debug("broadcastState() — isMasterServer=\(self.isMasterServer, privacy: .public)")

        if isMasterServer {
            emit(packet, .lan(.legacy))
        }

        emit(packet, .relay)
    }

    func broadcastCatchUp() {
        var packet = CuePacket(type: .pong, senderId: deviceId, roleCues: roles, timerItem: activeTimerItemForBroadcast, messages: recentMessages)
        packet.nextItem = nextItemForBroadcast
        stampUtcOffset(&packet)
        AppLog.cue.debug("broadcastCatchUp() — isMasterServer=\(self.isMasterServer, privacy: .public) messages=\(self.recentMessages.count, privacy: .public)")

        if isMasterServer {
            emit(packet, .lan(.legacy))
        }

        emit(packet, .relay)
    }

    func broadcastTimerUpdate() {
        refreshTimerAnchor()
        publishTimerAnchorToV2()
        guard let item = activeTimerItemForBroadcast else { return }
        var packet = CuePacket(type: .timerUpdate, senderId: deviceId, timerItem: item)
        packet.nextItem = nextItemForBroadcast
        stampUtcOffset(&packet)
        AppLog.cue.debug("broadcastTimerUpdate() — item=\"\(item.title, privacy: .private)\" remaining=\(item.remainingSeconds, privacy: .public)s isMasterServer=\(self.isMasterServer, privacy: .public)")
        if isMasterServer {
            emit(packet, .lan(.legacy))
        }
        emit(packet, .relay)
    }

    func broadcastToRelay(_ packet: CuePacket) {
        guard FeatureFlags.plotiphar, isProxyEnabled, !proxyToken.isEmpty else { return }
        relayClient.broadcast(packet: packet)
        directPeerChannel.send(packet: packet)
    }

    private func updateControlAPI() {
        guard hostsControlAPI else { return }

        if isControlAPIEnabled {
            server.advertisedControlAPIPort = controlAPIPort
            server.advertisingTXTDidChange()
            #if canImport(Network)
            let apiserver = controlAPIServer ?? makeControlAPIServer()
            apiserver.start(port: UInt16(clamping: controlAPIPort))
            controlAPIEventHub?.start()
            #endif
        } else {
            server.advertisedControlAPIPort = nil
            server.advertisingTXTDidChange()
            #if canImport(Network)
            controlAPIServer?.stop()
            controlAPIEventHub?.stop()
            #endif
            isControlAPIRunning = false
            controlAPIClientCount = 0
        }
    }

    #if canImport(Network)
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
        let hub = ControlAPIEventHub(engine: self, server: server, router: router)
        hub.hasClients = { [weak self] in (self?.controlAPIClientCount ?? 0) > 0 }
        controlAPIEventHub = hub
        return server
    }
    #endif

    func handlePacket(_ packet: CuePacket, origin: PacketOrigin = .relay) {
        guard packet.senderId != deviceId else { return }
        if let target = packet.to, target != deviceId { return }
        if packet.anchorRejected { return }
        guard acceptsInbound(packet) else {
            AppLog.networking.notice("Dropped \(packet.type.rawValue, privacy: .public) packet: a producer only accepts PING, SYNC and MESSAGE")
            return
        }
        AppLog.cue.debug("handlePacket() type=\(packet.type.rawValue, privacy: .public) from=\(packet.senderId, privacy: .private) roleCues=\(packet.roleCues?.count ?? 0, privacy: .public) timerItem=\(packet.timerItem?.title ?? "nil", privacy: .private)")

        let epochChanged = processEpoch(packet)
        noteProducerCapabilities(packet)
        noteProducerUTCOffset(packet)
        guard passesRevisionGate(packet, epochChanged: epochChanged) else { return }

        switch packet.type {
        case .cueUpdate, .timerUpdate, .pong:
            noteProducerPacket()
        case .timerAnchor, .cueDelta, .digest, .syncReply:
            if !isMasterServer {
                noteProducerPacket()
            }
        default:
            break
        }

        if packet.type == .cueUpdate || packet.type == .timerUpdate {
            noteLegacyPacket(packet, origin: origin)
        }

        let isV2Timer = !isMasterServer && syncV2.producerIsV2 && syncV2.held != nil

        switch packet.type {
        case .cueUpdate:
            if let updatedRoles = packet.roleCues {
                self.roles = updatedRoles
            }
            if let timer = packet.timerItem, !isV2Timer {
                self.activeTimerItem = timer
                applyReceivedNextItem(packet.nextItem)
            }
            if let messages = packet.messages {
                addMessages(messages)
            }
        case .timerUpdate:
            if let timer = packet.timerItem, !isV2Timer {
                self.activeTimerItem = timer
                applyReceivedNextItem(packet.nextItem)
            }
        case .messageBroadcast:
            if let msg = packet.message {
                addMessages([msg])
                if isMasterServer { _ = nextRev() }
            }
        case .clearMessages:
            recentMessages = []
        case .ping:
            if isMasterServer {
                if (packet.proto ?? 0) >= CuePacket.protocolVersion {
                    answerV2CatchUp(origin: origin, requester: packet.senderId)
                } else {
                    broadcastCatchUp()
                }
            }
        case .pong:
            let isV2Pong = syncV2.producerIsV2 && packet.rev != nil
            syncV2.catchUpInFlight = false
            if let updatedRoles = packet.roleCues {
                self.roles = updatedRoles
            }
            if let timer = packet.timerItem, !(isV2Timer && !isV2Pong) {
                self.activeTimerItem = timer
                applyReceivedNextItem(packet.nextItem)
            }
            if let messages = packet.messages {
                if isV2Pong {
                    applyV2CatchUpMessages(messages)
                } else {
                    addMessages(messages)
                }
            }
        case .sync:
            answerSync(packet, origin: origin)
        case .syncReply:
            handleSyncReply(packet)
        case .timerAnchor:
            if !isMasterServer { applyTimerAnchorPacket(packet) }
        case .cueDelta:
            if !isMasterServer, let deltas = packet.cueDeltas {
                applyCueDeltas(deltas)
            }
        case .digest:
            if !isMasterServer { verifyDigest(packet) }
        }

        if epochChanged {
            startSyncBurst()
            if packet.type != .pong { requestCatchUpOnce() }
        }
    }
}
