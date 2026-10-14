// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

#if !canImport(Network)
public protocol LANServerBackend: AnyObject {
    var onPacketReceived: ((CuePacket, LANConnectionID) -> Void)? { get set }
    var onStatusChanged: ((Bool) -> Void)? { get set }
    var advertisedControlAPIPort: Int? { get set }
    var advertisedDeviceId: String? { get set }
    func start()
    func stop()
    func advertisingTXTDidChange()
    func send(_ packet: CuePacket, to audience: LANAudience)
    func markProtocolV2(_ id: LANConnectionID)
}

public protocol LANClientBackend: AnyObject {
    var onPacketReceived: ((CuePacket) -> Void)? { get set }
    var onStatusChanged: ((Bool) -> Void)? { get set }
    var onMasterDiscovered: ((String) -> Void)? { get set }
    var onConnectedHost: ((String) -> Void)? { get set }
    var onConnectedAPIPort: ((Int) -> Void)? { get set }
    var onLinkStatusChanged: ((ProducerLinkStatus) -> Void)? { get set }
    func start()
    func stop()
    func setManualHost(_ host: String?)
    func forgetAssignedHost()
    func reconnectNow(force: Bool)
    func send(_ packet: CuePacket)
}

final class NullLANServerBackend: LANServerBackend {
    var onPacketReceived: ((CuePacket, LANConnectionID) -> Void)?
    var onStatusChanged: ((Bool) -> Void)?
    var advertisedControlAPIPort: Int?
    var advertisedDeviceId: String?
    func start() {}
    func stop() {}
    func advertisingTXTDidChange() {}
    func send(_ packet: CuePacket, to audience: LANAudience) {}
    func markProtocolV2(_ id: LANConnectionID) {}
}

final class NullLANClientBackend: LANClientBackend {
    var onPacketReceived: ((CuePacket) -> Void)?
    var onStatusChanged: ((Bool) -> Void)?
    var onMasterDiscovered: ((String) -> Void)?
    var onConnectedHost: ((String) -> Void)?
    var onConnectedAPIPort: ((Int) -> Void)?
    var onLinkStatusChanged: ((ProducerLinkStatus) -> Void)?
    func start() {}
    func stop() {}
    func setManualHost(_ host: String?) {}
    func forgetAssignedHost() {}
    func reconnectNow(force: Bool) {}
    func send(_ packet: CuePacket) {}
}

public enum LANTransportRegistry {
    public nonisolated(unsafe) static var makeServer: () -> LANServerBackend = { NullLANServerBackend() }
    public nonisolated(unsafe) static var makeClient: () -> LANClientBackend = { NullLANClientBackend() }
}

public final class LANUnicastServer: @unchecked Sendable {
    public static let port: UInt16 = 13380
    public static let assignPort: UInt16 = 13381

    private let backend: LANServerBackend

    public var onPacketReceived: ((CuePacket, LANConnectionID) -> Void)? {
        get { backend.onPacketReceived }
        set { backend.onPacketReceived = newValue }
    }
    public var onStatusChanged: ((Bool) -> Void)? {
        get { backend.onStatusChanged }
        set { backend.onStatusChanged = newValue }
    }
    public var advertisedControlAPIPort: Int? {
        get { backend.advertisedControlAPIPort }
        set { backend.advertisedControlAPIPort = newValue }
    }
    public var advertisedDeviceId: String? {
        get { backend.advertisedDeviceId }
        set { backend.advertisedDeviceId = newValue }
    }

    public init() {
        backend = LANTransportRegistry.makeServer()
    }

    public func start() { backend.start() }

    public func stop() { backend.stop() }

    public func markProtocolV2(_ id: LANConnectionID) { backend.markProtocolV2(id) }

    public func advertisingTXTDidChange() { backend.advertisingTXTDidChange() }

    public func send(_ packet: CuePacket, to audience: LANAudience = .all) {
        backend.send(packet, to: audience)
    }
}

public final class LANUnicastClient: @unchecked Sendable {
    private static let manualHostDefaultsKey = "lanUnicastManualProducerHost"

    private let backend: LANClientBackend

    public var onPacketReceived: ((CuePacket) -> Void)? {
        get { backend.onPacketReceived }
        set { backend.onPacketReceived = newValue }
    }
    public var onStatusChanged: ((Bool) -> Void)? {
        get { backend.onStatusChanged }
        set { backend.onStatusChanged = newValue }
    }
    public var onMasterDiscovered: ((String) -> Void)? {
        get { backend.onMasterDiscovered }
        set { backend.onMasterDiscovered = newValue }
    }
    public var onConnectedHost: ((String) -> Void)? {
        get { backend.onConnectedHost }
        set { backend.onConnectedHost = newValue }
    }
    public var onConnectedAPIPort: ((Int) -> Void)? {
        get { backend.onConnectedAPIPort }
        set { backend.onConnectedAPIPort = newValue }
    }
    public var onLinkStatusChanged: ((ProducerLinkStatus) -> Void)? {
        get { backend.onLinkStatusChanged }
        set { backend.onLinkStatusChanged = newValue }
    }

    public init() {
        backend = LANTransportRegistry.makeClient()
    }

    public static func savedManualHost() -> String? {
        UserDefaults.standard.string(forKey: manualHostDefaultsKey).flatMap { ManualHostPolicy.validate($0).endpoint }
    }

    public func setManualHost(_ host: String?) {
        if let host {
            UserDefaults.standard.set(host, forKey: Self.manualHostDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.manualHostDefaultsKey)
        }
        backend.setManualHost(host)
    }

    public func start() { backend.start() }

    public func stop() { backend.stop() }

    public func forgetAssignedHost() { backend.forgetAssignedHost() }

    public func reconnectNow(force: Bool = true) { backend.reconnectNow(force: force) }

    public func send(_ packet: CuePacket) { backend.send(packet) }
}
#endif
