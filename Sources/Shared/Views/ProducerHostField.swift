// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

struct ProducerHostField: View {
    @EnvironmentObject private var engine: CueEngine

    var ink: Color? = nil

    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    private var primary: Color { ink ?? .primary }
    private var secondary: Color { ink?.opacity(0.7) ?? .secondary }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Producer IP or hostname", text: $text)
                    .font(.inter(size: 15, weight: .semibold))
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
                    .font(.inter(size: 15, weight: .bold))
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let error {
                Text(error)
                    .font(.inter(size: 13, weight: .semibold))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            if let message = engine.producerLinkStatus.message {
                Text(message)
                    .font(.inter(size: 13, weight: .semibold))
                    .foregroundColor(engine.producerLinkStatus.isProblem ? .red : secondary)
                    .multilineTextAlignment(.center)
            }

            if engine.manualProducerHost != nil {
                Button("Use automatic discovery") {
                    engine.clearManualProducerHost()
                    text = ""
                    error = nil
                }
                .font(.inter(size: 13, weight: .semibold))
            }
        }
        .onAppear { text = engine.manualProducerHost ?? text }
    }

    private func connect() {
        let result = engine.setManualProducerHost(text)
        switch result {
        case .valid(let host):
            text = host
            error = nil
            focused = false
        case .empty:
            error = nil
        case .invalid(let reason):
            error = reason
        }
    }
}
