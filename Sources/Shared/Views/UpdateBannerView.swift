// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

#if !os(tvOS)
public struct UpdateBannerView: View {
    @ObservedObject private var updates = UpdateChecker.shared

    public init() {}

    public var body: some View {
        if let release = updates.bannerRelease {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.tint)
                Text("Version \(release.version) is available")
                    .font(.callout.weight(.semibold))
                Spacer()
                Link("View Release", destination: release.url)
                    .font(.callout.weight(.semibold))
                Button {
                    updates.dismissBanner()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.tint.opacity(0.12))
        }
    }
}

struct UpdateSettingsSection: View {
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some View {
        Section {
            LabeledContent("Current Version", value: updates.currentVersion)

            if let release = updates.availableRelease {
                LabeledContent("Latest Release") {
                    Link("\(release.version) — View Release", destination: release.url)
                }
            } else if updates.lastCheckedAt != nil, !updates.lastCheckFailed {
                Label("You're up to date", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            if updates.lastCheckFailed {
                Label("Couldn't reach GitHub", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Button(updates.isChecking ? "Checking…" : "Check for Updates") {
                Task { await updates.check() }
            }
            .disabled(updates.isChecking)
        } header: {
            Text("Updates")
        }
    }
}
#endif
