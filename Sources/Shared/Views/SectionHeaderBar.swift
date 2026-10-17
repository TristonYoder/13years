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
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Toggle sidebar")
                }

                Text(mode.displayName)
                    .font(.title2.weight(.bold))
                Spacer()
                actions()
                    .labelStyle(.iconOnly)
                    .buttonStyle(SectionHeaderActionButtonStyle())
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
        }
    }
}

struct SectionHeaderActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SectionHeaderActionButton(configuration: configuration)
    }
}

private struct SectionHeaderActionButton: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.title2)
            .foregroundStyle(configuration.role == .destructive ? AnyShapeStyle(AppPalette.negative) : AnyShapeStyle(.primary))
            .frame(width: 52, height: 40)
            .background(
                configuration.isPressed ? AppPalette.surfaceControlPressed : AppPalette.surfaceControl,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
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

public struct HideNativeSidebarToggle: ViewModifier {
    public func body(content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 14.4, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
        #elseif os(iOS)
        if #available(iOS 17.4, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
