// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Combine
import Foundation
import SwiftUI

@MainActor
public final class WatchPagerModel: ObservableObject {
    @AppStorage("watchProducerHost") private var persistedHost = ""
    @AppStorage("watchProducerPort") private var persistedPort = ProducerHTTPPagerClient.defaultPort
    @AppStorage("watchSelectedRoleId") public var selectedRoleId = "default"

    @Published public private(set) var state: ControlAPIState?
    @Published public private(set) var isReachable = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastSuccessfulPollAt: Date?

    public var host: String { persistedHost }
    public var port: Int { persistedPort }

    public var presentation: PagerPresentationState? {
        guard let state else { return nil }
        return PagerPresentationState(apiState: state, selectedRoleId: selectedRoleId)
    }

    public var activeRole: RoleCue? { presentation?.activeRole }
    public var currentState: CueState { presentation?.currentState ?? .off }
    public var roles: [RoleCue] { state?.roles ?? [] }

    private var client: ProducerHTTPPagerClient?
    private var pollTask: Task<Void, Never>?
    private var seededInitialSnapshot = false
    private var lastMessageId: String?
    private var bridgeIPObserver: AnyCancellable?
    private var producerBrowser: WatchProducerBrowser?
    private var browserObserver: AnyCancellable?

    public init() {}

    public func start() {
        guard pollTask == nil else { return }
        WatchSessionBridge.shared.activate()
        applyBridgeAddressIfNeeded()
        bridgeIPObserver = WatchSessionBridge.shared.$producerIP
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyBridgeAddressIfNeeded()
            }
        let browser = WatchProducerBrowser()
        producerBrowser = browser
        browserObserver = browser.$discoveredHost
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyBridgeAddressIfNeeded()
            }
        browser.start()
        restartPolling()
    }

    public func stop() {
        bridgeIPObserver?.cancel()
        bridgeIPObserver = nil
        browserObserver?.cancel()
        browserObserver = nil
        producerBrowser?.stop()
        producerBrowser = nil
        pollTask?.cancel()
        pollTask = nil
    }

    public func applyBridgeAddressIfNeeded() {
        guard persistedHost.isEmpty else { return }
        if let ip = WatchSessionBridge.shared.producerIP, !ip.isEmpty {
            configure(host: ip, port: WatchSessionBridge.shared.producerPort)
            return
        }
        if let ip = producerBrowser?.discoveredHost, !ip.isEmpty {
            configure(
                host: ip,
                port: producerBrowser?.discoveredPort ?? ProducerHTTPPagerClient.defaultPort
            )
        }
    }

    @discardableResult
    public func configure(host rawInput: String, port preferredPort: Int) -> Bool {
        let trimmed = rawInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        var hostValue = trimmed
        var portValue = preferredPort

        if let parsed = Self.splitHostPort(trimmed) {
            hostValue = parsed.host
            portValue = parsed.port
        } else if let url = URL(string: trimmed.contains("://") ? trimmed : "http://" + trimmed),
                  let urlHost = url.host {
            hostValue = urlHost
            if let urlPort = url.port {
                portValue = urlPort
            }
        }

        guard !hostValue.isEmpty else { return false }
        guard (1..<65536).contains(portValue) else { return false }

        persistedHost = hostValue
        persistedPort = portValue
        restartPolling()
        return true
    }

    public func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let client else { return }
        _ = try? await client.sendMessage(
            text: trimmed,
            targetRoleId: selectedRoleId,
            senderRoleId: selectedRoleId
        )
    }

    private func restartPolling() {
        client = persistedHost.isEmpty ? nil : ProducerHTTPPagerClient(host: persistedHost, port: persistedPort)
        seededInitialSnapshot = false
        lastMessageId = nil
        lastSuccessfulPollAt = nil
        pollTask?.cancel()
        pollTask = Task { await pollLoop() }
    }

    private func pollLoop() async {
        var nextTick = ContinuousClock.now
        while !Task.isCancelled {
            await pollOnce()
            nextTick += .seconds(1)
            let now = ContinuousClock.now
            if nextTick > now {
                try? await Task.sleep(for: nextTick - now)
            } else {
                nextTick = now
            }
        }
    }

    private func pollOnce() async {
        guard let client else { return }
        do {
            let fresh = try await client.fetchState()
            guard !Task.isCancelled else { return }
            let previous = state
            state = fresh
            lastSuccessfulPollAt = Date.now
            isReachable = true
            lastError = nil

            let freshPresentation = PagerPresentationState(apiState: fresh, selectedRoleId: selectedRoleId)

            guard seededInitialSnapshot else {
                seededInitialSnapshot = true
                lastMessageId = freshPresentation.latestRelevantMessage?.id
                return
            }

            if let previous {
                detectHaptics(from: previous, to: fresh, freshPresentation: freshPresentation)
            } else {
                lastMessageId = freshPresentation.latestRelevantMessage?.id
            }
        } catch {
            guard !Task.isCancelled else { return }
            isReachable = false
            lastError = error.localizedDescription
        }
    }

    private let isHapticsEnabled = false

    private func detectHaptics(from old: ControlAPIState, to new: ControlAPIState, freshPresentation: PagerPresentationState) {
        guard isHapticsEnabled else { return }
        let oldPresentation = PagerPresentationState(apiState: old, selectedRoleId: selectedRoleId)
        let newState = freshPresentation.currentState
        if newState != oldPresentation.currentState {
            PagerHaptics.shared.playCueTransition(for: newState)
        }
        guard let messageId = freshPresentation.latestRelevantMessage?.id, messageId != lastMessageId else { return }
        lastMessageId = messageId
        guard let message = freshPresentation.latestRelevantMessage, message.senderRoleId != selectedRoleId else { return }
        PagerHaptics.shared.playMessageReceived(for: newState)
    }

    private static func splitHostPort(_ input: String) -> (host: String, port: Int)? {
        guard !input.contains("/"), let colon = input.lastIndex(of: ":") else { return nil }
        let host = String(input[..<colon])
        guard !host.isEmpty, let port = Int(input[input.index(after: colon)...]), (1..<65536).contains(port) else { return nil }
        return (host, port)
    }
}

extension PagerPresentationState {
    public init(apiState: ControlAPIState, selectedRoleId: String) {
        self.init(
            roles: apiState.roles,
            planItems: apiState.plan.items,
            activeItemIndex: apiState.plan.activeItemIndex,
            activeTimerItem: apiState.timer?.item,
            recentMessages: apiState.messages,
            selectedRoleId: selectedRoleId,
            isProducerLive: apiState.network.isProducerLive,
            isLANConnected: apiState.network.isLANConnected,
            connectedMasterName: apiState.network.connectedMasterName,
            hourFormatThreshold: HourFormatThreshold(rawValue: apiState.settings.hourFormatThreshold) ?? .over90Minutes
        )
    }
}