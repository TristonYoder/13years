// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

extension View {
    @ViewBuilder
    func compactControlSize() -> some View {
        #if os(tvOS)
        self
        #else
        self.controlSize(.small)
        #endif
    }
}
