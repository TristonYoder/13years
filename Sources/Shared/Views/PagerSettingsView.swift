// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct PagerSettingsView: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PagerHaptics.strengthDefaultsKey) private var hapticStrength: Double = PagerHaptics.defaultStrength

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                #if os(iOS) || os(watchOS)
                if PagerHaptics.isSupported {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Slider(value: $hapticStrength, in: 0...1)
                            HStack {
                                Text("Lowest")
                                Spacer()
                                Text("Max")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)

                        Button("Test Vibration") {
                            PagerHaptics.shared.playTest()
                        }
                    } header: {
                        Text("Vibrate Strength")
                    } footer: {
                        Text("Controls how strong cue changes (Standby/GO!) and incoming messages feel. The iPhone's Taptic Engine is barely felt below about half strength, so \"Lowest\" here is still clearly noticeable — it doesn't go all the way to off.")
                    }
                }
                #endif

                Section {
                    if let master = engine.connectedMasterName {
                        LabeledContent("Connected Master") {
                            Text(master)
                                .foregroundStyle(.green)
                                .fontWeight(.medium)
                        }
                    } else {
                        Label("Searching for producer controller…", systemImage: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.secondary)
                    }

                    if let host = engine.connectedProducerHost, let port = engine.connectedProducerAPIPort {
                        LabeledContent("Producer Address") {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(host)
                                    .font(.system(.body, design: .monospaced))
                                Text("port \(port)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        LabeledContent("Discovery") {
                            Text("_13years._tcp")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Local Network")
                } footer: {
                    Text("This device automatically discovers the 13 Years Producer app on the same Wi-Fi network.")
                }

                Section {
                    PlotipharPairingSection()
                } header: {
                    Text("Plotiphar Cloud Proxy")
                } footer: {
                    Text("Paid feature. Pair once with plotiphar.com if the producer controller isn't on the same local network.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Pager Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                PagerHaptics.shared.prepareIfNeeded()
            }
        }
    }
}
