// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(iOS) || os(macOS)
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ConnectToView: View {
    let onConnected: (RemoteProducerSession) -> Void
    let onCancel: () -> Void

    @StateObject private var discovery = ProducerDiscovery()
    @State private var address = ""
    @State private var isConnecting = false
    @State private var connectingTo: String?
    @State private var errorText: String?
    @State private var attempt: RemoteProducerSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
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
                    Button("Connect", action: connectManually)
                        .buttonStyle(.borderedProminent)
                        .disabled(isConnecting || address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isConnecting {
                    ProgressView().controlSize(.small)
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
        .padding(24)
        #if os(macOS)
        .frame(width: 460)
        #endif
        .onAppear { discovery.start() }
        .onDisappear {
            discovery.stop()
            attempt?.disconnect()
        }
    }

    @ViewBuilder
    private var discoveredList: some View {
        if discovery.producers.isEmpty {
            if let issue = discovery.browseIssue {
                VStack(alignment: .leading, spacing: 6) {
                    Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    permissionHelp(for: issue)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
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
            connect(to: producer.endpoint, name: producer.displayName)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: reachable == false ? "slash.circle" : "dot.radiowaves.left.and.right")
                    .frame(width: 24)
                    .foregroundStyle(reachable == true ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(producer.displayName).font(.body.weight(.medium))
                    Text(subtitle(for: producer))
                        .font(.caption)
                        .foregroundStyle(reachable == false ? Color.orange : Color.secondary)
                }
                Spacer()
                if reachable == nil { ProgressView().controlSize(.small) }
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

    private func connectManually() {
        guard let endpoint = RemoteEndpoint.parse(address) else {
            errorText = "That doesn't look like an address. Use a host name or IP, optionally followed by :port."
            return
        }
        connect(to: endpoint, name: endpoint.host)
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
                        Color.black.opacity(0.18).allowsHitTesting(false)
                    }
                }
        }
        .id(session.id)
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
        case .reconnecting, .stalled: return Color(red: 1.0, green: 0.78, blue: 0.2)
        case .failed: return Color(red: 0.7, green: 0.15, blue: 0.15)
        default: return .purple
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
                }
                Button("Disconnect", action: onDisconnect)
                    .producerSecondaryButton()
                    .tint(foreground)
            }
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
                        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(.white)
                    }
                }
                .padding(.top, 6)
                .onTapGesture { session.dismissError() }
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(background)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch session.connection {
        case .reconnecting:
            ProgressView().controlSize(.small)
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
#endif
