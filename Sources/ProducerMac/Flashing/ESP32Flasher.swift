// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
import CryptoKit

public final class ESP32Flasher {

    public struct Progress: Sendable, Equatable {
        public enum Phase: Sendable, Equatable {
            case connecting
            case erasing
            case writing(bytesSent: Int, totalBytes: Int)
            case verifying
            case finishing
        }
        public let phase: Phase
        public let fraction: Double
        public let message: String
    }

    public enum FlashError: LocalizedError {
        case notInBootloader
        case unsupportedChip(magic: UInt32, name: String?)
        case commandFailed(command: String, errorCode: UInt8)
        case noResponse(command: String)
        case verificationMismatch(expected: String, actual: String)
        case imageTooLarge(bytes: Int, limit: Int)

        public var errorDescription: String? {
            switch self {
            case .notInBootloader:
                return "Couldn’t get the pager into its bootloader. Unplug it, plug it back in, "
                     + "and make sure no serial monitor is attached."
            case let .unsupportedChip(magic, name):
                if let name {
                    return "That board is an \(name). This firmware is built for the ESP32 pager board."
                }
                return String(format: "Unrecognised board (chip id 0x%08x).", magic)
            case let .commandFailed(command, code):
                return "The pager rejected \(command): \(ESPSerialProtocol.describeError(code))."
            case let .noResponse(command):
                return "The pager stopped responding during \(command)."
            case let .verificationMismatch(expected, actual):
                return "The firmware didn’t verify after writing "
                     + "(expected \(expected.prefix(8))…, got \(actual.prefix(8))…). Don’t use this unit; flash it again."
            case let .imageTooLarge(bytes, limit):
                return "That firmware image is \(bytes) bytes, larger than the \(limit)-byte flash."
            }
        }
    }

    private static let blockSize = 1024
    private static let flashSize: UInt32 = 4 * 1024 * 1024
    public static let consoleBaudRate = 115_200
    public static let transferBaudRate = 460_800

    private let port: SerialPort
    private let progressHandler: (Progress) -> Void
    private var readBuffer = Data()
    private var currentBaudRate: Int

    public init(port: SerialPort, onProgress: @escaping (Progress) -> Void = { _ in }) {
        self.port = port
        self.progressHandler = onProgress
        self.currentBaudRate = Self.consoleBaudRate
    }

    public func connect(attempts: Int = 7) throws {
        report(.connecting, 0.0, "Looking for the pager…")

        for attempt in 1...attempts {
            try resetIntoBootloader()

            readBuffer.removeAll()
            port.flush()

            if trySync() {
                report(.connecting, 0.04, "Connected to the pager.")
                try confirmChipIsESP32()
                try configureFlashParameters()
                raiseBaudRate()
                return
            }
            report(.connecting, 0.01 * Double(attempt), "Still looking for the pager…")
        }
        throw FlashError.notInBootloader
    }

    private func resetIntoBootloader() throws {
        try port.setControlLines(dtr: false, rts: false)
        try port.setControlLines(dtr: false, rts: true)
        Thread.sleep(forTimeInterval: 0.1)
        try port.setControlLines(dtr: true, rts: false)
        Thread.sleep(forTimeInterval: 0.05)
        try port.setControlLines(dtr: false, rts: false)
        Thread.sleep(forTimeInterval: 0.05)
    }

    private func trySync() -> Bool {
        for _ in 0..<5 {
            guard (try? port.write(ESPSerialProtocol.syncRequest())) != nil else { return false }
            if let response = try? awaitResponse(to: .sync, timeout: 0.35), response.isSuccess {
                drain(for: 0.05)
                return true
            }
        }
        return false
    }

    private func confirmChipIsESP32() throws {
        let magic = try readRegister(ESPSerialProtocol.chipDetectRegister)
        guard magic == ESPSerialProtocol.esp32Magic else {
            throw FlashError.unsupportedChip(magic: magic, name: ESPSerialProtocol.chipMagic[magic])
        }
    }

    private func configureFlashParameters() throws {
        _ = try send(ESPSerialProtocol.spiAttachRequest(),
                     command: .spiAttach, label: "connecting to flash", timeout: 3)
        _ = try send(ESPSerialProtocol.spiSetParametersRequest(flashSize: Self.flashSize),
                     command: .spiSetParameters, label: "flash setup", timeout: 3)
    }

    private func raiseBaudRate() {
        guard Self.transferBaudRate != currentBaudRate else { return }
        let request = ESPSerialProtocol.changeBaudRateRequest(to: UInt32(Self.transferBaudRate),
                                                             from: UInt32(currentBaudRate))
        guard (try? port.write(request)) != nil,
              let response = try? awaitResponse(to: .changeBaudRate, timeout: 2),
              response.isSuccess
        else { return }

        guard (try? port.setBaudRate(Self.transferBaudRate)) != nil else { return }
        currentBaudRate = Self.transferBaudRate
        Thread.sleep(forTimeInterval: 0.05)
        readBuffer.removeAll()
        port.flush()

        if (try? readRegister(ESPSerialProtocol.chipDetectRegister)) == nil {
            try? port.setBaudRate(Self.consoleBaudRate)
            currentBaudRate = Self.consoleBaudRate
            readBuffer.removeAll()
            port.flush()
        }
    }

