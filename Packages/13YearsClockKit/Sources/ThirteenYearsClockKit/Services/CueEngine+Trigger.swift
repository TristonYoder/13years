// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

extension CueEngine {
    public func effectiveTrigger(for item: PCOTimerItem) -> ItemTrigger {
        item.trigger ?? (followByDefault ? .follow : .go)
    }

    public func setItemTrigger(id: String, _ value: ItemTrigger?) {
        guard !isRemoteMirror, let index = planItems.firstIndex(where: { $0.id == id }),
              planItems[index].trigger != value else { return }
        planItems[index].trigger = value
        if activeTimerItem?.id == id { activeTimerItem?.trigger = value }
    }

    public func isFirstPlanItem(id: String) -> Bool {
        planItems.first(where: { !$0.isHeader })?.id == id
    }

    func evaluateTrigger() {
        guard let item = activeTimerItem, item.isRunning, !item.isHeader, item.lengthInSeconds > 0 else {
            triggerArmedItemId = nil
            return
        }
        if item.remainingSeconds > 0 {
            triggerArmedItemId = item.id
            return
        }
        guard triggerArmedItemId == item.id, let next = derivedNextPlanItem,
              effectiveTrigger(for: next) == .follow else { return }
        triggerArmedItemId = nil
        nextPlanItem()
    }
}
