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
    }

    private var adaptiveNavigation: some View {
        GeometryReader { proxy in
            if proxy.size.height > proxy.size.width {
                tabLayout
            } else {
                splitLayout
            }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(AppMode.sidebarCases, id: \.self, selection: Binding(
                get: { engine.appMode },
                set: { if let mode = $0 { engine.appMode = mode } }
            )) { mode in
                NavigationLink(value: mode) {
                    Label { Text(mode.displayName) } icon: { mode.icon }
                        .font(.body.weight(.medium))
                }
            }
            #if os(iOS) || os(macOS)
            .listStyle(.sidebar)
            #endif
            .navigationTitle("13 Years Producer")
            .modifier(HideNativeSidebarToggle())
        } detail: {
            detailView(for: engine.appMode)
                .modifier(HideNativeSidebarToggle())
        }
        .modifier(HideNativeSidebarToggle())
        .environment(\.toggleSidebar) {
            withAnimation {
                columnVisibility = columnVisibility == .all ? .detailOnly : .all
            }
        }
    }

    private var tabLayout: some View {
        TabView(selection: $engine.appMode) {
            ForEach(AppMode.sidebarCases, id: \.self) { mode in
                NavigationStack { detailView(for: mode) }
                    .tabItem { Label { Text(mode.displayName) } icon: { mode.icon } }
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
