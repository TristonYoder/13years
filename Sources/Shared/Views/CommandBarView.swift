// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS) || os(iOS)
struct CommandBarView: View {
    @EnvironmentObject var engine: CueEngine
    @Binding var text: String
    @Binding var selectedItemId: String?
    let onClose: () -> Void

    @FocusState private var isFocused: Bool
    @State private var highlighted = 0
    @State private var didNavigate = false
    @State private var armedText: String?
    @State private var feedback: String?

    private let maxRows = 6

    private var analysis: CommandLineAnalysis {
        CommandLine.analyze(text, context: engine.commandLineContext(selectedItemId: selectedItemId))
    }

    var body: some View {
        let analysis = analysis
        let rows = Array(analysis.suggestions.prefix(maxRows))
        VStack(alignment: .leading, spacing: 6) {
            entryRow(analysis, rows: rows)
            translationRow(analysis)
            if !rows.isEmpty { suggestionList(rows, analysis: analysis) }
            footer(analysis)
        }
        .padding(10)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .onAppear { focusAtEnd() }
        .onChange(of: text) { _, _ in
            highlighted = 0
            didNavigate = false
            if armedText != text { armedText = nil }
            feedback = nil
        }
    }

    private func entryRow(_ analysis: CommandLineAnalysis, rows: [CommandLineSuggestion]) -> some View {
        HStack(spacing: 10) {
            label("Entry")
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Text(text).hidden()
                    Text(analysis.ghost).foregroundStyle(.tertiary)
                }
                .lineLimit(1)
                TextField("Type a command, like sto it 3", text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    .onSubmit { submit(analysis) }
                    .onKeyPress(.tab) { accept(rows, analysis) }
                    .onKeyPress(.upArrow) { moveHighlight(-1, count: rows.count) }
                    .onKeyPress(.downArrow) { moveHighlight(1, count: rows.count) }
                    .onKeyPress(.escape) { close() }
            }
            .font(.system(.body, design: .monospaced))
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close command bar")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppPalette.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.accentColor.opacity(0.5), lineWidth: 1))
    }

