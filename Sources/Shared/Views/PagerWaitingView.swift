// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct PagerWaitingView: View {
    @EnvironmentObject private var engine: CueEngine

    @State private var addresses: [String] = DirectPeerChannel.localIPv4Addresses()

    private static let addressRefresh: TimeInterval = 5

    public init() {}

    #if os(tvOS)
    private static let isTV = true
    #else
    private static let isTV = false
    #endif

    private var ink: Color { StoplightMarkView.Palette.dark.ink }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            SkeletonLoaderView(ink: ink, layout: .pager)

            VStack(spacing: Self.isTV ? 48 : 26) {
                StoplightMarkView(palette: .dark)
                    .frame(maxWidth: Self.isTV ? 380 : 190)

                diagnostics
            }
            .padding(Self.isTV ? 80 : 40)
            .background {
                RadialGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.55),
                        .init(color: .black.opacity(0.85), location: 0.75),
                        .init(color: .black.opacity(0), location: 1.0),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: Self.isTV ? 700 : 300
                )
            }
        }
        .task {
            while !Task.isCancelled {
                addresses = DirectPeerChannel.localIPv4Addresses()
                try? await Task.sleep(nanoseconds: UInt64(Self.addressRefresh * 1_000_000_000))
            }
        }
    }

    @ViewBuilder
    private var diagnostics: some View {
        VStack(spacing: Self.isTV ? 28 : 14) {
            Text("Waiting for Producer…")
                .font(.inter(size: Self.isTV ? 40 : 17, weight: .bold))
                .foregroundColor(ink)

            ProducerHostField(ink: ink)

            if !engine.isLANConnected {
                Text("Not connected to the LAN cue network")
                    .font(.inter(size: Self.isTV ? 29 : 13, weight: .semibold))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            } else {
                VStack(spacing: Self.isTV ? 12 : 6) {
                    if addresses.isEmpty {
                        Text("IP unavailable")
                            .font(.inter(size: Self.isTV ? 33 : 15, weight: .semibold))
                            .foregroundColor(ink.opacity(0.85))
                    } else {
                        VStack(spacing: Self.isTV ? 6 : 3) {
                            ForEach(addresses, id: \.self) { address in
                                Text(address)
                                    .font(.inter(size: Self.isTV ? 33 : 15, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundColor(ink.opacity(0.85))
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: Self.isTV ? 800 : 360)
    }
}
