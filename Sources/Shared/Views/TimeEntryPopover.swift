// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public extension View {
    func timeEntryPopover(
        isPresented: Binding<Bool>,
        previewBaseSeconds: Int,
        previewElapsedSeconds: Int = 0,
        arrowEdge: Edge = TimeEntryPopoverDefaults.arrowEdge,
        hourFormatThreshold: HourFormatThreshold = .over90Minutes,
        clockFormat: ClockFormat,
        allowsEndAt: Bool = true,
        onCommit: @escaping (TimerInputParser.Action) -> Void
    ) -> some View {
        modifier(TimeEntryPopoverModifier(
            isPresented: isPresented,
            previewBaseSeconds: previewBaseSeconds,
            previewElapsedSeconds: previewElapsedSeconds,
            arrowEdge: arrowEdge,
            hourFormatThreshold: hourFormatThreshold,
            clockFormat: clockFormat,
            allowsEndAt: allowsEndAt,
            onCommit: onCommit
        ))
    }
}

public enum TimeEntryPopoverDefaults {
    #if os(iOS)
    public static let arrowEdge: Edge = .top
    #else
    public static let arrowEdge: Edge = .bottom
    #endif
}

enum TimeEntryPreview {
    static func resolvedSeconds(
        for action: TimerInputParser.Action,
        base: Int,
        elapsed: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        switch action {
        case .setAbsolute(let seconds):
            return max(0, seconds)
        case .adjustRelative(let delta):
            return max(-elapsed, base + delta)
        case .endAt(let time):
            return max(0, time.secondsUntil(now: now, calendar: calendar))
        }
    }
}

private struct TimeEntryPopoverModifier: ViewModifier {
    @Binding var isPresented: Bool
    let previewBaseSeconds: Int
    let previewElapsedSeconds: Int
    let arrowEdge: Edge
    let hourFormatThreshold: HourFormatThreshold
    let clockFormat: ClockFormat
    let allowsEndAt: Bool
    let onCommit: (TimerInputParser.Action) -> Void

    @State private var editBuffer: String = ""
    @State private var isEndAt = false
    @State private var meridiem: Meridiem?
    @FocusState private var isKeypadFocused: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, presented in
                if presented {
                    editBuffer = ""
                    isEndAt = false
                    meridiem = nil
                }
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
            if allowsEndAt {
                endAtToggle
            }
            TimeEntryKeypad(
                isEndAt: isEndAt,
                meridiem: meridiem,
                onDigit: { editBuffer.append($0) },
                onSign: { setSign($0) },
                onMeridiem: { toggleMeridiem($0) },
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
            Text(editBuffer.isEmpty ? (isEndAt ? "Type a time (24h, or pick AM/PM)…" : "Type a time…") : editBuffer)
                .font(editBuffer.isEmpty ? .system(size: 17, weight: .medium) : .inter(size: 17, weight: .medium))
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
        .background(AppPalette.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }

    private var endAtToggle: some View {
        Button {
            toggleEndAt()
        } label: {
            Text("End @")
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .producerSecondaryButton()
        .tint(isEndAt ? Color.accentColor : Color.secondary)
        .foregroundStyle(isEndAt ? Color.accentColor : Color.primary)
    }

    private func toggleMeridiem(_ selected: Meridiem) {
        meridiem = meridiem == selected ? nil : selected
    }

    private func toggleEndAt() {
        isEndAt.toggle()
        editBuffer = ""
        meridiem = nil
    }

    private var parsedAction: TimerInputParser.Action? {
        guard !editBuffer.isEmpty else { return nil }
        return isEndAt ? TimerInputParser.parseEndAt(editBuffer, meridiem: meridiem) : TimerInputParser.parse(editBuffer)
    }

    private var previewText: String {
        guard let action = parsedAction else { return "" }
        let remaining = TimeFormatting.string(forSeconds: resolvedSeconds(for: action), threshold: hourFormatThreshold)
        if case .endAt(let time) = action {
            return "End @ \(time.formatted(clockFormat)) → \(remaining) remaining"
        }
        return remaining
    }

    private func resolvedSeconds(for action: TimerInputParser.Action) -> Int {
        TimeEntryPreview.resolvedSeconds(for: action, base: previewBaseSeconds, elapsed: previewElapsedSeconds)
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
        if allowsEndAt && (raw == "@" || lower == "e") {
            toggleEndAt()
            return .handled
        }
        if isEndAt {
            if lower == "a" || lower == "p" {
                toggleMeridiem(lower == "p" ? .pm : .am)
                return .handled
            }
            return raw == ":" ? appendColon() : .ignored
        }
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

    private func appendColon() -> KeyPress.Result {
        editBuffer.append(":")
        return .handled
    }

    private func commit() {
        defer { isPresented = false }
        guard let action = parsedAction else { return }
        onCommit(action)
    }
}

private struct TimeEntryKeypad: View {
    let isEndAt: Bool
    let meridiem: Meridiem?
    let onDigit: (Character) -> Void
    let onSign: (Character) -> Void
    let onMeridiem: (Meridiem) -> Void
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
                        .disabled(isEndAt)
                    key("m") { onDigit("m") }
                        .disabled(isEndAt)
                    key("s") { onDigit("s") }
                        .disabled(isEndAt)
                }
                GridRow {
                    key("7") { onDigit("7") }
                    key("8") { onDigit("8") }
                    key("9") { onDigit("9") }
                    if isEndAt {
                        key("AM", tint: meridiem == .am ? .accentColor : .primary, selected: meridiem == .am) { onMeridiem(.am) }
                    } else {
                        key("−") { onSign("-") }
                    }
                }
                GridRow {
                    key("4") { onDigit("4") }
                    key("5") { onDigit("5") }
                    key("6") { onDigit("6") }
                    if isEndAt {
                        key("PM", tint: meridiem == .pm ? .accentColor : .primary, selected: meridiem == .pm) { onMeridiem(.pm) }
                            .background(sizeReader)
                    } else {
                        key("+") { onSign("+") }
                            .background(sizeReader)
                    }
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

    private var sizeReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: KeySizePreferenceKey.self, value: proxy.size)
        }
    }

    @ViewBuilder
    private func key(
        _ label: String,
        tint: Color = .primary,
        prominent: Bool = false,
        selected: Bool = false,
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
                .producerSecondaryButton()
                .tint(selected ? Color.accentColor : Color.secondary)
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
