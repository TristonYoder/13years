// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
import Observation

@MainActor
@Observable
public final class PagerFlashJob {

    public enum State: Equatable {
        case idle
        case running(ESP32Flasher.Progress)
        case succeeded(PagerIdentity)
        case flashedButNotProvisioned(reason: String)
        case failed(reason: String)
    }

    public private(set) var state: State = .idle

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    public var statusMessage: String {
        switch state {
        case .idle:
            return "Ready."
        case let .running(progress):
            return progress.message
        case let .succeeded(identity):
            let rotation = identity.rotate180 ? ", screen rotated 180°" : ""
            return "Done — pager \(identity.deviceID) is on \(identity.ssid) "
                 + "as \(identity.roleID)\(rotation)."
        case let .flashedButNotProvisioned(reason):
            return "Firmware written, but the pager didn’t take its settings: \(reason)"
        case let .failed(reason):
            return reason
        }
    }

    public var progressFraction: Double {
        switch state {
        case .idle: return 0
        case let .running(progress): return progress.fraction
        case .succeeded: return 1
        case .flashedButNotProvisioned: return 1
        case .failed: return 0
        }
    }

    public init() {}

    public func start(port portInfo: SerialPortInfo,
                      firmware: FirmwareImage,
                      provisioning: PagerProvisioning) {
        guard !isRunning else { return }

        if let validation = provisioning.validationError {
            state = .failed(reason: validation)
            return
        }

        state = .running(ESP32Flasher.Progress(phase: .connecting, fraction: 0,
                                               message: "Starting…"))
        let path = portInfo.path

        Task.detached(priority: .userInitiated) { [weak self] in
            let publish: @Sendable (ESP32Flasher.Progress) -> Void = { progress in
                Task { @MainActor [weak self] in
                    guard let self, self.isRunning else { return }
                    self.state = .running(progress)
                }
            }

            let port = SerialPort(path: path)
            do {
                try port.open(baudRate: ESP32Flasher.consoleBaudRate)
            } catch {
                await self?.finish(.failed(reason: error.localizedDescription))
                return
            }
            defer { port.close() }

            let flasher = ESP32Flasher(port: port, onProgress: publish)
            do {
                try flasher.connect()
                try flasher.writeFlash(firmware.data)
                try flasher.restartIntoFirmware()
            } catch {
                await self?.finish(.failed(reason: error.localizedDescription))
                return
            }

            publish(ESP32Flasher.Progress(phase: .finishing, fraction: 0.99,
                                          message: "Waiting for the pager to start up…"))
            PagerProvisioner.waitForConsole(on: port)
            publish(ESP32Flasher.Progress(phase: .finishing, fraction: 0.99,
                                          message: "Sending Wi-Fi settings…"))

            do {
                let identity = try PagerProvisioner.provision(provisioning, over: port)
                await self?.finish(.succeeded(identity))
            } catch {
                await self?.finish(.flashedButNotProvisioned(
                    reason: error.localizedDescription))
            }
        }
    }

    public func provisionOnly(port portInfo: SerialPortInfo,
                              provisioning: PagerProvisioning) {
        guard !isRunning else { return }
        if let validation = provisioning.validationError {
            state = .failed(reason: validation)
            return
        }

        state = .running(ESP32Flasher.Progress(phase: .finishing, fraction: 0.5,
                                               message: "Sending Wi-Fi settings…"))
        let path = portInfo.path

        Task.detached(priority: .userInitiated) { [weak self] in
            let port = SerialPort(path: path)
            do {
                try port.open(baudRate: ESP32Flasher.consoleBaudRate)
            } catch {
                await self?.finish(.failed(reason: error.localizedDescription))
                return
            }
            defer { port.close() }

            do {
                let identity = try PagerProvisioner.provision(provisioning, over: port)
                await self?.finish(.succeeded(identity))
            } catch {
                await self?.finish(.failed(reason: error.localizedDescription))
            }
        }
    }

    public func reset() {
        guard !isRunning else { return }
        state = .idle
    }

    @MainActor
    private func finish(_ outcome: State) {
        state = outcome
    }
}
