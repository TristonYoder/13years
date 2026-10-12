// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(CoreImage)
import CoreImage
import CoreImage.CIFilterBuiltins
#endif

struct CustomScreenURLSection: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.openURL) private var openURL

    @State private var roleName: String?
    @State private var layout: PagerURLBuilder.Layout = .auto
    @State private var cue: PagerURLBuilder.CueDisplay = .viewerChoice
    @State private var showSettings = true
    @State private var showMessages = true
    @State private var addressIndex = 0

    private struct Address: Hashable {
        let host: String
        let port: Int
        var label: String { (host.contains(":") ? "[\(host)]" : host) + ":" + String(port) }
    }

    private var addresses: [Address] {
        if engine.isRemoteMirror {
            #if os(tvOS)
            return []
            #else
            guard let session = engine.remoteCommands as? RemoteProducerSession else { return [] }
            return [Address(host: session.endpoint.host, port: session.endpoint.port)]
            #endif
        }
        return (["127.0.0.1"] + ControlAPIServer.localAddresses())
            .map { Address(host: $0, port: engine.controlAPIPort) }
    }

    private var selectedAddress: Address? {
        let list = addresses
        return list.indices.contains(addressIndex) ? list[addressIndex] : list.first
    }

    private var builder: PagerURLBuilder? {
        guard let address = selectedAddress else { return nil }
        return PagerURLBuilder(
            host: address.host,
            port: address.port,
            role: roleName,
            layout: layout,
            cue: cue,
            showSettings: showSettings,
            showMessages: showMessages
        )
    }

    private var apiOff: Bool { !engine.isRemoteMirror && !engine.isControlAPIEnabled }

    var body: some View {
        Group {
            if apiOff {
                Label("The web pager is served by the Control API, which is off on this Producer", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Toggle("Enable Control API", isOn: $engine.isControlAPIEnabled)
            }

            Picker("Role", selection: $roleName) {
                Text("Any role (viewer chooses)").tag(String?.none)
                ForEach(engine.roles) { role in
                    Text(role.name).tag(String?.some(role.name))
                }
            }

            Picker("Layout", selection: $layout) {
                ForEach(PagerURLBuilder.Layout.allCases) { Text($0.title).tag($0) }
            }

            Picker("Cue display", selection: $cue) {
                ForEach(PagerURLBuilder.CueDisplay.allCases) { Text($0.title).tag($0) }
            }

            Toggle("Show settings button", isOn: $showSettings)
            Toggle("Show messages button", isOn: $showMessages)

            Text("Turn both buttons off for a confidence monitor nobody can click.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if addresses.count > 1 {
                Picker("Address", selection: $addressIndex) {
                    ForEach(Array(addresses.enumerated()), id: \.offset) { index, address in
                        Text(address.label).tag(index)
                    }
                }
            } else if let only = addresses.first {
                LabeledContent("Address") {
                    Text(only.label)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if let builder {
                resultRows(builder.urlString, url: builder.url)
            }
        }
        .onChange(of: engine.roles) { _, roles in
            if let roleName, !roles.contains(where: { $0.name == roleName }) { self.roleName = nil }
        }
    }

    @ViewBuilder
    private func resultRows(_ string: String, url: URL?) -> some View {
        Text(string)
            .font(.system(.footnote, design: .monospaced))
            #if os(iOS) || os(macOS)
            .textSelection(.enabled)
            #endif

        HStack {
            #if os(macOS) || os(iOS)
            Button { copy(string) } label: { Label("Copy", systemImage: "doc.on.doc") }
            #endif
            #if !os(tvOS) && !os(watchOS)
            if let url {
                Button { openURL(url) } label: { Label("Open", systemImage: "safari") }
            }
            #endif
            #if !os(tvOS)
            if let url {
                ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
            }
            #endif
        }
        #if os(macOS)
        .buttonStyle(.bordered)
        #endif

        #if canImport(CoreImage)
        if let image = Self.qrImage(string) {
            HStack {
                Spacer()
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 160, height: 160)
                Spacer()
            }
            .accessibilityLabel("QR code for the pager URL")
        }
        #endif
    }

    #if canImport(CoreImage)
    private static func qrImage(_ string: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
    #endif

    private func copy(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = string
        #endif
    }
}
