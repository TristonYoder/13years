// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct ProducerControlView: View {
    @EnvironmentObject var engine: CueEngine
    @State private var messageText: String = ""
    @State private var showingPlanPicker = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            SectionHeaderBar(mode: .producerControl) {
                Button(action: { showingPlanPicker = true }) {
                    Label(engine.isPCOConnected ? "Change Plan" : "Sync PCO", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Pick a Planning Center plan type and plan to sync")
            }

            ScrollView {
                VStack(spacing: 24) {
                    commandDeck
                    roleGrid
                    commsPanel
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingPlanPicker) {
            PCOPlanPickerView()
        }
    }

    private var commandDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Master Control", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                Text("\(engine.selectedRoleIds.count) roles selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(action: { engine.setCueForSelectedRoles(.standby) }) {
                    VStack(spacing: 4) {
                        Text("STANDBY")
                            .font(.system(.title2, weight: .black))
                        Text("Yellow")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundStyle(.black)
                .help("Set STANDBY for the \(engine.selectedRoleIds.count) selected role(s)")

                Button(action: { engine.setCueForSelectedRoles(.go) }) {
                    VStack(spacing: 4) {
                        Text("GO!")
                            .font(.system(.title2, weight: .black))
                        Text("Green")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .help("Set GO for the \(engine.selectedRoleIds.count) selected role(s)")

                Button(action: { engine.setCueForSelectedRoles(.off) }) {
                    Text("CLEAR")
                        .font(.headline)
                        .padding(.vertical, 16)
                        .frame(width: 80)
                }
                .buttonStyle(.bordered)
                .help("Clear the cue for the \(engine.selectedRoleIds.count) selected role(s)")
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var roleGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Roles", systemImage: "person.3.fill")
                    .font(.headline)
                Spacer()
                Button("Clear All", role: .destructive) {
                    engine.clearAllCues()
                }
                .controlSize(.small)
                .help("Clear the cue for every role")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                ForEach(engine.roles) { role in
                    roleCard(role)
                }
            }
        }
    }

    private func roleCard(_ role: RoleCue) -> some View {
        let isSelected = engine.selectedRoleIds.contains(role.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(role.name)
                        .font(.headline)
                    if let person = role.personName {
                        Text(person)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(role.state.displayName)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(role.state.color.opacity(0.2), in: Capsule())
                    .foregroundStyle(role.state.color)
            }

            HStack(spacing: 8) {
                Button("Standby") { engine.setCueForRole(id: role.id, state: .standby) }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundStyle(.black)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)

                Button("GO!") { engine.setCueForRole(id: role.id, state: .go) }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)

                Button("Off") { engine.setCueForRole(id: role.id, state: .off) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? .blue : .clear, lineWidth: 2)
        )
        .onTapGesture { engine.toggleRoleSelection(role.id) }
    }

    private var commsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Crew Messages", systemImage: "message.fill")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("Message for host / crew…", text: $messageText)
                    #if os(macOS)
                    .textFieldStyle(.roundedBorder)
                    #endif

                Button("Send") {
                    engine.sendMessage(messageText)
                    messageText = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(messageText.isEmpty)
            }

            if !engine.recentMessages.isEmpty {
                ForEach(engine.recentMessages.prefix(4)) { msg in
                    HStack {
                        Text(msg.sender)
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
                        Text(msg.text)
                            .font(.callout)
                        Spacer()
                        Text(msg.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
