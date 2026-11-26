// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(iOS) || os(macOS)
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ConnectToView: View {
    var prefill: RemoteEndpoint?
    var prefillError: String? = nil
    let onConnected: (RemoteProducerSession) -> Void
    let onCancel: () -> Void

    @StateObject private var discovery = ProducerDiscovery()
    @State private var address = ""
    @State private var isConnecting = false
    @State private var connectingTo: String?
    @State private var errorText: String?
    @State private var attempt: RemoteProducerSession?
    @State private var chosen: (endpoint: RemoteEndpoint, name: String)?
    @State private var mode = RemoteLANMode.stored()

    var body: some View {
        Group {
            if chosen == nil { producerStep } else { modeStep }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 460)
        #endif
        .onAppear {
            discovery.start()
            connectToPrefill()
        }
        .onChange(of: prefill) { _, _ in connectToPrefill() }
        .onDisappear {
            discovery.stop()
            attempt?.disconnect()
        }
    }

    private func stepper(_ step: Int) -> some View {
        HStack(spacing: 6) {
            Text("Step \(step) of 2")
            Text("\u{00B7}")
            Text(step == 1 ? "Producer" : "Mode")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func choose(_ endpoint: RemoteEndpoint, name: String) {
        errorText = nil
        mode = RemoteLANMode.stored()
        chosen = (endpoint, name)
    }

    private var modeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                stepper(2)
                Text("How should this Mac connect?").font(.title2.weight(.bold))
            }
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(chosen?.name ?? "").font(.body.weight(.medium))
                    Text(chosen?.endpoint.address ?? "").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Change") {
                    attempt?.disconnect()
                    isConnecting = false
                    chosen = nil
                }
                .disabled(isConnecting)
            }
            .padding(10)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(spacing: 6) {
                ForEach(RemoteLANMode.allCases, id: \.self) { option in
                    Button { mode = option } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: mode == option ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(mode == option ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.displayName).font(.body.weight(.medium))
                                Text(option.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(mode == option ? 0.9 : 0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(mode == option ? Color.accentColor : Color.clear, lineWidth: 2))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isConnecting)
                }
            }
            Text("Your Control API pauses while connected.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(AppPalette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isConnecting {
                    ProgressView().compactControlSize()
                    Text("Connecting to \(connectingTo ?? "Producer")\u{2026}")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    attempt?.disconnect()
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                Button("Connect") {
                    guard let chosen else { return }
                    if RemoteLANCoordinator.shared.mode != mode { RemoteLANCoordinator.shared.mode = mode }
                    connect(to: chosen.endpoint, name: chosen.name)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isConnecting)
            }
        }
    }

    private var producerStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                stepper(1)
                Text("Connect To…").font(.title2.weight(.bold))
                Text("Control another Producer on this network from here. The Producer you connect to needs its Control API switched on.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("PRODUCERS ON THIS NETWORK")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                discoveredList
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("OR ENTER AN ADDRESS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                HStack {
                    TextField("host or host:port", text: $address)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .onSubmit(connectManually)
                    Button("Next", action: connectManually)
                        .buttonStyle(.borderedProminent)
                        .disabled(isConnecting || address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(AppPalette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isConnecting {
                    ProgressView().compactControlSize()
                    Text("Connecting to \(connectingTo ?? "Producer")…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    attempt?.disconnect()
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    @ViewBuilder
    private var discoveredList: some View {
        if discovery.producers.isEmpty {
            if let issue = discovery.browseIssue {
                VStack(alignment: .leading, spacing: 6) {
                    Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(AppPalette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    permissionHelp(for: issue)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    ProgressView().compactControlSize()
                    Text("Looking for Producers…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        } else {
            VStack(spacing: 4) {
                ForEach(discovery.producers) { producer in
                    producerRow(producer)
                }
            }
        }
    }

    @ViewBuilder
    private func permissionHelp(for issue: BrowseIssue) -> some View {
        if issue != .localNetworkDenied, case .failed = issue {
            EmptyView()
        } else {
            #if os(iOS)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .producerSecondaryButton()
            #else
            Text("System Settings > Privacy & Security > Local Network, then switch on 13 Years Producer.")
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif
        }
    }

    private func producerRow(_ producer: DiscoveredProducer) -> some View {
        let reachable = producer.apiReachable
        return Button {
            choose(producer.endpoint, name: producer.displayName)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: reachable == false ? "slash.circle" : "dot.radiowaves.left.and.right")
                    .frame(width: 24)
                    .foregroundStyle(reachable == true ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(producer.displayName).font(.body.weight(.medium))
                    Text(subtitle(for: producer))
                        .font(.caption)
                        .foregroundStyle(reachable == false ? AppPalette.warning : Color.secondary)
                }
                Spacer()
                if reachable == nil { ProgressView().compactControlSize() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isConnecting || reachable != true)
    }

    private func subtitle(for producer: DiscoveredProducer) -> String {
        switch producer.status {
        case .refused: return "Control API is off on that device"
        case .unreachable: return "Can't reach that device on the network"
        default: return producer.endpoint.address
        }
    }

    private func connectToPrefill() {
        guard let prefill, !isConnecting else { return }
        address = prefill.address
        if let prefillError {
            errorText = prefillError
            return
        }
        connect(to: prefill, name: prefill.name)
    }

    private func connectManually() {
        guard let endpoint = RemoteEndpoint.parse(address) else {
            errorText = "That doesn't look like an address. Use a host name or IP, optionally followed by :port."
            return
        }
        choose(endpoint, name: endpoint.host)
    }

    private func connect(to endpoint: RemoteEndpoint, name: String) {
        guard !isConnecting else { return }
        isConnecting = true
        connectingTo = name
        errorText = nil
        var target = endpoint
        target.name = name
        let session = RemoteProducerSession(endpoint: target)
        attempt = session
        Task {
            await session.connect()
            isConnecting = false
            if session.connection == .connected {
                attempt = nil
                onConnected(session)
            } else {
                if case .failed(let reason) = session.connection { errorText = reason }
                session.disconnect()
                attempt = nil
            }
        }
    }
}

struct RemoteProducerContainerView: View {
    @ObservedObject var session: RemoteProducerSession
    @ObservedObject var lan: RemoteLANCoordinator
    let onDisconnect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            banner
            ProducerRootView()
                .id(session.id)
                .environmentObject(session.engine)
                .disabled(!session.isLive)
                .overlay {
                    if !session.isLive {
                        AppPalette.scrimFaint.allowsHitTesting(false)
                    }
                }
        }
        .id(session.id)
        #if os(macOS)
        .ignoresSafeArea(.container, edges: .top)
        #endif
    }

    private var isWarning: Bool {
        switch session.connection {
        case .reconnecting, .stalled: return true
        default: return false
        }
    }

    private var foreground: Color { isWarning ? .black : .white }

    private var background: Color {
        switch session.connection {
        case .reconnecting, .stalled: return AppPalette.cueStandby
        case .failed: return AppPalette.timerOvertime
        default: return AppPalette.remote
        }
    }

    private var banner: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                statusLabel
                Spacer()
                if case .stalled = session.connection {
                    Button("Reconnect now") { session.reconnectNow() }
                        .buttonStyle(.borderedProminent)
                        .tint(.black)
                        #if os(macOS)
                        .compactControlSize()
                        #endif
                }
                #if os(iOS)
                Menu {
                    Button("Disconnect", role: .destructive, action: onDisconnect)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                }
                .tint(foreground)
                #endif
            }
            .foregroundStyle(foreground)
            #if os(macOS)
            .padding(.leading, 78)
            .padding(.trailing, 14)
            .frame(height: 28)
            #else
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            #endif
            .background(background)

            if !session.recentErrors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(session.recentErrors) { note in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(note.message).font(.footnote.weight(.semibold))
                            if let detail = note.detail {
                                Text(detail).font(.caption)
                            }
                        }
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppPalette.scrimSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(background)
                .onTapGesture { session.dismissError() }
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch session.connection {
        case .reconnecting:
            ProgressView().compactControlSize()
            Text(session.isResyncing ? "Resyncing with \(session.displayName)…" : "Reconnecting to \(session.displayName)…")
                .font(.callout.weight(.semibold))
        case .stalled(let reason):
            Image(systemName: "exclamationmark.triangle.fill")
            Text(stalledText(reason)).font(.callout.weight(.semibold))
        case .failed(let message):
            Image(systemName: "xmark.octagon.fill")
            Text(message).font(.callout.weight(.semibold)).lineLimit(2)
        default:
            Image(systemName: "dot.radiowaves.left.and.right")
            Text("Controlling \(session.displayName)").font(.callout.weight(.semibold))
            if let count = session.state?.settings.connectedAPIClients, count > 1 {
                Text("· \(count) controllers connected")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    private func stalledText(_ reason: RemoteProducerSession.Stall) -> String {
        switch reason {
        case .unreachable: return "\(session.displayName) can't be reached on the network."
        case .refused: return "\(session.displayName) is there, but its Control API is off."
        case .noHello: return "\(session.displayName) didn't start a live connection."
        }
    }
}

struct RemoteProducerSettingsSection: View {
    var body: some View {
        Section {
            RemoteLANModePicker(lan: RemoteLANCoordinator.shared)
        } header: {
            Text("Remote Producer")
        } footer: {
            Text("Applies to the next remote session you start with Connect To…. It has no effect on this device’s own pagers.")
        }
    }
}

struct RemoteLANModePicker: View {
    @ObservedObject var lan: RemoteLANCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Pagers on this network", selection: $lan.mode) {
                ForEach(RemoteLANMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(lan.mode.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let status = lan.statusText {
                Text(status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(lan.isError ? AppPalette.negative : Color.secondary)
            }
        }
    }
}
#endif

#if os(macOS) || os(iOS)
struct RemoteConnectingOverlay: View {
    let name: String
    let cancel: () -> Void

    var body: some View {
        ZStack {
            AppPalette.scrimSoft.ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                Text("Connecting to \(name)…")
                    .font(.headline)
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .transition(.opacity)
    }
}
#endif
