// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct SectionHeaderBar<Actions: View>: View {
    let mode: AppMode
    let showsTitles: Bool
    @ViewBuilder let actions: () -> Actions
    @Environment(\.toggleSidebar) private var toggleSidebar

    /// With `showsTitles`, action buttons show their text beside the icon when the row has room,
    /// and fall back to icons only when it does not.
    public init(mode: AppMode, showsTitles: Bool = false, @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.mode = mode
        self.showsTitles = showsTitles
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showsTitles {
                ViewThatFits(in: .horizontal) {
                    row(titles: true)
                    row(titles: false)
                }
            } else {
                row(titles: false)
            }

            Divider()
        }
    }

    private func row(titles: Bool) -> some View {
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
                .labelStyle(TitledOrIconLabelStyle(showsTitle: titles))
                .buttonStyle(SectionHeaderActionButtonStyle(showsTitles: titles))
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

private struct TitledOrIconLabelStyle: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        if showsTitle {
            HStack(spacing: 6) {
                configuration.icon
                configuration.title.font(.callout.weight(.medium)).lineLimit(1)
            }
        } else {
            configuration.icon
        }
    }
}

struct SectionHeaderActionButtonStyle: ButtonStyle {
    var showsTitles = false

    func makeBody(configuration: Configuration) -> some View {
        SectionHeaderActionButton(configuration: configuration, showsTitles: showsTitles)
    }
}

private struct SectionHeaderActionButton: View {
    let configuration: ButtonStyle.Configuration
    let showsTitles: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.title2)
            .foregroundStyle(configuration.role == .destructive ? AnyShapeStyle(AppPalette.negative) : AnyShapeStyle(.primary))
            .padding(.horizontal, showsTitles ? 10 : 0)
            .frame(minWidth: 52, idealWidth: showsTitles ? nil : 52, maxWidth: showsTitles ? nil : 52, minHeight: 40, maxHeight: 40)
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
