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
                    row(tier: .all)
                    row(tier: .primary)
                    row(tier: .none)
                }
            } else {
                row(tier: .none)
            }

            Divider()
        }
    }

    private func row(tier: HeaderTitleTier) -> some View {
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
            HStack(spacing: 8) {
                actions()
                    .labelStyle(TitledOrIconLabelStyle())
                    .buttonStyle(SectionHeaderActionButtonStyle())
            }
            .environment(\.headerTitleTier, tier)
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

/// How many toolbar actions show their title: all, only those marked primary, or none.
enum HeaderTitleTier { case all, primary, none }

private struct HeaderTitleTierKey: EnvironmentKey { static let defaultValue = HeaderTitleTier.none }
private struct HeaderActionIsPrimaryKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var headerTitleTier: HeaderTitleTier {
        get { self[HeaderTitleTierKey.self] }
        set { self[HeaderTitleTierKey.self] = newValue }
    }
    var headerActionIsPrimary: Bool {
        get { self[HeaderActionIsPrimaryKey.self] }
        set { self[HeaderActionIsPrimaryKey.self] = newValue }
    }
}

extension View {
    /// Keeps this action's title visible when the header is too narrow for every title.
    func headerActionPrimary() -> some View {
        environment(\.headerActionIsPrimary, true)
    }
}

private func headerShowsTitle(tier: HeaderTitleTier, primary: Bool) -> Bool {
    switch tier {
    case .all: return true
    case .primary: return primary
    case .none: return false
    }
}

private struct TitledOrIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        TitledOrIconLabel(configuration: configuration)
    }

    private struct TitledOrIconLabel: View {
        let configuration: LabelStyleConfiguration
        @Environment(\.headerTitleTier) private var tier
        @Environment(\.headerActionIsPrimary) private var primary

        var body: some View {
            if headerShowsTitle(tier: tier, primary: primary) {
                HStack(spacing: 6) {
                    configuration.icon
                    configuration.title.font(.callout.weight(.medium)).lineLimit(1)
                }
            } else {
                configuration.icon
            }
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
    @Environment(\.headerTitleTier) private var tier
    @Environment(\.headerActionIsPrimary) private var primary

    private var showsTitles: Bool { headerShowsTitle(tier: tier, primary: primary) }

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
