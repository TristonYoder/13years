// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct ImportFlowTextView: View {
    let onImport: (_ title: String, _ items: [PCOTimerItem]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var planTitle: String = ""
    @State private var text: String = ""

    private static let placeholder = """
    Pre-Service Countdown | Media | 5:00
    Welcome & Announcements | Header | 3
    Opener: Great Are You Lord | Song | 4:30
    Message
    """

    public init(onImport: @escaping (_ title: String, _ items: [PCOTimerItem]) -> Void) {
        self.onImport = onImport
    }

    private var parsedItems: [PCOTimerItem] {
        ServiceFlowImporter.parse(text)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Service Title") {
                    TextField("e.g. Sunday Morning Service", text: $planTitle)
                }

                Section {
                    #if os(iOS) || os(macOS)
                    TextEditor(text: $text)
                        .frame(minHeight: 220)
                        .font(.system(.body, design: .monospaced))
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(Self.placeholder)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    #else
                    Text("Text import isn't available on Apple TV.")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                        .padding(.top, 8)
                    #endif
                } header: {
                    Text("Flow")
                } footer: {
                    Text("One item per line: Title | Type | Duration. Type and duration are optional — duration accepts mm:ss or a plain number of minutes.")
                }

                if !text.isEmpty {
                    Section("Preview") {
                        Text("\(parsedItems.count) item\(parsedItems.count == 1 ? "" : "s") will replace the current flow.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Import Flow")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        onImport(planTitle, parsedItems)
                        dismiss()
                    }
                    .disabled(parsedItems.isEmpty)
                }
            }
        }
    }
}
