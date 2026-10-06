// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct SectionHeaderBar<Actions: View>: View {
    let mode: AppMode
    @ViewBuilder let actions: () -> Actions
    @Environment(\.toggleSidebar) private var toggleSidebar

    public init(mode: AppMode, @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.mode = mode
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let toggleSidebar {
                    Button(action: toggleSidebar) {
                        Image(systemName: "sidebar.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Toggle sidebar")
                }

                mode.icon
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(mode.displayName)
                    .font(.title2.weight(.bold))
                Spacer()
                actions()
                    .labelStyle(.iconOnly)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
        }
    }
}

private struct ToggleSidebarActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    public var toggleSidebar: (() -> Void)? {
        get { self[ToggleSidebarActionKey.self] }
        set { self[ToggleSidebarActionKey.self] = newValue }
    }
}

#if os(macOS)
public struct HideNativeSidebarToggle: ViewModifier {
    public func body(content: Content) -> some View {
        if #available(macOS 14.4, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}
#endif
