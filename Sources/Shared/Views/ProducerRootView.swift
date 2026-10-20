// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct ProducerRootView: View {
    @EnvironmentObject var engine: CueEngine
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            #if !os(tvOS)
            if !engine.isRemoteMirror {
                UpdateBannerView()
            }
            #endif

            LiveTimerHeaderView()
                .padding()
                #if os(macOS)
                .padding(.top, -6)
                #endif
                .background(.regularMaterial)

            Divider()

            adaptiveNavigation
        }
        #if os(macOS)
        .ignoresSafeArea(.container, edges: .top)
        #endif
        .task {
            guard !engine.isRemoteMirror else { return }
            UpdateChecker.shared.startPeriodicChecks()
        }
        #if os(macOS) || os(iOS)
        .modifier(MessageNotificationsModifier())
        #endif
    }

    private var adaptiveNavigation: some View {
        #if os(macOS)
        macLayout
        #else
        GeometryReader { proxy in
            if proxy.size.height > proxy.size.width || proxy.size.width < 640 {
                tabLayout
            } else {
                splitLayout
            }
        }
        #endif
    }

    private var sidebarSelection: Binding<AppMode?> {
        Binding(
            get: { engine.appMode },
            set: { if let mode = $0 { engine.appMode = mode } }
        )
    }

    private func sidebarRow(_ mode: AppMode) -> some View {
        Label { Text(mode.displayName) } icon: { mode.icon }
            .font(.body.weight(.medium))
            .modifier(UnreadBadge(count: badgeCount(for: mode)))
    }

    private func badgeCount(for mode: AppMode) -> Int {
        mode == .messages ? engine.unreadMessageCount : 0
    }

    private var toggleSidebarAction: () -> Void {
        {
            withAnimation {
                columnVisibility = columnVisibility == .all ? .detailOnly : .all
            }
        }
    }

    #if os(macOS)
    private var macLayout: some View {
        HStack(spacing: 0) {
            if columnVisibility != .detailOnly {
                List(selection: sidebarSelection) {
                    ForEach(AppMode.sidebarCases, id: \.self) { mode in
                        sidebarRow(mode).tag(mode)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .frame(width: 160)
                .modifier(SidebarPanel())
                .padding(8)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            NavigationStack {
                detailView(for: engine.appMode)
            }
        }
        .environment(\.toggleSidebar, toggleSidebarAction)
    }
    #endif

    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(AppMode.sidebarCases, id: \.self, selection: sidebarSelection) { mode in
                NavigationLink(value: mode) {
                    sidebarRow(mode)
                }
            }
            #if os(iOS)
            .listStyle(.sidebar)
            #endif
            .navigationTitle("13 Years Producer")
            .modifier(HideNativeSidebarToggle())
        } detail: {
            detailView(for: engine.appMode)
                .modifier(HideNativeSidebarToggle())
        }
        .modifier(HideNativeSidebarToggle())
        .environment(\.toggleSidebar, toggleSidebarAction)
    }

    private var tabLayout: some View {
        TabView(selection: $engine.appMode) {
            ForEach(AppMode.sidebarCases, id: \.self) { mode in
                NavigationStack { detailView(for: mode) }
                    .tabItem { Label { Text(mode.displayName) } icon: { mode.icon } }
                    .modifier(UnreadBadge(count: badgeCount(for: mode)))
                    .tag(mode)
            }
        }
        .tint(.accentColor)
    }

    @ViewBuilder
    private func detailView(for mode: AppMode) -> some View {
        switch mode {
        case .producerControl:
            ProducerControlView()
        case .serviceFlow:
            ServiceFlowView()
        case .livePreview:
            ProducerControlView()
        case .messages:
            MessagesView()
        case .settings:
            SettingsView()
        }
    }
}

#if os(macOS)
private struct SidebarPanel: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
        } else {
            material(content, shape)
        }
        #else
        material(content, shape)
        #endif
    }

    private func material(_ content: Content, _ shape: RoundedRectangle) -> some View {
        content
            .background(.regularMaterial, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
    }
}
#endif

private struct UnreadBadge: ViewModifier {
    let count: Int

    func body(content: Content) -> some View {
        #if os(tvOS)
        content
        #else
        content.badge(count)
        #endif
    }
}
