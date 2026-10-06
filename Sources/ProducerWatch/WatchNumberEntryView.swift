// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

enum WatchKeypadMode {
    case ipAddress
    case portNumber
}

struct WatchNumberEntryView: View {
    let mode: WatchKeypadMode
    let title: String
    let initialValue: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var showingTextEntry = false

    init(mode: WatchKeypadMode, title: String, initialValue: String, onSave: @escaping (String) -> Void) {
        self.mode = mode
        self.title = title
        self.initialValue = initialValue
        self.onSave = onSave
        self._text = State(initialValue: initialValue)
    }

    private var isAddress: Bool { mode == .ipAddress }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let gridHeight = max(0, geo.size.height - 72)
                VStack(alignment: .leading, spacing: 0) {
                    display
                    Spacer(minLength: 6)
                    if showingTextEntry {
                        textEntry
                    } else {
                        keypad(height: gridHeight)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 2)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(text)
                        dismiss()
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: showingTextEntry)
    }

    private var display: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayText)
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                Spacer(minLength: 0)
                Button {
                    guard !text.isEmpty else { return }
                    text.removeLast()
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(text.isEmpty ? .tertiary : .secondary)
                .disabled(text.isEmpty)
            }
        }
        .padding(.top, 4)
    }

    private var displayText: String {
        if !text.isEmpty { return text }
        return isAddress ? "0.0.0.0" : "port"
    }

    private var textEntry: some View {
        VStack(spacing: 12) {
            TextField(title, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 18, weight: .medium, design: .monospaced))
            Button {
                showingTextEntry = false
            } label: {
                Label("123", systemImage: "number")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.bordered)
        }
    }

    private func keypad(height: CGFloat) -> some View {
        let spacing: CGFloat = 10
        let rowCount = 4
        let rowHeight = max((height - CGFloat(rowCount - 1) * spacing) / CGFloat(rowCount), 26)

        return Grid(horizontalSpacing: 10, verticalSpacing: spacing) {
            GridRow {
                digit("1", height: rowHeight)
                digit("2", height: rowHeight)
                digit("3", height: rowHeight)
            }
            GridRow {
                digit("4", height: rowHeight)
                digit("5", height: rowHeight)
                digit("6", height: rowHeight)
            }
            GridRow {
                digit("7", height: rowHeight)
                digit("8", height: rowHeight)
                digit("9", height: rowHeight)
            }
            if isAddress {
                GridRow {
                    toggleKey(height: rowHeight)
                    digit(".", height: rowHeight)
                    digit("0", height: rowHeight)
                }
            } else {
                GridRow {
                    digit("0", height: rowHeight)
                }
            }
        }
    }

    private func digit(_ label: String, height: CGFloat) -> some View {
        Button {
            text += label
        } label: {
            Text(label)
                .font(.system(size: 20, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(white: 0.16))
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleKey(height: CGFloat) -> some View {
        Button {
            showingTextEntry.toggle()
        } label: {
            Text("ABC")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(white: 0.16))
                )
        }
        .buttonStyle(.plain)
    }
}