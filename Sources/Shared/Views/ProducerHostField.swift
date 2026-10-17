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

    private var fieldFont: Font { .inter(size: Self.isTV ? 33 : 15, weight: .semibold) }
    private var rowHeight: CGFloat { Self.isTV ? 72 : 34 }
    private var radius: CGFloat { Self.isTV ? 16 : 8 }
    private var canConnect: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: Self.isTV ? 20 : 10) {
            HStack(spacing: Self.isTV ? 20 : 10) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(fieldFont)
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .tint(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Self.isTV ? 24 : 12)
                    .frame(height: rowHeight)
                    .background(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )
                    .overlay(
                        Text("IP or hostname, optional :port")
                            .font(.system(size: Self.isTV ? 33 : 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.58))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, Self.isTV ? 24 : 12)
                            .opacity(text.isEmpty ? 1 : 0)
                            .allowsHitTesting(false)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(Color.white.opacity(focused ? 0.6 : 0.3), lineWidth: 1)
                    )
                    #if os(macOS)
                    .focusEffectDisabled()
                    #endif
                    .focused($focused)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .submitLabel(.go)
                    .onSubmit(connect)
                    .onChange(of: text) { error = nil }

                Button(action: connect) {
                    Text("Connect")
                        .font(.system(size: Self.isTV ? 33 : 15, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, Self.isTV ? 28 : 14)
                        .frame(height: rowHeight)
                        .background(
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(Color.white)
                        )
                        .opacity(canConnect ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!canConnect)
            }
            .frame(maxWidth: Self.isTV ? 900 : 420)
            .frame(maxWidth: .infinity)

            if let error {
                Text(error)
                    .font(.system(size: Self.isTV ? 29 : 13, weight: .semibold))
                    .foregroundColor(AppPalette.negative)
                    .multilineTextAlignment(.center)
            }

            if let message = engine.producerLinkStatus.message {
                Text(message)
                    .font(.system(size: Self.isTV ? 29 : 13, weight: .semibold))
                    .foregroundColor(engine.producerLinkStatus.isProblem ? AppPalette.negative : secondary)
                    .multilineTextAlignment(.center)
            }

            if engine.manualProducerHost != nil {
                Button("Use automatic discovery") {
                    engine.clearManualProducerHost()
                    text = ""
                    error = nil
                }
                .font(.system(size: Self.isTV ? 29 : 13, weight: .semibold))
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
