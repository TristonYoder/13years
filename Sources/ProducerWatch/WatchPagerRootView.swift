// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

struct WatchPagerRootView: View {
    @ObservedObject var model: WatchPagerModel

    var body: some View {
        if model.host.isEmpty {
            WatchSetupView(model: model)
        } else {
            NavigationStack {
                WatchCueView(model: model)
            }
        }
    }
}

struct WatchSetupView: View {
    @ObservedObject var model: WatchPagerModel
    @State private var showingSettings = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                StoplightMarkView(palette: .matching(colorScheme))
                    .frame(width: 64, height: 64)
                Text("Connect with the 13 Years app on your iPhone, or enter the producer's IP address")
                    .font(.system(size: 13, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button {
                    showingSettings = true
                } label: {
                    Label("Set Producer", systemImage: "network")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.bottom)
            .padding(.top, 0)
        }
        .contentMargins(.top, -8, for: .scrollContent)
        .sheet(isPresented: $showingSettings) {
            WatchSettingsView(model: model)
        }
    }
}