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
    var receivedMonoMs: Double = 0
    var fallbackProducerMs: Double = 0
}

struct SyncV2State {
    var rev = 0
    var epoch = Int.random(in: 1...Int(Int32.max))
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
    var producerWorkItem: DispatchWorkItem?
    var producerTickDelayMs: Int?
    var producerEpoch: Int?
    var lastLegacyCatchUpMono: Double?
    var lastV2PacketMono: Double?
    var messageMismatchStreak = 0
    var lastMessageCatchUpMono: Double?
    var lastBurstMono: Double?
    var relayLinked = false
    var lastNextItem: CueNextItem?
}

extension CueEngine {
    public static let syncBurstCount = 5
    static let syncBurstSpacing: TimeInterval = 0.1
    static let syncIntervalTicks = 30
    static let digestIntervalTicks = 2
    static let catchUpMessageLimit = 20
    static let maxCatchUpPongBytes = 4096
    static let legacyCatchUpMinGapMs = 5_000.0
    static let v2SilenceBeforeLegacyCatchUpMs = 12_000.0
    static let burstReissueGapMs = 3_000.0
    static let messageMismatchFreeStreak = 2
    static let messageCatchUpBackoffMs = 30_000.0

    var monotonicMs: Double { monotonicMsClock() }

    public var clockEstimator: ClockOffsetEstimator { syncV2.estimator }

