// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

#if os(iOS)
struct ProducerSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .background(Color.primary.opacity(configuration.isPressed ? 0.26 : 0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
    }
}
#endif

extension View {
    @ViewBuilder
    func producerSecondaryButton() -> some View {
        #if os(iOS)
        buttonStyle(ProducerSecondaryButtonStyle())
        #else
        buttonStyle(.bordered)
        #endif
    }
}
