// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public final class LocalCueClient: @unchecked Sendable {
    private let channel = LANUnicastClient()
    private var isRunning = false

    public var onPacketReceived: ((CuePacket) -> Void)? {
        get { channel.onPacketReceived }
        set { channel.onPacketReceived = newValue }
    }
    public var onStatusChanged: ((Bool) -> Void)? {
        get { channel.onStatusChanged }
        set { channel.onStatusChanged = newValue }
    }
    public var onMasterDiscovered: ((String) -> Void)? {
        get { channel.onMasterDiscovered }
        set { channel.onMasterDiscovered = newValue }
    }
    public var onConnectedHost: ((String) -> Void)? {
        get { channel.onConnectedHost }
        set { channel.onConnectedHost = newValue }
    }
    public var onConnectedAPIPort: ((Int) -> Void)? {
        get { channel.onConnectedAPIPort }
        set { channel.onConnectedAPIPort = newValue }
    }

    public init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        AppLog.networking.info("LocalCueClient starting (client mode)")
        channel.start()
    }

    public func stop() {
        guard isRunning else { return }
        AppLog.networking.debug("LocalCueClient stopping")
        isRunning = false
        channel.stop()
    }

    public func broadcast(packet: CuePacket) {
        channel.send(packet)
    }

    public func forgetAssignedHost() {
        channel.forgetAssignedHost()
    }
}