    static func clampedInt(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(max(-1e15, min(1e15, value)))
    }

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
            armProducerDisplayTick()
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
        armProducerDisplayTick()
    }

    func publishTimerAnchorToV2() {
        guard isMasterServer, !isRemoteMirror else { return }
        var packet = CuePacket(type: .timerAnchor, senderId: deviceId, timerItem: syncV2.anchor == nil ? nil : activeTimerItemForBroadcast)
        packet.nextItem = syncV2.anchor == nil ? nil : nextItemForBroadcast
        stampUtcOffset(&packet)
        syncV2.lastNextItem = packet.nextItem
        packet.rev = nextRev()
        packet.epoch = syncV2.epoch
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
                armProducerDisplayTick()
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
            armProducerDisplayTick()
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

    func makeDigestPacket(to requester: String? = nil) -> CuePacket {
        var packet = CuePacket(type: .digest, senderId: deviceId)
        packet.hashes = currentHashes()
        packet.rev = syncV2.rev
        packet.epoch = syncV2.epoch
        packet.to = requester
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
            packet.epoch = syncV2.epoch
            emitToV2Peers(packet)
        } else {
            var packet = CuePacket(type: .cueUpdate, senderId: deviceId, roleCues: roles)
            packet.rev = nextRev()
            packet.epoch = syncV2.epoch
            emitToV2Peers(packet)
        }
    }

    func makeV2CatchUpPong(to requester: String?) -> CuePacket {
        var messages = Array(SyncHash.sortedNewestFirst(recentMessages).prefix(Self.catchUpMessageLimit))
        var pong = CuePacket(type: .pong, senderId: deviceId, roleCues: roles, timerItem: activeTimerItemForBroadcast, messages: messages)
        pong.nextItem = nextItemForBroadcast
        pong.proto = CuePacket.protocolVersion
        pong.rev = syncV2.rev
        pong.epoch = syncV2.epoch
        pong.to = requester
        stampUtcOffset(&pong)
        while !messages.isEmpty, (pong.encode()?.count ?? 0) > Self.maxCatchUpPongBytes {
            messages.removeLast()
            pong.messages = messages
        }
        while var next = pong.nextItem, (pong.encode()?.count ?? 0) > Self.maxCatchUpPongBytes,
              let longest = next.notes.max(by: { $0.value.utf8.count < $1.value.utf8.count })?.key {
            next.notes.removeValue(forKey: longest)
            pong.nextItem = next
        }
        return pong
    }

    func answerV2CatchUp(origin: PacketOrigin, requester: String? = nil) {
        evaluateMasterTimer()
        if syncV2.lastBroadcastRoles == nil { syncV2.lastBroadcastRoles = roles }
        let pong = makeV2CatchUpPong(to: requester)
        var anchorPacket = CuePacket(type: .timerAnchor, senderId: deviceId, timerItem: syncV2.anchor == nil ? nil : activeTimerItemForBroadcast)
        anchorPacket.nextItem = syncV2.anchor == nil ? nil : nextItemForBroadcast
        anchorPacket.rev = syncV2.rev
        anchorPacket.epoch = syncV2.epoch
        anchorPacket.to = requester
        anchorPacket.anchor = syncV2.anchor
        stampUtcOffset(&anchorPacket)
        let digest = makeDigestPacket(to: requester)
        switch origin {
        case .lanServer(let id):
            server.markProtocolV2(id)
            for packet in [pong, anchorPacket, digest] { emit(packet, .lan(.connection(id))) }
        case .relay:
            syncV2.relayHasV2Peer = true
            for packet in [pong, anchorPacket, digest] { emit(packet, .relay) }
        case .lanClient:
            break
        }
    }

    func answerSync(_ packet: CuePacket, origin: PacketOrigin) {
        guard isMasterServer, !isRemoteMirror, let t0 = packet.t0 else { return }
        var reply = CuePacket(type: .syncReply, senderId: deviceId)
        reply.t0 = t0
        reply.t1 = Int((packet.receivedAtMs ?? SyncClock.nowMs()).rounded())
        reply.epoch = syncV2.epoch
        reply.to = packet.senderId
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
        let marksV2: Bool
        switch packet.type {
        case .pong: marksV2 = packet.rev != nil
        case .timerAnchor, .cueDelta, .digest: marksV2 = true
        case .syncReply: marksV2 = packet.to == deviceId
        default: marksV2 = false
        }
        guard marksV2 else { return }
        syncV2.lastV2PacketMono = monotonicMs
        syncV2.producerIsV2 = true
        if syncV2.estimator.offsetMs == nil { ensureSyncBurst() }
    }

    func processEpoch(_ packet: CuePacket) -> Bool {
        guard !isMasterServer, !isRemoteMirror, let epoch = packet.epoch else { return false }
        let known = syncV2.producerEpoch
        syncV2.producerEpoch = epoch
        guard let known, known != epoch else { return false }
        discardProducerState()
        return true
    }

    func discardProducerState() {
        cancelDisplayTick()
        syncV2.held = nil
        syncV2.gate.reset()
        syncV2.estimator.reset()
        refreshProducerClockOffset()
        syncV2.pendingSyncT0 = []
        syncV2.catchUpInFlight = false
        syncV2.messageMismatchStreak = 0
        syncV2.lastMessageCatchUpMono = nil
        if var item = activeTimerItem, item.isRunning {
            item.isRunning = false
            activeTimerItem = item
        }
    }

    func noteLegacyPacket(_ packet: CuePacket, origin: PacketOrigin) {
        guard !isMasterServer, !isRemoteMirror, syncV2.producerIsV2, packet.rev == nil else { return }
        let now = monotonicMs
        var silent = true
        if let last = syncV2.lastV2PacketMono { silent = now - last > Self.v2SilenceBeforeLegacyCatchUpMs }
        var viaLAN = false
        if case .lanClient = origin { viaLAN = true }
        guard viaLAN || silent else { return }
        if let last = syncV2.lastLegacyCatchUpMono, now - last < Self.legacyCatchUpMinGapMs { return }
        syncV2.lastLegacyCatchUpMono = now
        requestCatchUp()
    }

    func passesRevisionGate(_ packet: CuePacket, epochChanged: Bool = false) -> Bool {
        guard !isMasterServer, syncV2.producerIsV2 else { return true }
        let addressed = packet.to == deviceId
        switch packet.type {
        case .pong:
            if packet.rev != nil { syncV2.gate.rebase(to: packet.rev) }
            return true
        case .cueUpdate, .timerAnchor, .cueDelta:
            return syncV2.gate.accept(packet.rev, strict: !addressed, allowJump: epochChanged)
        case .digest:
            return syncV2.gate.accept(packet.rev, strict: false, allowJump: epochChanged, advance: false)
        default:
            return true
        }
    }

    func applyTimerAnchorPacket(_ packet: CuePacket) {
        guard let anchor = packet.anchor, let item = packet.timerItem, item.id == anchor.itemId else {
            syncV2.held = nil
            cancelDisplayTick()
            if activeTimerItem != nil { activeTimerItem = nil }
            applyReceivedNextItem(nil)
            return
        }
        applyReceivedNextItem(packet.nextItem)
        let stamp = packet.timestamp * 1000
        let sinceAnchor = stamp - Double(anchor.anchorMs)
        let fallback = stamp.isFinite && sinceAnchor >= 0 && sinceAnchor <= Double(TimerAnchor.maxElapsedMs) ? stamp : Double(anchor.anchorMs)
        syncV2.held = HeldAnchor(anchor: anchor, item: item, receivedMonoMs: monotonicMs, fallbackProducerMs: fallback)
        refreshHeldTimer()
        armDisplayTick()
    }

    func applyReceivedNextItem(_ next: CueNextItem?) {
        let item = next?.timerItem
        if nextItem != item { nextItem = item }
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
        let mismatches = localHashes().mismatches(against: remote)
        if mismatches.isEmpty {
            syncV2.messageMismatchStreak = 0
            return
        }
        if mismatches == [.messages] {
            syncV2.messageMismatchStreak += 1
            let now = monotonicMs
            if syncV2.messageMismatchStreak > Self.messageMismatchFreeStreak,
               let last = syncV2.lastMessageCatchUpMono, now - last < Self.messageCatchUpBackoffMs {
                return
            }
            syncV2.lastMessageCatchUpMono = now
        }
        requestCatchUpOnce()
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
        var sorted = SyncHash.sortedNewestFirst(messages)
        if sorted.count > 200 { sorted.removeLast(sorted.count - 200) }
        if recentMessages != sorted { recentMessages = sorted }
    }

    public var producerClock: ProducerClockInfo {
        ProducerClockInfo(offsetMs: producerClockOffsetMs, utcOffsetSeconds: producerUTCOffsetSeconds)
    }

    func refreshProducerClockOffset() {
        let target: Double?
        if isMasterServer && !isRemoteMirror {
            target = 0
            if producerUTCOffsetSeconds != nil { producerUTCOffsetSeconds = nil }
        } else {
            target = isRemoteMirror ? syncV2.mirrorOffsetMs : syncV2.estimator.offsetMs
        }
        if let target, let current = producerClockOffsetMs, abs(target - current) < 2 { return }
        if target == nil && producerClockOffsetMs == nil { return }
        producerClockOffsetMs = target
    }

    func noteProducerUTCOffset(_ packet: CuePacket) {
        guard !isMasterServer, !isRemoteMirror, let utc = packet.utcOffsetSeconds else { return }
        switch packet.type {
        case .cueUpdate, .timerUpdate, .pong, .timerAnchor, .cueDelta, .digest, .syncReply:
            if producerUTCOffsetSeconds != utc { producerUTCOffsetSeconds = utc }
        default:
            break
        }
    }

    public func setRemoteUTCOffset(_ seconds: Int?) {
        guard isRemoteMirror, producerUTCOffsetSeconds != seconds else { return }
        producerUTCOffsetSeconds = seconds
    }

    var syncedProducerNowMs: Double? {
        let local = timerClock().timeIntervalSince1970 * 1000
        let offset = isRemoteMirror ? syncV2.mirrorOffsetMs : syncV2.estimator.offsetMs
        return offset.map { local + $0 }
    }

    var heldProducerNowMs: Double? {
        if let synced = syncedProducerNowMs { return synced }
        guard !isRemoteMirror, let held = syncV2.held else { return nil }
        return held.fallbackProducerMs + max(0, monotonicMs - held.receivedMonoMs)
    }

    func refreshHeldTimer() {
        guard let held = syncV2.held, let nowMs = heldProducerNowMs else { return }
        let item = held.anchor.applying(to: held.item, atProducerMs: Self.clampedInt(nowMs.rounded(.down)))
        if activeTimerItem != item { activeTimerItem = item }
    }

    func cancelDisplayTick() {
        syncV2.displayWorkItem?.cancel()
        syncV2.displayWorkItem = nil
    }

    func armDisplayTick() {
        cancelDisplayTick()
        guard let held = syncV2.held, held.anchor.isRunning, let nowMs = heldProducerNowMs,
              let wait = held.anchor.msUntilNextSecond(atProducerMs: Self.clampedInt(nowMs.rounded(.down))) else { return }
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
        let sample = ClockSyncSample(t0: Double(t0), t1: Double(t1), t2: Double(t2), t3: t3, monotonicMs: monotonicMs)
        guard syncV2.estimator.add(sample, nowMonotonicMs: monotonicMs) else { return }
        refreshProducerClockOffset()
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

    func ensureSyncBurst() {
        guard !isMasterServer, !isRemoteMirror else { return }
        if let last = syncV2.lastBurstMono, monotonicMs - last < Self.burstReissueGapMs { return }
        startSyncBurst()
    }

    func startSyncBurst() {
        guard !isMasterServer, !isRemoteMirror else { return }
        syncV2.lastBurstMono = monotonicMs
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
        client.reconnectNow(force: false)
        syncV2.estimator.clearSamples()
        startSyncBurst()
        refreshHeldTimer()
        armDisplayTick()
    }

    func systemClockDidChange() {
        deviceDidBecomeActive()
    }

    func relayDidConnect() {
        syncV2.relayLinked = true
        guard !isMasterServer, !isRemoteMirror else { return }
        syncV2.estimator.clearSamples()
        requestCatchUp()
        startSyncBurst()
    }

    func relayDidDisconnect() {
        syncV2.relayLinked = false
    }

    func cancelProducerDisplayTick() {
        syncV2.producerWorkItem?.cancel()
        syncV2.producerWorkItem = nil
        syncV2.producerTickDelayMs = nil
    }

    func armProducerDisplayTick() {
        cancelProducerDisplayTick()
        guard isMasterServer, !isRemoteMirror, let anchor = syncV2.anchor, anchor.isRunning,
              let wait = anchor.msUntilNextSecond(atProducerMs: nowMsInt) else { return }
        let delay = wait + 1
        syncV2.producerTickDelayMs = delay
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.syncV2.producerWorkItem = nil
            self.evaluateMasterTimer()
            self.armProducerDisplayTick()
        }
        syncV2.producerWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay), execute: work)
    }

    func resetClientSyncState() {
        cancelDisplayTick()
        syncV2.producerIsV2 = false
        syncV2.estimator.reset()
        refreshProducerClockOffset()
        syncV2.pendingSyncT0 = []
        syncV2.held = nil
        syncV2.gate.reset()
        syncV2.catchUpInFlight = false
        syncV2.ticksSinceSync = 0
        syncV2.producerEpoch = nil
        syncV2.messageMismatchStreak = 0
        syncV2.lastMessageCatchUpMono = nil
        syncV2.lastBurstMono = nil
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
            syncV2.estimator.expire(nowMonotonicMs: monotonicMs)
            refreshProducerClockOffset()
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
        refreshProducerClockOffset()
        refreshHeldTimer()
        armDisplayTick()
    }
}