    private func translationRow(_ analysis: CommandLineAnalysis) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            label("Translation")
            Group {
                if analysis.pieces.isEmpty {
                    Text("Full words appear here as you type").foregroundStyle(.tertiary)
                } else {
                    analysis.pieces.reduce(Text("")) { $0 + Text($1.text + " ").foregroundColor(color(for: $1.kind)) }
                }
            }
            .font(.system(.body, design: .monospaced))
            .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
    }

    private func suggestionList(_ rows: [CommandLineSuggestion], analysis: CommandLineAnalysis) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    text = analysis.completed(with: suggestion)
                    isFocused = true
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(suggestion.word)
                            .font(.system(.callout, design: .monospaced).weight(.medium))
                            .frame(minWidth: 80, alignment: .leading)
                        Text(suggestion.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(suggestion.example)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(index == highlighted ? Color.accentColor.opacity(0.16) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(AppPalette.surfaceSubtle.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func footer(_ analysis: CommandLineAnalysis) -> some View {
        HStack(spacing: 8) {
            statusText(analysis)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Clear") {
                text = ""
                isFocused = true
            }
            .producerSecondaryButton()
            .controlSize(.small)
            Button(armedText == nil ? "Enter" : "Confirm") { submit(analysis) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func statusText(_ analysis: CommandLineAnalysis) -> some View {
        if armedText != nil, let statement = analysis.statement,
           let prompt = engine.commandConfirmationPrompt(statement, selectedItemId: selectedItemId) {
            Text(prompt).foregroundStyle(AppPalette.warning)
        } else if let feedback {
            Text(feedback).foregroundStyle(AppPalette.positive)
        } else {
            switch analysis.status {
            case .empty:
                Text("Start with Store, Label, Move, Copy, Delete, Standby, Go or Item. A number opens time entry.").foregroundStyle(.secondary)
            case .incomplete(let message):
                Text(analysis.hint ?? message).foregroundStyle(.secondary)
            case .ready:
                Text("Ready. Enter runs it.").foregroundStyle(.secondary)
            case .ambiguous(let message):
                Text(message).foregroundStyle(AppPalette.warning)
            case .invalid(let message):
                Text(message).foregroundStyle(AppPalette.negative)
            }
        }
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(width: 74, alignment: .leading)
    }

    private func color(for kind: CommandLinePiece.Kind) -> Color {
        switch kind {
        case .resolved, .value: return .primary
        case .prediction: return .secondary
        case .ambiguous: return AppPalette.warning
        case .invalid: return AppPalette.negative
        }
    }

    private func accept(_ rows: [CommandLineSuggestion], _ analysis: CommandLineAnalysis) -> KeyPress.Result {
        guard !rows.isEmpty else { return .ignored }
        text = analysis.completed(with: rows[min(highlighted, rows.count - 1)])
        return .handled
    }

    private func moveHighlight(_ delta: Int, count: Int) -> KeyPress.Result {
        guard count > 0 else { return .ignored }
        highlighted = min(max(highlighted + delta, 0), count - 1)
        didNavigate = true
        return .handled
    }

    private func close() -> KeyPress.Result {
        onClose()
        return .handled
    }

    private func submit(_ analysis: CommandLineAnalysis) {
        var chosen = analysis
        let rows = Array(analysis.suggestions.prefix(maxRows))
        if didNavigate, !rows.isEmpty {
            let filled = analysis.completed(with: rows[min(highlighted, rows.count - 1)])
            chosen = CommandLine.analyze(filled, context: engine.commandLineContext(selectedItemId: selectedItemId))
            guard chosen.statement != nil else {
                text = filled
                return
            }
            text = filled
        }
        guard let statement = chosen.statement else { return }
        if engine.commandConfirmationPrompt(statement, selectedItemId: selectedItemId) != nil, armedText != text {
            armedText = text
            return
        }
        guard let outcome = engine.runCommand(statement, selectedItemId: selectedItemId) else { return }
        if let id = outcome.selectItemId { selectedItemId = id }
        text = ""
        feedback = outcome.message
        isFocused = true
    }

    private func focusAtEnd() {
        DispatchQueue.main.async {
            isFocused = true
            #if os(macOS)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                    editor.setSelectedRange(NSRange(location: editor.string.count, length: 0))
                }
            }
            #endif
        }
    }
}

#endif

struct CommandItemNumber: ViewModifier {
    @EnvironmentObject var engine: CueEngine
    let itemId: String

    func body(content: Content) -> some View {
        content.overlay(alignment: .leading) {
            if engine.isCommandBarOpen, let index = engine.planItems.firstIndex(where: { $0.id == itemId }) {
                Text(String(index + 1))
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
                    .padding(.leading, 2)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .accessibilityLabel("Item \(index + 1)")
            }
        }
    }
}

extension View {
    func commandItemNumber(_ itemId: String) -> some View {
        modifier(CommandItemNumber(itemId: itemId))
    }
}

#if os(macOS) || os(iOS)
#if os(macOS)
struct CommandBarKeyCapture: NSViewRepresentable {
    let isEnabled: Bool
    let onKey: (String) -> Bool

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onKey = onKey
        view.isEnabled = isEnabled
        return view
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        view.onKey = onKey
        view.isEnabled = isEnabled
    }

    final class CaptureView: NSView {
        var onKey: ((String) -> Bool)?
        var isEnabled = true
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isEnabled, event.window === self.window, self.window?.attachedSheet == nil else { return event }
                if let responder = self.window?.firstResponder, responder is NSTextView || responder is NSTextField { return event }
                guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return event }
                guard let characters = event.characters, characters.count == 1, let first = characters.first, !first.isWhitespace,
                      characters.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 && !(0xF700...0xF8FF).contains($0.value) })
                else { return event }
                return self.onKey?(characters) == true ? nil : event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
#endif

enum CommandBarKeys {
    static func startingText(for press: KeyPress) -> String? {
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        let characters = press.characters
        guard characters.count == 1, let first = characters.first, !first.isWhitespace else { return nil }
        guard characters.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 && !(0xF700...0xF8FF).contains($0.value) }) else { return nil }
        return characters
    }

    static func isTimeEntryStart(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        return (first.isASCII && first.isNumber) || first == "+" || first == "-"
    }
}
#endif
