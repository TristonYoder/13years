// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct PagerSettingsView: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PagerHaptics.strengthDefaultsKey) private var hapticStrength: Double = PagerHaptics.defaultStrength
    @AppStorage(CueDisplayStyle.storageKey) private var cueDisplayRaw: String = CueDisplayStyle.defaultStyle.rawValue
    @AppStorage(PagerLayoutChoice.storageKey) private var layoutRaw: String = PagerLayoutChoice.defaultChoice.rawValue
    #if PAGER_MAC
    @AppStorage("keepOnTop") private var keepOnTop = false
    #endif

    public init() {}

    private var connectionState: PagerConnectionState {
        PagerConnectionState(isProducerLive: engine.isMasterServer || engine.isProducerLive, isLANConnected: engine.isLANConnected)
    }

    static func syncText(offsetMs: Double, rttMs: Double?) -> String {
        let offset = String(format: "%+.0f ms", offsetMs)
        guard let rttMs else { return offset }
        return "\(offset), RTT \(String(format: "%.0f", rttMs)) ms"
    }

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
                    Picker("Cue display", selection: $cueDisplayRaw) {
                        ForEach(CueDisplayStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                } header: {
                    Text("Cue Display")
                } footer: {
                    Text("Outline frames the screen in the cue colour. Full screen fills the whole screen with it.")
                }

                #if !os(tvOS)
                Section {
                    Picker("Layout", selection: $layoutRaw) {
                        ForEach(PagerLayoutChoice.allCases) { choice in
                            Text(choice.title).tag(choice.rawValue)
                        }
                    }
                } header: {
                    Text("Layout")
                } footer: {
                    Text("Lower third shows the clock, element name and countdown on a single line. Automatic switches to it on very wide windows. Tap the screen to show the role, messages and settings.")
                }
                #endif

                #if PAGER_MAC
                Section {
                    Toggle("Keep on top", isOn: $keepOnTop)
                } header: {
                    Text("Window")
                } footer: {
                    Text("Keeps this window above other windows.")
                }
                #endif

                Section {
                    LabeledContent("Mode") {
                        Text(engine.manualProducerHost ?? "Automatic")
                            .foregroundStyle(.secondary)
                    }
                    ProducerHostField()
                } header: {
                    Text("Producer")
                } footer: {
                    Text("Automatic finds the producer on this network. Enter an IP address or hostname to connect to one directly, for example when discovery is blocked.")
                }

                Section {
                    LabeledContent("Status") {
                        Text(connectionState.title)
                            .foregroundStyle(connectionState == .live ? Color.green : Color.red)
                            .fontWeight(.medium)
                    }
                    LabeledContent("Producer") {
                        Text(engine.connectedMasterName ?? "—")
                            .foregroundStyle(.secondary)
                    }
                    if let offset = engine.syncV2.estimator.offsetMs {
                        LabeledContent("Clock sync") {
                            Text(Self.syncText(offsetMs: offset, rttMs: engine.syncV2.estimator.best?.effectiveRtt))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Connection")
                }

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

                if FeatureFlags.plotiphar {
                    Section {
                        PlotipharPairingSection()
                    } header: {
                        Text("Plotiphar Cloud Proxy")
                    } footer: {
                        Text("Pair once with plotiphar.com if the producer controller isn't on the same local network.")
                    }
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
