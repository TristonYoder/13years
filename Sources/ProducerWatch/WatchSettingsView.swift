// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

struct WatchSettingsView: View {
    @ObservedObject var model: WatchPagerModel

    enum Field: String, Identifiable {
        case ip
        case port
        var id: String { rawValue }

        var title: String {
            switch self {
            case .ip: return "IP address"
            case .port: return "Port"
            }
        }

        var mode: WatchKeypadMode {
            switch self {
            case .ip: return .ipAddress
            case .port: return .portNumber
            }
        }
    }

    @AppStorage(PagerHaptics.strengthDefaultsKey) private var hapticStrength = PagerHaptics.defaultStrength
    @State private var draftHost = ""
    @State private var draftPortText = ""
    @State private var editingField: Field?
    @State private var saveNotice: String?
    @Environment(\.dismiss) private var dismiss

    private var hostDisplay: String {
        draftHost.isEmpty ? "0.0.0.0" : draftHost
    }

    private var portDisplay: String {
        draftPortText.isEmpty ? "13390" : draftPortText
    }

    var body: some View {
        Form {
            Section("Producer") {
                Button {
                    editingField = .ip
                } label: {
                    fieldRow(title: "IP address", value: hostDisplay)
                }
                .buttonStyle(.plain)

                Button {
                    editingField = .port
                } label: {
                    fieldRow(title: "Port", value: portDisplay)
                }
                .buttonStyle(.plain)

                Text("default port 13390")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Button("Save & Connect") {
                    let port = Int(draftPortText) ?? ProducerHTTPPagerClient.defaultPort
                    if model.configure(host: draftHost, port: port) {
                        saveNotice = "Saved — connecting to\n\(model.host):\(model.port)"
                    } else {
                        saveNotice = "That address doesn't parse."
                    }
                }
                .disabled(draftHost.trimmingCharacters(in: .whitespaces).isEmpty)
                if let saveNotice {
                    Text(saveNotice)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Haptics") {
                Slider(value: $hapticStrength, in: 0...1)
                Button("Test Vibration") {
                    PagerHaptics.shared.prepareIfNeeded()
                    PagerHaptics.shared.playTest()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(item: $editingField) { field in
            WatchNumberEntryView(
                mode: field.mode,
                title: field.title,
                initialValue: field == .ip ? draftHost : draftPortText
            ) { newValue in
                if field == .ip {
                    draftHost = newValue
                } else {
                    draftPortText = newValue
                }
            }
        }
        .onAppear {
            draftHost = model.host
            draftPortText = model.port == ProducerHTTPPagerClient.defaultPort ? "" : String(model.port)
        }
    }

    private func fieldRow(title: String, value: String) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }
}