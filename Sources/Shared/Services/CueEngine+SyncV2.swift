// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

enum PacketOrigin {
    case lanServer(LANConnectionID)
    case lanClient
    case relay
}

enum OutboundTarget {
    case lan(LANAudience)
    case relay
}

struct HeldAnchor {
    var anchor: TimerAnchor
    var item: PCOTimerItem
}

struct SyncV2State {
    var rev = 0
    var anchor: TimerAnchor?
    var writtenSeconds = 0
    var lastBroadcastRoles: [RoleCue]?
    var relayHasV2Peer = false

    var producerIsV2 = false
    var estimator = ClockOffsetEstimator()
    var pendingSyncT0: Set<Int> = []
    var held: HeldAnchor?
    var gate = SyncRevisionGate()
    var catchUpInFlight = false
    var ticksSinceSync = 0
    var mirrorOffsetMs: Double?
    var displayWorkItem: DispatchWorkItem?
}

extension CueEngine {
    static let syncBurstCount = 5
    static let syncBurstSpacing: TimeInterval = 0.1
    static let syncIntervalTicks = 30
    static let digestIntervalTicks = 10
    static let v2StalenessInterval: TimeInterval = 25

    var nowMsInt: Int {
        Int((timerClock().timeIntervalSince1970 * 1000).rounded())
    }

    var currentAnchor: TimerAnchor? {
        if isMasterServer && !isRemoteMirror {
            evaluateMasterTimer()
            return syncV2.anchor
        }
        return syncV2.held?.anchor
    }

    func emit(_ packet: CuePacket, _ target: OutboundTarget) {
        outboundObserver?(packet, target)
        switch target {
        case .lan(let audience):
            if isMasterServer {
                server.broadcast(packet: packet, to: audience)
            } else {
                client.broadcast(packet: packet)
            }
        case .relay:
            broadcastToRelay(packet)
        }
    }

    func emitToV2Peers(_ packet: CuePacket) {
        guard isMasterServer else { return }
        emit(packet, .lan(.v2))
        if syncV2.relayHasV2Peer { emit(packet, .relay) }
    }

    func nextRev() -> Int {
        syncV2.rev += 1
        return syncV2.rev
    }

    func exactElapsedMs(of item: PCOTimerItem, at now: Int) -> Int {
        if let anchor = syncV2.anchor, anchor.itemId == item.id, item.elapsedSeconds == syncV2.writtenSeconds {
            return anchor.elapsedMs(atProducerMs: now)
        }
        return item.elapsedSeconds * 1000
    }

    func refreshTimerAnchor() {
        guard isMasterServer, !isRemoteMirror else { return }
        let now = nowMsInt
        guard var item = activeTimerItem else {
            syncV2.anchor = nil
            syncV2.writtenSeconds = 0
            return
        }
        let exact = exactElapsedMs(of: item, at: now)
        if syncV2.anchor?.itemId == item.id, item.elapsedSeconds == syncV2.writtenSeconds, exact / 1000 != item.elapsedSeconds {
            item.elapsedSeconds = exact / 1000
            activeTimerItem = item
        }
        syncV2.anchor = TimerAnchor(
            itemId: item.id,
            lengthInSeconds: item.lengthInSeconds,
            elapsedMs: exact,
            anchorMs: now,
            isRunning: item.isRunning,
            isDurationActual: activeTimerActualForDisplay
        )
        syncV2.writtenSeconds = item.elapsedSeconds
    }

    func publishTimerAnchorToV2() {
        guard isMasterServer, !isRemoteMirror else { return }
        var packet = CuePacket(type: .timerAnchor, senderId: deviceId, timerItem: syncV2.anchor == nil ? nil : activeTimerItemForBroadcast)
        packet.rev = nextRev()
        packet.anchor = syncV2.anchor
        emitToV2Peers(packet)
    }

