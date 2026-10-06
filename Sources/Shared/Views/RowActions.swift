// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

extension View {
    func rowActions<Content: View>(@ViewBuilder _ actions: () -> Content) -> some View {
        let content = actions()
        return self
            .contextMenu { content }
            #if os(iOS)
            .swipeActions(edge: .trailing) { content }
            #endif
    }
}

#if os(macOS)
struct RowActionButton: View {
    let systemImage: String
    let label: String
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout)
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}
#endif
