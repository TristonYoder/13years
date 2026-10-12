// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

extension View {
    @ViewBuilder
    func producerSecondaryButton() -> some View {
        #if os(iOS)
        buttonStyle(.bordered).tint(.primary)
        #else
        buttonStyle(.bordered)
        #endif
    }
}
