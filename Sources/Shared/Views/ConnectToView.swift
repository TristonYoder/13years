// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(iOS) || os(macOS)
import SwiftUI

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
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(discovery.browseError ?? "Looking for Producers…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        } else {
            VStack(spacing: 4) {
                ForEach(discovery.producers) { producer in
                    producerRow(producer)
                }
            }
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
                    Text(reachable == false ? "Control API is off on that device" : producer.endpoint.address)
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
                .environmentObject(session.engine)
                .disabled(!session.isLive)
                .overlay {
                    if !session.isLive {
                        Color.black.opacity(0.18).allowsHitTesting(false)
                    }
                }
        }
    }

    private var banner: some View {
        HStack(spacing: 10) {
            if session.connection == .reconnecting {
                ProgressView().controlSize(.small)
                Text("Reconnecting to \(session.displayName)…").font(.callout.weight(.semibold))
            } else {
                Image(systemName: "dot.radiowaves.left.and.right")
                Text("Controlling \(session.displayName)").font(.callout.weight(.semibold))
                if let count = session.state?.settings.connectedAPIClients, count > 1 {
                    Text("· \(count) controllers connected")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            if let error = session.lastError {
                Text(error)
                    .font(.footnote)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.25), in: Capsule())
                    .onTapGesture { session.dismissError() }
            }
            Spacer()
            Button("Disconnect", action: onDisconnect)
                .buttonStyle(.bordered)
                .tint(.white)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(session.connection == .reconnecting ? Color.orange : Color.purple)
    }
}
#endif
