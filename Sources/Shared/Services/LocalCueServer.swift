// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public final class LocalCueServer: @unchecked Sendable {
    private let channel = LANUnicastServer()
    private var isRunning = false

    public var onPacketReceived: ((CuePacket) -> Void)? {
        get { channel.onPacketReceived }
        set { channel.onPacketReceived = newValue }
    }
    public var onStatusChanged: ((Bool) -> Void)? {
        get { channel.onStatusChanged }
        set { channel.onStatusChanged = newValue }
    }
    public var advertisedControlAPIPort: Int? {
        get { channel.advertisedControlAPIPort }
        set { channel.advertisedControlAPIPort = newValue }
    }

    public init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        AppLog.networking.info("LocalCueServer starting (master mode)")
        channel.start()
    }

    public func stop() {
        guard isRunning else { return }
        AppLog.networking.debug("LocalCueServer stopping")
        isRunning = false
        channel.stop()
    }

    public func advertisingTXTDidChange() {
        channel.advertisingTXTDidChange()
    }

    public func broadcast(packet: CuePacket) {
        channel.send(packet)
    }
}
