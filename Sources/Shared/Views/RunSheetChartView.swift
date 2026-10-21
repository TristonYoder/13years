// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS) || os(iOS)
import SwiftUI

struct RunSheetChartSheet: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss
    let item: PCOTimerItem

    @AppStorage("runSheetChartFontSize") private var fontSize = 16.0
    @AppStorage("runSheetChartShowsChords") private var showsChords = true
    @State private var chart: PCOArrangementChart?
    @State private var parsed = ChordChart()
    @State private var loadError: String?
    @State private var isLoading = false

    private static let fontSizeRange = 10.0...40.0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            summary
            content
        }
        .task { await load(force: false) }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 520)
        #endif
    }

    private var reference: (songId: String, arrangementId: String)? {
        PCOAttachmentOwner.chartReference(for: item)
    }

    private var title: String {
        item.details?.song?.title ?? item.title
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if let name = chart?.name ?? item.details?.arrangement?.name, !name.isEmpty {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isLoading { ProgressView().controlSize(.small) }
            Picker("Display", selection: $showsChords) {
                Text("Lyrics").tag(false)
                Text("Chords").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            .disabled(!parsed.hasChords)
            HStack(spacing: 2) {
                Button {
                    fontSize = max(Self.fontSizeRange.lowerBound, fontSize - 2)
                } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .disabled(fontSize <= Self.fontSizeRange.lowerBound)
                .accessibilityLabel("Smaller text")
                Button {
                    fontSize = min(Self.fontSizeRange.upperBound, fontSize + 2)
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .disabled(fontSize >= Self.fontSizeRange.upperBound)
                .accessibilityLabel("Larger text")
            }
            Button {
                Task { await load(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isLoading)
            .accessibilityLabel("Reload chart")
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    @ViewBuilder
    private var summary: some View {
        let facts = summaryFacts
        if !facts.isEmpty || !sequence.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if !facts.isEmpty {
                    HStack(spacing: 14) {
                        ForEach(facts, id: \.label) { fact in
                            HStack(spacing: 4) {
                                Text(fact.label)
                                    .foregroundStyle(.secondary)
                                Text(fact.value)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
                if !sequence.isEmpty {
                    Text(sequence.joined(separator: " \u{2192} "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()
        }
    }

    private var sequence: [String] {
        let fromChart = chart?.sequence ?? []
        if !fromChart.isEmpty { return fromChart }
        return item.details?.effectiveSequenceShort ?? item.details?.arrangement?.sequence ?? []
    }

    private var summaryFacts: [(label: String, value: String)] {
        var facts: [(String, String)] = []
        if let key = chart?.chordChartKey ?? item.details?.displayKey, !key.isEmpty {
            facts.append(("Key", key))
        }
        if let bpm = chart?.bpm ?? item.details?.arrangement?.bpm, bpm > 0 {
            facts.append(("BPM", bpm == bpm.rounded() ? String(Int(bpm)) : String(format: "%.1f", bpm)))
        }
        if let meter = chart?.meter ?? item.details?.arrangement?.meter, !meter.isEmpty {
            facts.append(("Meter", meter))
        }
        return facts
    }

    @ViewBuilder
    private var content: some View {
        if let loadError, chart == nil {
            ContentUnavailableView {
                Label("Couldn't Load Chart", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button("Try Again") { Task { await load(force: true) } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if chart == nil {
            ProgressView("Loading chart\u{2026}")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if parsed.isEmpty {
            ContentUnavailableView(
                "No Chart",
                systemImage: "music.note.list",
                description: Text("This arrangement doesn't have lyrics or a chord chart in Planning Center.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView([.vertical, .horizontal]) {
                chartBody
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var chartBody: some View {
        let chords = showsChords && parsed.hasChords
        return VStack(alignment: .leading, spacing: fontSize * 0.9) {
            ForEach(Array(parsed.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 0) {
                    if let heading = section.title {
                        Text(heading)
                            .font(.system(size: fontSize, weight: .bold))
                            .padding(.bottom, fontSize * 0.3)
                    }
                    let lines = chords ? section.lines : section.lyricLines
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        lineView(line, showsChords: chords)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func lineView(_ line: ChordChart.Line, showsChords: Bool) -> some View {
        if line.isBlank {
            Color.clear.frame(height: fontSize * 0.6)
        } else if showsChords {
            VStack(alignment: .leading, spacing: 0) {
                if !line.chords.isEmpty {
                    Text(verbatim: line.chordRow)
                        .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                }
                if line.hasLyrics {
                    Text(verbatim: line.text)
                        .font(.system(size: fontSize, design: .monospaced))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        } else {
            Text(verbatim: line.text)
                .font(.system(size: fontSize))
        }
    }

    private func load(force: Bool) async {
        guard let reference else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await engine.pcoArrangementChart(songId: reference.songId, arrangementId: reference.arrangementId, forceRefresh: force)
            chart = loaded
            loadError = nil
            let source = loaded.hasChart ? loaded.chordChart : loaded.lyrics
            parsed = ChordChartParser.parse(source ?? "")
        } catch {
            if !(error is CancellationError) { loadError = error.localizedDescription }
        }
    }
}
#endif
