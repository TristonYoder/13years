// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI
import Combine

struct PagerFlashingView: View {
    @EnvironmentObject private var cueEngine: CueEngine

    @State private var job = PagerFlashJob()
    @State private var ports: [SerialPortInfo] = []
    @State private var selectedPortPath: String?
    private let firmware = FirmwareImage.bundled()

    @State private var ssid = ""
    @State private var password = ""
    @State private var roleID = ""
    @State private var useStaticProducer = false
    @State private var producerIP = ""
    @State private var rotate180 = false

    private let rescanTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var selectedPort: SerialPortInfo? {
        ports.first { $0.path == selectedPortPath }
    }

    private var provisioning: PagerProvisioning {
        PagerProvisioning(
            ssid: ssid,
            password: password,
            roleID: roleID.isEmpty ? nil : roleID,
            producerHost: useStaticProducer ? producerIP : "auto",
            rotate180: rotate180
        )
    }

    private var canFlash: Bool {
        selectedPort != nil && firmware != nil
            && provisioning.validationError == nil && !job.isRunning
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                boardSection
                firmwareSection
                networkSection
                mountingSection
            }
            .formStyle(.grouped)

            Divider()
            footer
        }
        .frame(width: 520, height: 700)
        .onAppear { rescanPorts() }
        .onReceive(rescanTimer) { _ in
            guard !job.isRunning else { return }
            rescanPorts()
        }
    }

    private var boardSection: some View {
        Section {
            if ports.filter(\.looksLikeBoard).isEmpty {
                Label("No board found. Connect a pager over USB.", systemImage: "cable.connector")
                    .foregroundStyle(.secondary)
            }
            Picker("Board", selection: $selectedPortPath) {
                Text("Choose…").tag(String?.none)
                ForEach(ports) { port in
                    Text(port.displayName).tag(Optional(port.path))
                }
            }
            .disabled(job.isRunning)
        } header: {
            Text("Board")
        } footer: {
            Text("The board appears as its USB-serial chip — a pager board shows as CH340. "
               + "Close any serial monitor first; only one program can hold the port.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var firmwareSection: some View {
        Section {
            if let firmware {
                LabeledContent("Firmware") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(firmware.byteCount / 1024)K")
                        Text(firmware.md5.prefix(12) + "…")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Label("This build is missing its pager firmware.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Firmware")
        } footer: {
            Text(firmware == nil
                 ? "Rebuild the app with Hardware/esp32/tools/build-firmware.py --out "
                 + "Sources/ProducerMac/Resources/13years-pager-merged.bin."
                 : "Ships with the app, so a pager can only ever be flashed with firmware "
                 + "that matches this version of the Producer.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var networkSection: some View {
        Section {
            TextField("Wi-Fi network", text: $ssid)
            SecureField("Wi-Fi password", text: $password)

            Picker("Role", selection: $roleID) {
                Text("Leave unchanged").tag("")
                ForEach(cueEngine.roles) { role in
                    Text(role.name).tag(role.id)
                }
            }

            Toggle("Use a fixed producer address", isOn: $useStaticProducer)
            if useStaticProducer {
                TextField("Producer IP", text: $producerIP)
                    .textFieldStyle(.roundedBorder)
            }

            if let validation = provisioning.validationError, !ssid.isEmpty || !producerIP.isEmpty {
                Label(validation, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Wi-Fi and role")
        } footer: {
            Text(useStaticProducer
                 ? "A fixed address skips Bonjour discovery — for networks that filter it."
                 : "The pager finds this producer over Bonjour. Turn on a fixed address only if that fails.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .disabled(job.isRunning)
    }

    private var mountingSection: some View {
        Section {
            Toggle("Rotate screen 180°", isOn: $rotate180)
                .disabled(job.isRunning)
        } header: {
            Text("Mounting")
        } footer: {
            Text("For a pager mounted with the cable exiting the other way. "
               + "Turns touch input with the screen, so taps still land where you press.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if job.isRunning || job.progressFraction > 0 {
                ProgressView(value: job.progressFraction)
                    .progressViewStyle(.linear)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                statusIcon
                Text(job.statusMessage)
                    .font(.callout)
                    .foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Set Up Only") {
                    guard let port = selectedPort else { return }
                    job.provisionOnly(port: port, provisioning: provisioning)
                }
                .disabled(selectedPort == nil || provisioning.validationError != nil || job.isRunning)

                Spacer()

                if case .succeeded = job.state {
                    Button("Flash Another") { job.reset() }
                }

                Button(job.isRunning ? "Working…" : "Flash and Set Up") {
                    guard let port = selectedPort, let firmware else { return }
                    job.start(port: port, firmware: firmware, provisioning: provisioning)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canFlash)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.state {
        case .idle:
            EmptyView()
        case .running:
            ProgressView().controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .flashedButNotProvisioned:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private var statusColor: Color {
        switch job.state {
        case .failed: return .red
        case .flashedButNotProvisioned: return .orange
        default: return .secondary
        }
    }

    private func rescanPorts() {
        ports = SerialPortInfo.available()
        if selectedPortPath == nil || !ports.contains(where: { $0.path == selectedPortPath }) {
            let boards = ports.filter(\.looksLikeBoard)
            selectedPortPath = boards.count == 1 ? boards[0].path : nil
        }
    }
}
