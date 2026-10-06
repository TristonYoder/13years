// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct PagerRootView: View {
    @State private var showingSettings = false

    public init() {}

    public var body: some View {
        HostPagerView()
            .overlay(alignment: .bottomTrailing) {
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.inter(size: 16))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(14)
                }
                .accessibilityLabel("Pager Settings")
                .help("Pager settings")
            }
            .sheet(isPresented: $showingSettings) {
                PagerSettingsView()
            }
    }
}
