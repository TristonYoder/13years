// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

extension View {
    @ViewBuilder
    func producerSecondaryButton() -> some View {
        #if os(iOS)
        buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 10)).tint(.primary)
        #else
        buttonStyle(.bordered)
        #endif
    }

    @ViewBuilder
    func producerButtonShape() -> some View {
        #if os(iOS)
        buttonBorderShape(.roundedRectangle(radius: 10))
        #else
        self
        #endif
    }
}