    func evaluateMasterTimer() {
        guard isMasterServer, !isRemoteMirror else { return }
        let now = nowMsInt
        guard var item = activeTimerItem else {
            if syncV2.anchor != nil {
                syncV2.anchor = nil
                syncV2.writtenSeconds = 0
                publishTimerAnchorToV2()
            }
            return
        }
        let consistent: Bool
        if let anchor = syncV2.anchor {
            consistent = anchor.itemId == item.id
                && anchor.lengthInSeconds == item.lengthInSeconds
                && anchor.isRunning == item.isRunning
                && anchor.isDurationActual == activeTimerActualForDisplay
                && item.elapsedSeconds == syncV2.writtenSeconds
        } else {
            consistent = false
        }
        if !consistent {
            syncV2.anchor = TimerAnchor(
                itemId: item.id,
                lengthInSeconds: item.lengthInSeconds,
                elapsedMs: item.elapsedSeconds * 1000,
                anchorMs: now,
                isRunning: item.isRunning,
                isDurationActual: activeTimerActualForDisplay
            )
            syncV2.writtenSeconds = item.elapsedSeconds
            publishTimerAnchorToV2()
            return
        }
        guard item.isRunning, let anchor = syncV2.anchor else { return }
        let seconds = anchor.elapsedSeconds(atProducerMs: now)
        if seconds != item.elapsedSeconds {
            item.elapsedSeconds = seconds
            syncV2.writtenSeconds = seconds
            activeTimerItem = item
        }
    }

    func currentHashes() -> SyncHash.Hashes {
        SyncHash.Hashes(
            roles: SyncHash.roles(roles),
            timer: SyncHash.timer(currentAnchor),
            messages: SyncHash.messages(recentMessages)
        )
    }

    func makeDigestPacket() -> CuePacket {
        var packet = CuePacket(type: .digest, senderId: deviceId)
        packet.hashes = currentHashes()
        packet.rev = syncV2.rev
        packet.digestMs = nowMsInt
        return packet
    }

    func publishDigestToV2() {
        guard isMasterServer, !isRemoteMirror else { return }
        emitToV2Peers(makeDigestPacket())
    }

    func rolesStructure(_ roles: [RoleCue]) -> [RoleCue] {
        roles.map { role in
            var copy = role
            copy.state = .off
            copy.lastUpdated = Date(timeIntervalSince1970: 0)
            return copy
        }
    }

    func emitV2Roles() {
        guard isMasterServer, !isRemoteMirror else { return }
        let previous = syncV2.lastBroadcastRoles
        syncV2.lastBroadcastRoles = roles
        if let previous, rolesStructure(previous) == rolesStructure(roles) {
            let deltas = zip(previous, roles).compactMap { old, new -> CueDelta? in
                guard old.state != new.state || old.lastUpdated != new.lastUpdated else { return nil }
                return CueDelta(id: new.id, state: new.state, lastUpdated: new.lastUpdated)
            }
            guard !deltas.isEmpty else { return }
            var packet = CuePacket(type: .cueDelta, senderId: deviceId)
            packet.cueDeltas = deltas
            packet.rev = nextRev()
            emitToV2Peers(packet)
        } else {
            var packet = CuePacket(type: .cueUpdate, senderId: deviceId, roleCues: roles)
            packet.rev = nextRev()
            emitToV2Peers(packet)
        }
    }

    func answerV2CatchUp(origin: PacketOrigin) {
        evaluateMasterTimer()
        if syncV2.lastBroadcastRoles == nil { syncV2.lastBroadcastRoles = roles }
        var pong = CuePacket(type: .pong, senderId: deviceId, roleCues: roles, timerItem: activeTimerItemForBroadcast, messages: recentMessages)
        pong.proto = CuePacket.protocolVersion
        pong.rev = syncV2.rev
        var anchorPacket = CuePacket(type: .timerAnchor, senderId: deviceId, timerItem: syncV2.anchor == nil ? nil : activeTimerItemForBroadcast)
        anchorPacket.rev = syncV2.rev
        anchorPacket.anchor = syncV2.anchor
        let digest = makeDigestPacket()
        switch origin {
        case .lanServer(let id):
            server.markProtocolV2(id)
            for packet in [pong, anchorPacket, digest] { emit(packet, .lan(.connection(id))) }
        case .relay:
            syncV2.relayHasV2Peer = true
            broadcastCatchUp()
            for packet in [anchorPacket, digest] { emit(packet, .relay) }
        case .lanClient:
            break
        }
    }

