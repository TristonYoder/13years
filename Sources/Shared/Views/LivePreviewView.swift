// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct LivePreviewView: View {
    @EnvironmentObject var engine: CueEngine

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            SectionHeaderBar(mode: .livePreview)

            ScrollView {
                VStack(spacing: 16) {
                    Text("Mirrors exactly what the Host Pager app renders. Use the role picker below to switch which pager screen you're previewing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    phoneFrame

                    if let master = engine.connectedMasterName {
                        Label("Connected to \(master)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else if engine.isMasterServer {
                        Label("Broadcasting as master controller", systemImage: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.blue)
                            .font(.caption)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var phoneFrame: some View {
        HostPagerView()
            .frame(width: 320, height: 660)
            .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .strokeBorder(.black, lineWidth: 10)
            )
            .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
    }
}
