// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject var engine: CueEngine

    private static let showsPlotipharIntegration = false

    @State private var plotipharURL: String = "http://localhost:3000"
    @State private var showingPlanPicker = false
    @State private var showingRoleNotes = false
    @State private var showingServiceSchedule = false
    @State private var showingWaypointLibrary = false
    @State private var connectTargetIP: String = ""
    @State private var connectPingSentAt: Date?

    public init() {}

    private var knownNoteCategories: [String] {
        var set = Set(engine.pcoNoteCategories.map(\.name))
        for item in engine.planItems {
            set.formUnion(item.notes.keys)
        }
        return set.sorted()
    }

    public var body: some View {
        VStack(spacing: 0) {
            SectionHeaderBar(mode: .settings)

            settingsForm
        }
    }

    private var settingsForm: some View {
        Form {
            Section {
                if let name = engine.pcoUserName {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Signed in as **\(name)**")
                    }
                }

                Button(action: { engine.signInWithPCO() }) {
                    Label(
                        engine.isPCOConnected ? "Re-authenticate with Planning Center" : "Sign in with Planning Center",
                        systemImage: "person.badge.key.fill"
                    )
                }

                Button(action: { showingPlanPicker = true }) {
                    Label("Choose a Plan to Sync", systemImage: "arrow.triangle.2.circlepath")
                }

                if engine.isPCOConnected {
                    Button(role: .destructive, action: { engine.signOutOfPCO() }) {
                        Label("Sign Out", systemImage: "person.badge.minus")
                    }
                }
            } header: {
                Text("Planning Center Online")
            } footer: {
                Text("Sign in with your PCO account to sync live service plans, item timers, and team assignments. Stays signed in across app launches until you sign out.")
            }

            Section {
                Button(action: { showingRoleNotes = true }) {
                    Label("Roles & Notes", systemImage: "person.text.rectangle")
                }
            } header: {
                Text("Roles")
            } footer: {
                Text("Add, rename, or remove roles, and choose which note categories each one sees on its pager.")
            }

            Section {
                Button(action: { showingWaypointLibrary = true }) {
                    Label("Waypoints", systemImage: Waypoint.symbolName)
                }
            } header: {
                Text("Waypoints")
            } footer: {
                Text("Reusable handles like \u{201C}Song 1\u{201D} that a Stream Deck or Companion button fires by name. Define them once here; each week, assign them to that week's items from Service Flow and every button keeps working.")
            }

            Section {
                Button(action: { showingServiceSchedule = true }) {
                    Label("Service Schedule", systemImage: "clock.badge.checkmark")
                }
            } header: {
                Text("Service Schedule")
            } footer: {
                Text("Pick a lead time before each service and this device goes live automatically — switching into the live producer view and, optionally, loading a specific Planning Center plan. Setup done once, ahead of a week's flow.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    #if !os(tvOS)
                    Slider(
                        value: Binding(
                            get: {
                                Double(HourFormatThreshold.allCases.firstIndex(of: engine.hourFormatThreshold) ?? 1)
                            },
                            set: { newValue in
                                let lastIndex = HourFormatThreshold.allCases.count - 1
                                let index = min(max(Int(newValue.rounded()), 0), lastIndex)
                                engine.hourFormatThreshold = HourFormatThreshold.allCases[index]
                            }
                        ),
                        in: 0...Double(HourFormatThreshold.allCases.count - 1),
                        step: 1
                    )
                    #else
                    Picker("Formatting threshold", selection: $engine.hourFormatThreshold) {
                        ForEach(HourFormatThreshold.allCases) { threshold in
                            Text(threshold.label).tag(threshold)
                        }
                    }
                    .pickerStyle(.segmented)
                    #endif

                    HStack {
                        ForEach(HourFormatThreshold.allCases) { threshold in
                            Text(threshold.label)
                                .font(.caption2)
                                .foregroundStyle(threshold == engine.hourFormatThreshold ? Color.accentColor : .secondary)
                                .fontWeight(threshold == engine.hourFormatThreshold ? .semibold : .regular)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("HH:MM:SS Formatting")
            } footer: {
                Text("Once a duration crosses this threshold, it displays as H:MM:SS instead of MM:SS — e.g. a 95-minute countdown reads 1:35:00 instead of 95:00.")
            }

            Section {
                Toggle("Act as Master Controller", isOn: $engine.isMasterServer)
                    .onChange(of: engine.isMasterServer) { _, _ in
                        engine.toggleMasterMode()
                    }

                if !engine.isMasterServer, let master = engine.connectedMasterName {
                    LabeledContent("Discovered Master") {
                        Text(master)
                            .foregroundStyle(.green)
                            .fontWeight(.medium)
                    }
                }

                LabeledContent("LAN Service") {
                    Text("_13years._tcp : \(String(LANUnicastServer.port))")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Local Network")
            } footer: {
                Text("Devices on the same LAN — Pager apps and ESP32 hardware pagers — discover this device via Bonjour and connect directly for real-time cue delivery.")
            }

            Section {
                ControlAPISettingsSection()
            } header: {
                Text("Control API")
            } footer: {
                Text("Lets a Stream Deck, Bitfocus Companion, QLab, or any script on this network drive cues, timers, and the service flow over HTTP and WebSocket. There is no password on it — anyone who can reach this device on the network can fire a cue, so leave it off on untrusted or guest Wi-Fi. See CONTROL-API.md for the full endpoint reference.")
            }

            Section {
                HStack {
                    TextField("Pager or App IP address", text: $connectTargetIP)
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        #elseif os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                        .autocorrectionDisabled()

                    Button("Send") {
                        let trimmed = connectTargetIP.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, engine.pingDevice(atIP: trimmed) else { return }
                        connectPingSentAt = Date()
                    }
                    .disabled(connectTargetIP.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if let sentAt = connectPingSentAt {
                    Label("Sent — check that device for \"Live\"", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                        .id(sentAt)
                }

                if !engine.isMasterServer {
                    Button("Forget Assigned Producer", role: .destructive) {
                        engine.forgetAssignedProducer()
                    }
                }
            } header: {
                Text("13 Years Pager & App Connect")
            } footer: {
                Text("If an ESP32 hardware pager or another 13 Years app can't find this device on its own (some venue Wi-Fi blocks the discovery it normally uses), type its IP address — shown on its own waiting screen — and send it this device's address directly. It remembers this and skips discovery from then on; \"producer auto\" on an ESP32's Serial console, or \"Forget Assigned Producer\" on another app, undoes that.")
            }

            if Self.showsPlotipharIntegration {
                Section("StagePlotiphar") {
                    TextField("Server URL", text: $plotipharURL)
                        #if os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                }

                Section {
                    PlotipharPairingSection()
                    plotipharAssignmentSyncStatusRow
                } header: {
                    Text("Plotiphar Cloud Proxy")
                } footer: {
                    Text("Paid feature. Pair once with plotiphar.com to sync cue state across separate networks when devices aren't on the same LAN.")
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingPlanPicker) {
            PCOPlanPickerView()
        }
        .sheet(isPresented: $showingRoleNotes) {
            RoleNoteAssignmentView(categories: knownNoteCategories)
        }
        .sheet(isPresented: $showingWaypointLibrary) {
            WaypointLibraryView()
        }
        .sheet(isPresented: $showingServiceSchedule) {
            ServiceScheduleView()
        }
    }

    @ViewBuilder
    private var plotipharAssignmentSyncStatusRow: some View {
        switch engine.plotipharAssignmentSyncStatus {
        case .notSynced, .notPaired:
            EmptyView()
        case .noMatchingEvent:
            Label("No Plotiphar plan matches the one currently loaded — using manual role assignments", systemImage: "person.crop.circle.badge.questionmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .synced:
            Label("Role assignments synced from Plotiphar for this plan", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }
}
