// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct ProducerRootView: View {
    @EnvironmentObject var engine: CueEngine
    #if os(macOS)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    #endif

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            LiveTimerHeaderView()
                .padding()
                .background(.regularMaterial)

            Divider()

            #if os(macOS)
            macOSNavigationSplitView
            #else
            iPadNavigationLayout
            #endif
        }
    }

    #if os(macOS)
    private var macOSNavigationSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(AppMode.allCases, id: \.self, selection: Binding(
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
        } detail: {
            detailView(for: engine.appMode)
        }
        .modifier(HideNativeSidebarToggle())
        .environment(\.toggleSidebar) {
            withAnimation {
                columnVisibility = columnVisibility == .all ? .detailOnly : .all
            }
        }
    }
    #endif

    private var iPadNavigationLayout: some View {
        TabView(selection: $engine.appMode) {
            ForEach(AppMode.allCases, id: \.self) { mode in
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
            LivePreviewView()
        case .messages:
            MessagesView()
        case .settings:
            SettingsView()
        }
    }
}