    func answerSync(_ packet: CuePacket, origin: PacketOrigin) {
        guard isMasterServer, !isRemoteMirror, let t0 = packet.t0 else { return }
        var reply = CuePacket(type: .syncReply, senderId: deviceId)
        reply.t0 = t0
        reply.t1 = Int((packet.receivedAtMs ?? SyncClock.nowMs()).rounded())
        switch origin {
        case .lanServer(let id):
            emit(reply, .lan(.connection(id)))
        case .relay:
            emit(reply, .relay)
        case .lanClient:
            break
        }
    }

    func noteProducerCapabilities(_ packet: CuePacket) {
        guard !isMasterServer else { return }
        switch packet.type {
        case .timerAnchor, .cueDelta, .digest, .syncReply:
            syncV2.producerIsV2 = true
        default:
            if packet.proto == CuePacket.protocolVersion { syncV2.producerIsV2 = true }
        }
    }

    func passesRevisionGate(_ packet: CuePacket) -> Bool {
        guard !isMasterServer, syncV2.producerIsV2 else { return true }
        switch packet.type {
        case .pong:
            syncV2.gate.rebase(to: packet.rev)
            return true
        case .cueUpdate, .timerAnchor, .cueDelta, .digest:
            return syncV2.gate.accept(packet.rev)
        default:
            return true
        }
    }

    func applyTimerAnchorPacket(_ packet: CuePacket) {
        guard let anchor = packet.anchor, let item = packet.timerItem, item.id == anchor.itemId else {
            syncV2.held = nil
            cancelDisplayTick()
            if activeTimerItem != nil { activeTimerItem = nil }
            return
        }
        syncV2.held = HeldAnchor(anchor: anchor, item: item)
        if syncedProducerNowMs == nil {
            if activeTimerItem != item { activeTimerItem = item }
        } else {
            refreshHeldTimer()
        }
        armDisplayTick()
    }

    func applyCueDeltas(_ deltas: [CueDelta]) {
        var updated = roles
        var unknown = false
        for delta in deltas {
            guard let index = updated.firstIndex(where: { $0.id == delta.id }) else {
                unknown = true
                continue
            }
            updated[index].state = delta.state
            updated[index].lastUpdated = delta.lastUpdated
        }
        if updated != roles { roles = updated }
        if unknown { requestCatchUpOnce() }
    }

    func localHashes() -> SyncHash.Hashes {
        SyncHash.Hashes(
            roles: SyncHash.roles(roles),
            timer: SyncHash.timer(syncV2.held?.anchor),
            messages: SyncHash.messages(recentMessages)
        )
    }

    func verifyDigest(_ packet: CuePacket) {
        guard let remote = packet.hashes else { return }
        if !localHashes().mismatches(against: remote).isEmpty {
            requestCatchUpOnce()
        }
    }

