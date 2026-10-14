// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

extension CueEngine {
    static let producerAcceptedPacketTypes: Set<CuePacket.PacketType> = [.ping, .sync, .messageBroadcast]

    func acceptsInbound(_ packet: CuePacket) -> Bool {
        guard isMasterServer else { return true }
        return Self.producerAcceptedPacketTypes.contains(packet.type)
    }
}
