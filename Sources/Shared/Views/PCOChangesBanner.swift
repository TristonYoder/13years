// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

struct PCOChangesBanner: View {
    @EnvironmentObject var engine: CueEngine
    @State private var isExpanded = false

    var body: some View {
        if let pending = engine.pendingPCOChangesForCurrentPlan {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pending.headline)
                            .font(.callout.weight(.semibold))
                        Text("Merging keeps the current item and its timer running.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(isExpanded ? "Hide" : "Details") { isExpanded.toggle() }
                        .buttonStyle(.borderless)
                    Button("Dismiss") { engine.dismissPCOChanges(revision: pending.revision) }
                        .help("Keep the run sheet as it is. This revision won't be offered again.")
                    Button("Merge") { engine.acceptPCOChanges(revision: pending.revision) }
                        .buttonStyle(.borderedProminent)
                        .help("Bring Planning Center's changes into the run sheet")
                }

                if isExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(pending.changes.enumerated()), id: \.offset) { _, change in
                            Label(change.summary, systemImage: symbol(for: change.kind))
                                .font(.caption)
                        }
                    }
                    .padding(.leading, 28)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tint.opacity(0.12))
            .onChange(of: pending.revision) { _, _ in isExpanded = false }
        }
    }

    private func symbol(for kind: PCOPlanChange.Kind) -> String {
        switch kind {
        case .added: return "plus.circle"
        case .removed: return "minus.circle"
        case .retitled: return "pencil"
        case .retyped: return "tag"
        case .length: return "timer"
        case .notes: return "note.text"
        case .reordered: return "arrow.up.arrow.down"
        }
    }
}
