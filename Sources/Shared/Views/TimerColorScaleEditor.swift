// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension Color {
    /// A color from six hex digits (RRGGBB), or nil when the string is not valid.
    init?(timerHex hex: String) {
        guard TimerColorScale.isValidHex(hex), let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Six hex digits (RRGGBB) in sRGB.
    var timerHex: String {
        #if os(macOS)
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let (r, g, b) = (color.redComponent, color.greenComponent, color.blueComponent)
        #else
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (1, 1, 1, 1)
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        func byte(_ component: CGFloat) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

#if os(macOS) || os(iOS)
/// Edits a timer color scale as a list of levels: one color while there is plenty of time, levels that take
/// over as time runs out (by time or percent left), and levels for going over (by time or percent over).
struct TimerColorScaleEditor: View {
    @Binding var scale: TimerColorScale

    private static let maxStops = 12

    var body: some View {
        Section {
            TimerColorPreview(scale: scale)
                .listRowSeparator(.hidden)
        } header: {
            Text("Preview")
        }

        Section {
            Toggle(isOn: Binding(
                get: { scale.onTimeHex != nil },
                set: { scale.onTimeHex = $0 ? "34C759" : nil }
            )) {
                HStack {
                    Text("On time")
                    Spacer()
                    if let hex = scale.onTimeHex {
                        swatch(hex) { scale.onTimeHex = $0 }
                    }
                }
            }
        } footer: {
            Text("Off keeps the normal text color until the first level.")
        }

        Section {
            ForEach(indices(of: .remaining), id: \.self) { index in
                levelRow($scale.stops[index])
            }
            addButton("Add Level", phase: .remaining)
        } header: {
            Text("Running out")
        } footer: {
            Text("A level takes over once the time left falls to its value. With several reached, the one closest to zero wins.")
        }

        Section {
            HStack(spacing: 10) {
                Text("Over time")
                    .frame(width: 66, alignment: .leading)
                Text("from 0:00")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                effectMenu($scale.overtimeEffect)
                swatch(scale.overtimeHex) { scale.overtimeHex = $0 }
            }
            ForEach(indices(of: .overtime), id: \.self) { index in
                levelRow($scale.stops[index])
            }
            addButton("Add Level", phase: .overtime)
        } header: {
            Text("Over time")
        } footer: {
            Text("Red is the default. Add deeper levels that take over once the item is that far over. Each level can add an effect (Pulse, Blink, Flicker, Glitch) to the current item's countdown; None is standard.")
        }

        Section {
            Button("Reset to Standard", role: .destructive) { scale = .standard }
                .disabled(scale.isStandard)
        }
    }

    private func indices(of phase: TimerColorStop.Phase) -> [Int] {
        scale.stops.indices.filter { scale.stops[$0].phase == phase }
    }

    private func addButton(_ title: String, phase: TimerColorStop.Phase) -> some View {
        Button {
            scale.stops.append(phase == .remaining
                ? TimerColorStop(phase: .remaining, value: 60, unit: .seconds, colorHex: "FFD60A")
                : TimerColorStop(phase: .overtime, value: 60, unit: .seconds, colorHex: "FF3B30"))
        } label: {
            Label(title, systemImage: "plus")
        }
        .disabled(scale.stops.count >= Self.maxStops)
    }

    private func levelRow(_ stop: Binding<TimerColorStop>) -> some View {
        HStack(spacing: 10) {
            TimerLevelValueField(value: stop.value, unit: stop.wrappedValue.unit)
                .frame(width: 66)
            Picker("Unit", selection: stop.unit) {
                Text("mm:ss").tag(TimerColorStop.Unit.seconds)
                Text("%").tag(TimerColorStop.Unit.percent)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 92)
            Text(stop.wrappedValue.phase == .remaining ? "left" : "over")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            effectMenu(stop.effect)
            swatch(stop.wrappedValue.colorHex) { stop.wrappedValue.colorHex = $0 }
            Button {
                let id = stop.wrappedValue.id
                scale.stops.removeAll { $0.id == id }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove this level")
            .accessibilityLabel("Remove level")
        }
    }

    private func effectMenu(_ effect: Binding<TimerEffect>) -> some View {
        Picker("Effect", selection: effect) {
            ForEach(TimerEffect.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
        .help("An effect on the countdown to grab attention. None is standard.")
    }

    private func swatch(_ hex: String, set: @escaping (String) -> Void) -> some View {
        ColorPicker("Color", selection: Binding(
            get: { Color(timerHex: hex) ?? .white },
            set: { set($0.timerHex) }
        ), supportsOpacity: false)
        .labelsHidden()
        .frame(width: 40)
    }
}

/// A level's value: minutes and seconds ("1:30", or plain seconds) or a percent, committed on Return or when focus leaves.
private struct TimerLevelValueField: View {
    @Binding var value: Int
    let unit: TimerColorStop.Unit
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .multilineTextAlignment(.trailing)
            .font(.clock(.body, weight: .regular))
            .focused($focused)
            #if os(macOS)
            .textFieldStyle(.roundedBorder)
            #endif
            .onAppear { text = formatted }
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onChange(of: value) { _, _ in if !focused { text = formatted } }
            .onChange(of: unit) { _, _ in text = formatted }
    }

    private var formatted: String {
        unit == .percent ? "\(value)" : TimeFormatting.string(forSeconds: value, threshold: .never)
    }

    private func commit() {
        let parsed = Self.parse(text, unit: unit) ?? value
        value = unit == .percent ? min(max(parsed, 0), 100) : min(max(parsed, 0), 86_400)
        text = formatted
    }

    /// "1:30" is a minute and a half, "1:05:00" an hour and five minutes, and a bare number is seconds (or percent).
    static func parse(_ raw: String, unit: TimerColorStop.Unit) -> Int? {
        let cleaned = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
        guard !cleaned.isEmpty else { return nil }
        if unit == .percent { return Int(cleaned) }
        let parts = cleaned.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.contains(where: { $0 == nil }) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }
}

/// A strip showing the scale across a five-minute item and two minutes of overtime.
struct TimerColorPreview: View {
    let scale: TimerColorScale
    private let length = 300
    private let overtime = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach(0..<(length + overtime), id: \.self) { second in
                        Rectangle()
                            .fill(color(forRemaining: second < length ? length - second : -(second - length + 1)))
                            .frame(width: proxy.size.width / CGFloat(length + overtime))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 14)
            GeometryReader { proxy in
                let zeroX = proxy.size.width * CGFloat(length) / CGFloat(length + overtime)
                ZStack(alignment: .leading) {
                    Text("5:00").position(x: 14, y: 6)
                    Text("0:00").position(x: zeroX, y: 6)
                    Text("+2:00").position(x: proxy.size.width - 16, y: 6)
                }
                .font(.clock(.caption, weight: .regular))
                .foregroundStyle(.secondary)
            }
            .frame(height: 14)
        }
    }

    private func color(forRemaining remaining: Int) -> Color {
        scale.colorHex(remainingSeconds: remaining, lengthSeconds: length).flatMap(Color.init(timerHex:)) ?? Color.primary.opacity(0.35)
    }
}

/// The producer-wide scale, in its own sheet from Settings.
struct TimerColorsSettingsView: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TimerColorScaleEditor(scale: Binding(
                    get: { engine.timerColorScale },
                    set: { engine.setTimerColorScale($0) }
                ))
            }
            .formStyle(.grouped)
            .navigationTitle("Timer Colors")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 520, idealHeight: 600)
        #endif
    }
}

/// A scale for one item or waypoint: off follows the producer-wide scale, on edits its own.
struct TimerColorOverrideSheet: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss
    let title: String
    let current: TimerColorScale?
    let save: (TimerColorScale?) -> Void

    @State private var draft: TimerColorScale
    @State private var isCustom: Bool

    init(title: String, current: TimerColorScale?, save: @escaping (TimerColorScale?) -> Void) {
        self.title = title
        self.current = current
        self.save = save
        _draft = State(initialValue: current ?? .standard)
        _isCustom = State(initialValue: current != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use custom colors", isOn: $isCustom)
                        .onChange(of: isCustom) { _, on in
                            if on && current == nil { draft = engine.timerColorScale }
                        }
                } footer: {
                    Text(isCustom ? "These colors replace the producer-wide scale for \(title)." : "\(title) follows the producer-wide timer colors from Settings, shown here.")
                }
                if isCustom {
                    TimerColorScaleEditor(scale: $draft)
                } else {
                    Section("Inherited") {
                        TimerColorPreview(scale: engine.timerColorScale)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Timer Colors")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(isCustom ? draft : nil)
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 420, idealHeight: 600)
        #endif
    }
}
#endif
