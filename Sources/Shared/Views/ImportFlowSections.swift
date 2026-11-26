// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

/// The import fields, shared by the standalone sheet and the Import text tab of the item editor.
struct ImportFlowSections: View {
    @Binding var planTitle: String
    @Binding var text: String

    private static let placeholder = """
    Pre-Service Countdown | Media | 5:00
    Welcome & Announcements | Header | 3
    Opener: Great Are You Lord | Song | 4:30
    Message
    """

    static func parsedItems(_ text: String) -> [PCOTimerItem] { ServiceFlowImporter.parse(text) }

    var body: some View {
        let parsedItems = Self.parsedItems(text)
        Group {
                Section("Event Title") {
                    TextField("e.g. Sunday Morning", text: $planTitle)
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
    }
}
