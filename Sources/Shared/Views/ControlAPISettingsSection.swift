// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

public struct ControlAPISettingsSection: View {
    @EnvironmentObject var engine: CueEngine
    @State private var portText: String = ""

    public init() {}

    public var body: some View {
        Group {
            Toggle("Enable Control API", isOn: $engine.isControlAPIEnabled)

            if engine.isControlAPIEnabled {
                statusRow

                HStack {
                    Text("Port")
                    Spacer()
                    TextField("13390", text: $portText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #elseif os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                        .onSubmit(commitPort)
                }

                ForEach(addresses, id: \.self) { address in
                    LabeledContent("Base URL") {
                        Text(address + "/v1")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                            #if os(iOS) || os(macOS)
                            .textSelection(.enabled)
                            #endif
                    }
                }

                webPagerRows

                LabeledContent("Connected Clients") {
                    Text("\(engine.controlAPIClientCount)")
                        .foregroundStyle(engine.controlAPIClientCount > 0 ? .green : .secondary)
                }
            }
        }
        .onAppear { portText = String(engine.controlAPIPort) }
        .onChange(of: engine.controlAPIPort) { _, newValue in
            portText = String(newValue)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if engine.isControlAPIRunning {
            Label("Listening", systemImage: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.green)
                .font(.footnote)
        } else {
            Label("Not listening — retrying (is port \(engine.controlAPIPort) already in use?)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.footnote)
        }
    }

    @ViewBuilder
    private var webPagerRows: some View {
        ForEach(addresses, id: \.self) { address in
            LabeledContent("Web Pager") {
                webPagerLink(address + WebPager.path)
            }
        }

        Text("Open that in any browser for a pager screen. Add `?role=Host` to pin it to one role, and a short, wide window (an OBS browser source, a ribbon display) switches itself to a single lower-third line.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func webPagerLink(_ address: String) -> some View {
        #if os(iOS) || os(macOS)
        if let url = URL(string: address) {
            Link(address, destination: url)
                .font(.system(.footnote, design: .monospaced))
                .contextMenu {
                    Button("Copy Link") { copyToPasteboard(address) }
                }
                .help("Open this pager in your browser")
        } else {
            plainAddress(address)
        }
        #else
        plainAddress(address)
        #endif
    }

    private func plainAddress(_ address: String) -> some View {
        Text(address)
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    private func copyToPasteboard(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = string
        #endif
    }

    private var addresses: [String] {
        (["127.0.0.1"] + ControlAPIServer.localAddresses())
            .map { "http://\($0):\(engine.controlAPIPort)" }
    }

    private func commitPort() {
        guard let port = Int(portText.trimmingCharacters(in: .whitespaces)),
              (1024...65535).contains(port) else {
            portText = String(engine.controlAPIPort)
            return
        }
        engine.controlAPIPort = port
    }
}