    public func writeFlash(_ image: Data, at offset: UInt32 = 0) throws {
        guard image.count <= Int(Self.flashSize) else {
            throw FlashError.imageTooLarge(bytes: image.count, limit: Int(Self.flashSize))
        }

        let blockCount = (image.count + Self.blockSize - 1) / Self.blockSize
        report(.erasing, 0.05, "Erasing…")

        _ = try send(ESPSerialProtocol.flashBeginRequest(size: UInt32(image.count),
                                                        blockCount: UInt32(blockCount),
                                                        blockSize: UInt32(Self.blockSize),
                                                        offset: offset),
                     command: .flashBegin, label: "erase", timeout: 60)

        var sent = 0
        for sequence in 0..<blockCount {
            let start = sequence * Self.blockSize
            let end = min(start + Self.blockSize, image.count)
            var payload = image.subdata(in: start..<end)
            if payload.count < Self.blockSize {
                payload.append(Data(repeating: 0xFF, count: Self.blockSize - payload.count))
            }

            _ = try send(ESPSerialProtocol.flashDataRequest(payload: payload, sequence: UInt32(sequence)),
                         command: .flashData, label: "writing", timeout: 5)

            sent = end
            let fraction = 0.10 + 0.80 * (Double(sent) / Double(image.count))
            report(.writing(bytesSent: sent, totalBytes: image.count), fraction,
                   "Writing firmware… \(sent / 1024)K of \(image.count / 1024)K")
        }

        try verify(image, at: offset)

        report(.finishing, 0.98, "Restarting the pager…")
        _ = try? send(ESPSerialProtocol.flashEndRequest(reboot: false),
                      command: .flashEnd, label: "finishing", timeout: 3)
    }

    private func verify(_ image: Data, at offset: UInt32) throws {
        report(.verifying, 0.92, "Verifying…")
        let response = try send(ESPSerialProtocol.flashMD5Request(address: offset,
                                                                 size: UInt32(image.count)),
                                command: .spiFlashMD5, label: "verification", timeout: 30)

        let reported = String(decoding: response.body, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let expected = Insecure.MD5.hash(data: image).map { String(format: "%02x", $0) }.joined()

        guard reported == expected else {
            throw FlashError.verificationMismatch(expected: expected, actual: reported)
        }
        report(.verifying, 0.96, "Verified.")
    }

    public func restartIntoFirmware() throws {
        try port.setControlLines(dtr: false, rts: true)
        Thread.sleep(forTimeInterval: 0.1)
        try port.setControlLines(dtr: false, rts: false)
        if currentBaudRate != Self.consoleBaudRate {
            try port.setBaudRate(Self.consoleBaudRate)
            currentBaudRate = Self.consoleBaudRate
        }
        readBuffer.removeAll()
        port.flush()
        report(.finishing, 1.0, "Done.")
    }

    private func readRegister(_ address: UInt32) throws -> UInt32 {
        let response = try send(ESPSerialProtocol.readRegisterRequest(address: address),
                                command: .readRegister, label: "identifying the board", timeout: 2)
        return response.value
    }

    private func send(_ request: Data, command: ESPSerialProtocol.Command,
                      label: String, timeout: TimeInterval) throws -> ESPSerialProtocol.Response {
        try port.write(request)
        let response = try awaitResponse(to: command, timeout: timeout)
        guard response.isSuccess else {
            throw FlashError.commandFailed(command: label, errorCode: response.errorCode)
        }
        return response
    }

    private func awaitResponse(to command: ESPSerialProtocol.Command,
                               timeout: TimeInterval) throws -> ESPSerialProtocol.Response {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            while let frame = ESPSerialProtocol.nextFrame(in: readBuffer) {
                readBuffer.removeFirst(frame.consumed)
                if let response = ESPSerialProtocol.parseResponse(frame.payload),
                   response.command == command.rawValue {
                    return response
                }
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            let chunk = try port.read(timeout: min(remaining, 0.2))
            if chunk.isEmpty { continue }
            readBuffer.append(chunk)
        }
        throw FlashError.noResponse(command: command == .sync ? "sync" : String(describing: command))
    }

    private func drain(for interval: TimeInterval) {
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline {
            guard let chunk = try? port.read(timeout: 0.02), !chunk.isEmpty else { continue }
            _ = chunk
        }
        readBuffer.removeAll()
    }

    private func report(_ phase: Progress.Phase, _ fraction: Double, _ message: String) {
        progressHandler(Progress(phase: phase, fraction: min(max(fraction, 0), 1), message: message))
    }
}