    func requestCatchUpOnce() {
        guard !isMasterServer, !isRemoteMirror, !syncV2.catchUpInFlight else { return }
        syncV2.catchUpInFlight = true
        requestCatchUp()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.syncV2.catchUpInFlight = false
        }
    }

    func applyV2CatchUpMessages(_ messages: [InterTeamMessage]) {
        let sorted = messages.sorted { $0.timestamp > $1.timestamp }
        if recentMessages != sorted { recentMessages = sorted }
    }

    var syncedProducerNowMs: Double? {
        let local = timerClock().timeIntervalSince1970 * 1000
        let offset = isRemoteMirror ? syncV2.mirrorOffsetMs : syncV2.estimator.offsetMs
        return offset.map { local + $0 }
    }

    func refreshHeldTimer() {
        guard let held = syncV2.held, let nowMs = syncedProducerNowMs else { return }
        let item = held.anchor.applying(to: held.item, atProducerMs: Int(nowMs.rounded(.down)))
        if activeTimerItem != item { activeTimerItem = item }
    }

    func cancelDisplayTick() {
        syncV2.displayWorkItem?.cancel()
        syncV2.displayWorkItem = nil
    }

    func armDisplayTick() {
        cancelDisplayTick()
        guard let held = syncV2.held, held.anchor.isRunning, let nowMs = syncedProducerNowMs,
              let wait = held.anchor.msUntilNextSecond(atProducerMs: Int(nowMs.rounded(.down))) else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.refreshHeldTimer()
            self?.armDisplayTick()
        }
        syncV2.displayWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(wait + 2), execute: work)
    }

    func handleSyncReply(_ packet: CuePacket) {
        guard !isMasterServer, !isRemoteMirror, let t0 = packet.t0, let t1 = packet.t1, let t2 = packet.t2,
              let t3 = packet.receivedAtMs, syncV2.pendingSyncT0.remove(t0) != nil else { return }
        let sample = ClockSyncSample(t0: Double(t0), t1: Double(t1), t2: Double(t2), t3: t3)
        guard syncV2.estimator.add(sample) else { return }
        refreshHeldTimer()
        armDisplayTick()
    }

    func sendSyncSample() {
        guard !isMasterServer, !isRemoteMirror else { return }
        let t0 = Int(SyncClock.nowMs().rounded())
        syncV2.pendingSyncT0.insert(t0)
        if syncV2.pendingSyncT0.count > 32 { syncV2.pendingSyncT0.remove(syncV2.pendingSyncT0.min()!) }
        var packet = CuePacket(type: .sync, senderId: deviceId)
        packet.t0 = t0
        emit(packet, .lan(.all))
        emit(packet, .relay)
    }

    func startSyncBurst() {
        guard !isMasterServer, !isRemoteMirror else { return }
        for index in 0..<Self.syncBurstCount {
            let delay = Self.syncBurstSpacing * Double(index)
            if index == 0 {
                sendSyncSample()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.sendSyncSample()
                }
            }
        }
        syncV2.ticksSinceSync = 0
    }

    public func deviceDidBecomeActive() {
        guard !isMasterServer, !isRemoteMirror else { return }
        sendSyncSample()
        syncV2.ticksSinceSync = 0
        refreshHeldTimer()
        armDisplayTick()
    }

    func resetClientSyncState() {
        cancelDisplayTick()
        syncV2.producerIsV2 = false
        syncV2.estimator.reset()
        syncV2.pendingSyncT0 = []
        syncV2.held = nil
        syncV2.gate.reset()
        syncV2.catchUpInFlight = false
        syncV2.ticksSinceSync = 0
    }

    func v2HeartbeatTick() {
        if isMasterServer {
            emitV2RolesIfChanged()
            if heartbeatTickCount % Self.digestIntervalTicks == 0 { publishDigestToV2() }
        } else if syncV2.producerIsV2 {
            syncV2.ticksSinceSync += 1
            if syncV2.ticksSinceSync >= Self.syncIntervalTicks {
                syncV2.ticksSinceSync = 0
                sendSyncSample()
            }
            refreshHeldTimer()
            if syncV2.displayWorkItem == nil { armDisplayTick() }
        }
    }

    func emitV2RolesIfChanged() {
        guard let previous = syncV2.lastBroadcastRoles, previous != roles else { return }
        emitV2Roles()
    }

    public func setRemoteClockOffset(_ offsetMs: Double?) {
        guard isRemoteMirror else { return }
        syncV2.mirrorOffsetMs = offsetMs
        refreshHeldTimer()
        armDisplayTick()
    }
}
