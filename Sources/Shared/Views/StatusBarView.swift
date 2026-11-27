// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var engine: CueEngine

    private var lanProblem: String? { engine.lanProblemDescription }

    var body: some View {
        if lanProblem != nil || engine.pcoLastError != nil {
            VStack(spacing: 4) {
                if let lanProblem {
                    line(lanProblem, systemImage: "wifi.exclamationmark", color: AppPalette.negative)
                }
                if let error = engine.pcoLastError {
                    line(error, systemImage: "exclamationmark.triangle.fill", color: AppPalette.warning)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func line(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.callout.weight(.medium))
            .foregroundStyle(color)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}
