// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public extension View {
    func timeEntryPopover(
        isPresented: Binding<Bool>,
        previewBaseSeconds: Int,
        arrowEdge: Edge = .bottom,
        hourFormatThreshold: HourFormatThreshold = .over90Minutes,
        onCommit: @escaping (TimerInputParser.Action) -> Void
    ) -> some View {
        modifier(TimeEntryPopoverModifier(
            isPresented: isPresented,
            previewBaseSeconds: previewBaseSeconds,
            arrowEdge: arrowEdge,
            hourFormatThreshold: hourFormatThreshold,
            onCommit: onCommit
        ))
    }
}

private struct TimeEntryPopoverModifier: ViewModifier {
    @Binding var isPresented: Bool
    let previewBaseSeconds: Int
    let arrowEdge: Edge
    let hourFormatThreshold: HourFormatThreshold
    let onCommit: (TimerInputParser.Action) -> Void

    @State private var editBuffer: String = ""
    @FocusState private var isKeypadFocused: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, presented in
                if presented { editBuffer = "" }
            }
            #if os(iOS) || os(macOS)
            .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: arrowEdge) {
                popoverContent
            }
            #else
            .sheet(isPresented: $isPresented) {
                popoverContent
            }
            #endif
    }

    private var popoverContent: some View {
        VStack(spacing: 12) {
            screen
            TimeEntryKeypad(
                onDigit: { editBuffer.append($0) },
                onSign: { setSign($0) },
                onClear: { editBuffer = "" },
                onCommit: { commit() }
            )
        }
        .padding(16)
        .focusable()
        .focusEffectDisabled()
        .focused($isKeypadFocused)
        .onKeyPress { handleKeyPress($0) }
        .onAppear {
            DispatchQueue.main.async { isKeypadFocused = true }
        }
        #if os(iOS)
        .presentationCompactAdaptation(.popover)
        #endif
    }

    private var screen: some View {
        VStack(spacing: 2) {
            Text(editBuffer.isEmpty ? "Type a time…" : editBuffer)
                .font(.inter(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(previewText.isEmpty ? " " : previewText)
                .font(.inter(size: 34, weight: .bold))
                .foregroundStyle(previewText.isEmpty ? Color.secondary.opacity(0.4) : Color.primary)
                .lineLimit(1)
                #if !os(tvOS)
                .contentTransition(.numericText())
                #endif
        }
        .frame(minWidth: 220)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }

    private var previewText: String {
        guard !editBuffer.isEmpty, let action = TimerInputParser.parse(editBuffer) else { return "" }
        return TimeFormatting.string(forSeconds: resolvedSeconds(for: action), threshold: hourFormatThreshold)
    }

    private func resolvedSeconds(for action: TimerInputParser.Action) -> Int {
        switch action {
        case .setAbsolute(let seconds):
            return max(0, seconds)
        case .adjustRelative(let delta):
            return max(0, previewBaseSeconds + delta)
        }
    }

    private func setSign(_ sign: Character) {
        if editBuffer.first == sign {
            editBuffer.removeFirst()
        } else {
            if let first = editBuffer.first, first == "+" || first == "-" {
                editBuffer.removeFirst()
            }
            editBuffer.insert(sign, at: editBuffer.startIndex)
        }
    }

    private func backspace() {
        if !editBuffer.isEmpty { editBuffer.removeLast() }
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape {
            isPresented = false
            return .handled
        }
        if press.key == .return {
            commit()
            return .handled
        }
        if press.key == .delete || press.characters == "\u{7F}" || press.characters == "\u{8}" {
            backspace()
            return .handled
        }
        guard press.characters.count == 1, let raw = press.characters.first else { return .ignored }
        if raw.isNumber {
            editBuffer.append(raw)
            return .handled
        }
        let lower = Character(raw.lowercased())
        if lower == "h" || lower == "m" || lower == "s" {
            editBuffer.append(lower)
            return .handled
        }
        if raw == ":" {
            editBuffer.append(raw)
            return .handled
        }
        if raw == "+" || raw == "-" {
            setSign(raw)
            return .handled
        }
        return .ignored
    }

    private func commit() {
        defer { isPresented = false }
        guard !editBuffer.isEmpty, let action = TimerInputParser.parse(editBuffer) else { return }
        onCommit(action)
    }
}

private struct TimeEntryKeypad: View {
    let onDigit: (Character) -> Void
    let onSign: (Character) -> Void
    let onClear: () -> Void
    let onCommit: () -> Void

    private let keySize: CGFloat = 48
    private let spacing: CGFloat = 8

    @State private var measuredKeySize = CGSize(width: 48, height: 48)

    private var doubleContentWidth: CGFloat { keySize + measuredKeySize.width + spacing }
    private var doubleContentHeight: CGFloat { keySize + measuredKeySize.height + spacing }

    var body: some View {
        VStack(spacing: spacing) {
            Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
                GridRow {
                    key("C", tint: .secondary, action: onClear)
                    key("h") { onDigit("h") }
                    key("m") { onDigit("m") }
                    key("s") { onDigit("s") }
                }
                GridRow {
                    key("7") { onDigit("7") }
                    key("8") { onDigit("8") }
                    key("9") { onDigit("9") }
                    key("−") { onSign("-") }
                }
                GridRow {
                    key("4") { onDigit("4") }
                    key("5") { onDigit("5") }
                    key("6") { onDigit("6") }
                    key("+") { onSign("+") }
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: KeySizePreferenceKey.self, value: proxy.size)
                            }
                        )
                }
            }

            HStack(spacing: spacing) {
                VStack(spacing: spacing) {
                    HStack(spacing: spacing) {
                        key("1") { onDigit("1") }
                        key("2") { onDigit("2") }
                        key("3") { onDigit("3") }
                    }
                    HStack(spacing: spacing) {
                        key("0", width: doubleContentWidth) { onDigit("0") }
                        key(":") { onDigit(":") }
                    }
                }
                key("↵", tint: .accentColor, prominent: true, width: keySize, height: doubleContentHeight, action: onCommit)
            }
        }
        .onPreferenceChange(KeySizePreferenceKey.self) { measuredKeySize = $0 }
    }

    @ViewBuilder
    private func key(
        _ label: String,
        tint: Color = .primary,
        prominent: Bool = false,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let content = Text(label)
            .font(.system(.title3, design: .monospaced).weight(.medium))
            .frame(width: width ?? keySize, height: height ?? keySize)

        if prominent {
            Button(action: action) { content }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .foregroundStyle(.white)
        } else {
            Button(action: action) { content }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .foregroundStyle(tint)
        }
    }
}

private struct KeySizePreferenceKey: PreferenceKey {
    static var defaultValue = CGSize(width: 48, height: 48)
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
