// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject var engine: CueEngine

    private static let showsPlotipharIntegration = FeatureFlags.plotiphar

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

                if !engine.isRemoteMirror {
                    Button(action: { engine.signInWithPCO() }) {
                        Label(
                            engine.isPCOConnected ? "Re-authenticate with Planning Center" : "Sign in with Planning Center",
                            systemImage: "person.badge.key.fill"
                        )
                    }
                }

                Button(action: { showingPlanPicker = true }) {
                    Label("Choose a Plan to Sync", systemImage: "arrow.triangle.2.circlepath")
                }

                if engine.isPCOConnected && !engine.isRemoteMirror {
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
                Text("Reusable handles like \u{201C}Song 1\u{201D} that a Stream Deck or Companion button fires by name. Define them once here; each week, assign them to that week's items from the Run Sheet and every button keeps working.")
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
                CustomScreenURLSection()
            } header: {
                Text("Custom screen URL")
            } footer: {
                Text("Builds an address for the built-in web pager, for a screen that can't run the app: a laptop, an OBS browser source, a lobby display. Open it in a browser on that screen.")
            }

            Section {
                HStack(spacing: 10) {
                    ForEach([HourFormatThreshold.never, .over90Minutes, .over60Minutes]) { threshold in
                        HourFormatOptionCard(
                            threshold: threshold,
                            isSelected: threshold == engine.hourFormatThreshold
                        ) {
                            engine.setHourFormatThreshold(threshold)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("HH:MM:SS Formatting")
            } footer: {
                Text("Once a duration crosses this threshold, it displays as H:MM:SS instead of MM:SS — the examples show a 75-minute and a 95-minute countdown.")
            }

            #if os(macOS) || os(iOS)
            RemoteProducerSettingsSection()
            #endif

            #if os(macOS) || os(iOS)
            Section {
                LaunchSettingsSection()
            } header: {
                Text("Startup")
            } footer: {
                Text("A template opens as a new untitled document, so the template file itself is never changed except by Save as Template.")
            }
            #endif

            Section {
                if SettingsGating.isLocalControlAPIConfigurable(isRemoteSession: engine.isRemoteMirror) {
                    ControlAPISettingsSection()
                } else {
                    Label("This device’s Control API is off while you control \(engine.remoteProducerName ?? "a remote Producer"). It returns when you disconnect.", systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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

            } header: {
                Text("13 Years Pager & App Connect")
            } footer: {
                Text("If an ESP32 hardware pager or another 13 Years app can't find this device on its own (some venue Wi-Fi blocks the discovery it normally uses), type its IP address — shown on its own waiting screen — and send it the address to connect to. It remembers this and skips discovery from then on; \"producer auto\" on an ESP32's Serial console, or \"Forget Assigned Producer\" on another app, undoes that.")
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
                    Text("Pair once with plotiphar.com to sync cue state across separate networks when devices aren't on the same LAN.")
                }
            }

            #if !os(tvOS)
            UpdateSettingsSection()

            Section {
                Link(destination: URL(string: "https://github.com/TristonYoder/13years")!) {
                    Label("13 Years on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            #endif
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

struct HourFormatOptionCard: View {
    let threshold: HourFormatThreshold
    let isSelected: Bool
    let action: () -> Void

    private static let sampleMinutes = [75, 95]

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(threshold.label)
                    .font(.callout.weight(.semibold))

                VStack(spacing: 2) {
                    ForEach(Self.sampleMinutes, id: \.self) { minutes in
                        Text(TimeFormatting.string(forSeconds: minutes * 60, threshold: threshold))
                            .font(.system(.callout, design: .monospaced))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
