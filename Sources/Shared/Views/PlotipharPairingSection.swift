// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct PlotipharPairingSection: View {
    @EnvironmentObject var engine: CueEngine

    public init() {}

    public var body: some View {
        relayHostField

        switch engine.plotipharPairingState {
        case .idle:
            Button(action: { engine.startPlotipharPairing() }) {
                Label("Pair with Plotiphar", systemImage: "link.badge.plus")
            }

        case .starting:
            HStack(spacing: 8) {
                ProgressView()
                Text("Starting pairing…")
                    .foregroundStyle(.secondary)
            }

        case .waitingApproval(let code, let expiresAt):
            VStack(alignment: .leading, spacing: 10) {
                Text("Enter this code at plotiphar.com/pair")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(code)
                    .font(.system(.largeTitle, design: .monospaced).bold())
                    .tracking(4)

                Text("Expires \(expiresAt, style: .relative) from now")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Cancel", role: .cancel) {
                    engine.cancelPlotipharPairing()
                }
            }
            .padding(.vertical, 4)

        case .approved:
            HStack {
                Label("Connected to Plotiphar", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Disconnect", role: .destructive) {
                    engine.disconnectPlotiphar()
                }
            }

            Toggle("Cloud Proxy Active", isOn: $engine.isProxyEnabled)

        case .expired:
            VStack(alignment: .leading, spacing: 10) {
                Label("Pairing code expired", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Try Again") {
                    engine.startPlotipharPairing()
                }
            }

        case .error(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("Try Again") {
                    engine.startPlotipharPairing()
                }
            }
        }
    }

    private var relayHostField: some View {
        HStack {
            Text("Relay Host")
            Spacer()
            TextField("relay.example.com", text: $engine.plotipharRelayHost)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                #if os(iOS)
                .autocapitalization(.none)
                .keyboardType(.URL)
                #endif
                .disableAutocorrection(true)
        }
    }
}
