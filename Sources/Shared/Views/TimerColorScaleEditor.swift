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

/// Edits a timer color scale: a color while there is plenty of time, stops that take over as time runs
/// out (by seconds or percent of the item's length), and a color for overtime. Shows a preview of the
/// colors across a five-minute item.
struct TimerColorScaleEditor: View {
    @Binding var scale: TimerColorScale

    private static let maxStops = 8

    var body: some View {
        Section {
            TimerColorPreview(scale: scale)
                .listRowSeparator(.hidden)

            Toggle("Color while on time", isOn: Binding(
                get: { scale.onTimeHex != nil },
                set: { scale.onTimeHex = $0 ? "34C759" : nil }
            ))
            if let hex = scale.onTimeHex {
                colorRow("On time", hex: hex) { scale.onTimeHex = $0 }
            }
        } header: {
            Text("Preview")
        } footer: {
            Text("Off keeps the normal text color until the first stop.")
        }

        Section {
            ForEach($scale.stops) { $stop in
                stopRow($stop)
            }
            .onDelete { offsets in scale.stops.remove(atOffsets: offsets) }

            Button {
                scale.stops.append(TimerColorStop(value: 60, unit: .seconds, colorHex: "FFD60A"))
            } label: {
                Label("Add Stop", systemImage: "plus")
            }
            .disabled(scale.stops.count >= Self.maxStops)

            colorRow("Overtime", hex: scale.overtimeHex) { scale.overtimeHex = $0 }
        } header: {
            Text("When time is running out")
        } footer: {
            Text("A stop takes over once the time remaining falls to its value. With several stops reached, the one closest to zero wins. Overtime applies once the item runs past its length.")
        }

        Section {
            Button("Reset to Standard", role: .destructive) { scale = .standard }
                .disabled(scale.isStandard)
        }
    }

    private func stopRow(_ stop: Binding<TimerColorStop>) -> some View {
        HStack(spacing: 10) {
            Text("At")
                .foregroundStyle(.secondary)
            TextField("Value", value: stop.value, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                #if os(macOS)
                .textFieldStyle(.roundedBorder)
                #endif
            Picker("Unit", selection: stop.unit) {
                Text("sec left").tag(TimerColorStop.Unit.seconds)
                Text("% left").tag(TimerColorStop.Unit.percent)
            }
            .labelsHidden()
            .fixedSize()
            Spacer()
            ColorPicker("Color", selection: Binding(
                get: { Color(timerHex: stop.wrappedValue.colorHex) ?? .yellow },
                set: { stop.wrappedValue.colorHex = $0.timerHex }
            ), supportsOpacity: false)
            .labelsHidden()
        }
        .onChange(of: stop.wrappedValue.value) { _, value in
            let limit = stop.wrappedValue.unit == .percent ? 100 : 86_400
            if value < 0 || value > limit { stop.wrappedValue.value = min(max(value, 0), limit) }
        }
    }

    private func colorRow(_ title: String, hex: String, set: @escaping (String) -> Void) -> some View {
        ColorPicker(title, selection: Binding(
            get: { Color(timerHex: hex) ?? .white },
            set: { set($0.timerHex) }
        ), supportsOpacity: false)
    }
}

/// A strip showing the scale across a five-minute item, then a little overtime.
private struct TimerColorPreview: View {
    let scale: TimerColorScale
    private let length = 300
    private let overtime = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach(0..<(length + overtime), id: \.self) { second in
                        let remaining = length - second - (second < length ? 0 : 1)
                        Rectangle().fill(color(forRemaining: second < length ? length - second : -(second - length + 1)))
                            .frame(width: proxy.size.width / CGFloat(length + overtime))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 14)
            HStack {
                Text("5:00").font(.clock(.caption, weight: .regular))
                Spacer()
                Text("0:00").font(.clock(.caption, weight: .regular))
                Spacer()
                Text("+0:30").font(.clock(.caption, weight: .regular))
            }
            .foregroundStyle(.secondary)
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
                    Text(isCustom ? "These colors replace the producer-wide scale for \\(title)." : "\\(title) follows the producer-wide timer colors from Settings.")
                }
                if isCustom {
                    TimerColorScaleEditor(scale: $draft)
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
