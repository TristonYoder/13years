// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

struct ProducerHostField: View {
    @EnvironmentObject private var engine: CueEngine

    var ink: Color? = nil

    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    #if os(tvOS)
    private static let isTV = true
    #else
    private static let isTV = false
    #endif

    private var primary: Color { ink ?? .primary }
    private var secondary: Color { ink?.opacity(0.7) ?? .secondary }

    var body: some View {
        VStack(spacing: Self.isTV ? 20 : 10) {
            HStack(spacing: Self.isTV ? 20 : 10) {
                TextField("IP or hostname, optional :port", text: $text)
                    .font(.inter(size: Self.isTV ? 33 : 15, weight: .semibold))
                    .foregroundColor(primary)
                    .focused($focused)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .submitLabel(.go)
                    .onSubmit(connect)
                    .onChange(of: text) { error = nil }

                Button("Connect", action: connect)
                    .font(.inter(size: Self.isTV ? 33 : 15, weight: .bold))
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let error {
                Text(error)
                    .font(.inter(size: Self.isTV ? 29 : 13, weight: .semibold))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            if let message = engine.producerLinkStatus.message {
                Text(message)
                    .font(.inter(size: Self.isTV ? 29 : 13, weight: .semibold))
                    .foregroundColor(engine.producerLinkStatus.isProblem ? .red : secondary)
                    .multilineTextAlignment(.center)
            }

            if engine.manualProducerHost != nil {
                Button("Use automatic discovery") {
                    engine.clearManualProducerHost()
                    text = ""
                    error = nil
                }
                .font(.inter(size: Self.isTV ? 29 : 13, weight: .semibold))
            }
        }
        .onAppear { text = engine.manualProducerHost ?? text }
    }

    private func connect() {
        let result = engine.setManualProducerHost(text)
        switch result {
        case .valid:
            text = result.endpoint ?? text
            error = nil
            focused = false
        case .empty:
            error = nil
        case .invalid(let reason):
            error = reason
        }
    }
}
