// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

extension CueEngine {
    public func effectiveAutoAdvance(for item: PCOTimerItem) -> Bool {
        item.autoAdvance ?? autoAdvanceByDefault
    }

    public func setItemAutoAdvance(id: String, _ value: Bool?) {
        guard !isRemoteMirror, let index = planItems.firstIndex(where: { $0.id == id }),
              planItems[index].autoAdvance != value else { return }
        planItems[index].autoAdvance = value
        if activeTimerItem?.id == id { activeTimerItem?.autoAdvance = value }
    }

    func evaluateAutoAdvance() {
        guard let item = activeTimerItem, item.isRunning, !item.isHeader, item.lengthInSeconds > 0 else {
            autoAdvanceArmedItemId = nil
            return
        }
        if item.remainingSeconds > 0 {
            autoAdvanceArmedItemId = item.id
            return
        }
        guard autoAdvanceArmedItemId == item.id, effectiveAutoAdvance(for: item), derivedNextPlanItem != nil else { return }
        autoAdvanceArmedItemId = nil
        nextPlanItem()
    }
}
