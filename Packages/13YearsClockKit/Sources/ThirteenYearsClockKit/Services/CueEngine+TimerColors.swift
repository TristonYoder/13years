// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

extension CueEngine {
    /// The scale for an item: its own override, else the first of its waypoints that has one, else the producer-wide scale.
    public func timerColorScale(for item: PCOTimerItem) -> TimerColorScale {
        if let own = item.timerColors { return own }
        for id in item.waypointIds {
            if let scale = waypoints.first(where: { $0.id == id })?.timerColors { return scale }
        }
        return timerColorScale
    }

    private var resolvesTimerColorsLocally: Bool { isMasterServer && !isRemoteMirror }

    /// The color to draw an item's countdown in, or nil for the normal text color. The producer resolves its own
    /// scales; a pager or mirror uses the one the producer sent, or the standard scale when none came.
    public func timerColorHex(for item: PCOTimerItem) -> String? {
        timerStyle(for: item).colorHex
    }

    /// The countdown's color and effect for an item right now.
    public func timerStyle(for item: PCOTimerItem) -> (colorHex: String?, effect: TimerEffect) {
        let scale = resolvesTimerColorsLocally ? timerColorScale(for: item) : (receivedTimerColors ?? .standard)
        return scale.style(remainingSeconds: item.remainingSeconds, lengthSeconds: item.lengthInSeconds)
    }

    /// The scale a pager should draw with: the producer's own for its host preview, otherwise what it was sent.
    public var pagerTimerColors: TimerColorScale? {
        resolvesTimerColorsLocally ? broadcastTimerColors : receivedTimerColors
    }

    /// What goes out to pagers and mirrors for the active item. The standard scale is not sent: receivers assume it.
    var broadcastTimerColors: TimerColorScale? {
        guard let item = activeTimerItem else { return nil }
        let scale = timerColorScale(for: item)
        return scale.isStandard ? nil : scale
    }

    func timerColorsDidChange() {
        guard !isRemoteMirror else { return }
        broadcastTimerUpdate()
    }

    public func setTimerColorScale(_ scale: TimerColorScale) {
        if isRemoteMirror {
            remoteCommands?.send(.timerColors(scale))
            return
        }
        timerColorScale = scale
    }

    public func setItemTimerColors(id: String, _ scale: TimerColorScale?) {
        guard !isRemoteMirror, let index = planItems.firstIndex(where: { $0.id == id }),
              planItems[index].timerColors != scale else { return }
        planItems[index].timerColors = scale
        if activeTimerItem?.id == id {
            activeTimerItem?.timerColors = scale
            broadcastTimerUpdate()
        }
    }

    public func setWaypointTimerColors(id: String, _ scale: TimerColorScale?) {
        if isRemoteMirror {
            remoteCommands?.send(.waypointTimerColors(ref: id, scale))
            return
        }
        guard let index = waypoints.firstIndex(where: { $0.id == id }),
              waypoints[index].timerColors != scale else { return }
        waypoints[index].timerColors = scale
        broadcastTimerUpdate()
    }
}
