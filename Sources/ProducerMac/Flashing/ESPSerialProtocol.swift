// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

enum ESPSerialProtocol {

    enum Command: UInt8 {
        case flashBegin = 0x02
        case flashData = 0x03
        case flashEnd = 0x04
        case sync = 0x08
        case readRegister = 0x0A
        case spiSetParameters = 0x0B
        case spiAttach = 0x0D
        case changeBaudRate = 0x0F
        case spiFlashMD5 = 0x13
    }

    static let chipDetectRegister: UInt32 = 0x4000_1000

    static let chipMagic: [UInt32: String] = [
        0x00F0_1D83: "ESP32",
        0x0000_0F01: "ESP32-S2",
        0x0000_0007: "ESP32-S3",
        0x6921_506F: "ESP32-C3",
        0x1B31_506F: "ESP32-C3",
        0xFFF0_C101: "ESP8266",
    ]

    static let esp32Magic: UInt32 = 0x00F0_1D83

    private static let frameDelimiter: UInt8 = 0xC0
    private static let escapeByte: UInt8 = 0xDB
    private static let escapedDelimiter: UInt8 = 0xDC
    private static let escapedEscape: UInt8 = 0xDD

    static func slipEncode(_ payload: Data) -> Data {
        var out = Data([frameDelimiter])
        out.reserveCapacity(payload.count + 2)
        for byte in payload {
            switch byte {
            case frameDelimiter: out.append(contentsOf: [escapeByte, escapedDelimiter])
            case escapeByte: out.append(contentsOf: [escapeByte, escapedEscape])
            default: out.append(byte)
            }
        }
        out.append(frameDelimiter)
        return out
    }

    static func slipDecode(_ frame: Data) -> Data {
        var out = Data()
        out.reserveCapacity(frame.count)
        var iterator = frame.makeIterator()
        while let byte = iterator.next() {
            guard byte == escapeByte else {
                out.append(byte)
                continue
            }
            guard let next = iterator.next() else { break }
            switch next {
            case escapedDelimiter: out.append(frameDelimiter)
            case escapedEscape: out.append(escapeByte)
            default: out.append(next)
            }
        }
        return out
    }

    static func nextFrame(in buffer: Data) -> (payload: Data, consumed: Int)? {
        guard let start = buffer.firstIndex(of: frameDelimiter) else {
            return nil
        }
        var searchFrom = buffer.index(after: start)
        while searchFrom < buffer.endIndex, buffer[searchFrom] == frameDelimiter {
            searchFrom = buffer.index(after: searchFrom)
        }
        guard searchFrom < buffer.endIndex else { return nil }
        guard let end = buffer[searchFrom...].firstIndex(of: frameDelimiter) else {
            return nil
        }
        let payload = slipDecode(Data(buffer[searchFrom..<end]))
        let consumed = buffer.distance(from: buffer.startIndex, to: end) + 1
        return (payload, consumed)
    }

    static func checksum(_ data: Data) -> UInt32 {
        var state: UInt8 = 0xEF
        for byte in data { state ^= byte }
        return UInt32(state)
    }

    static func request(_ command: Command, data: Data = Data(), checksum: UInt32 = 0) -> Data {
        var packet = Data()
        packet.append(0x00)
        packet.append(command.rawValue)
        packet.append(littleEndian: UInt16(data.count))
        packet.append(littleEndian: checksum)
        packet.append(data)
        return slipEncode(packet)
    }

    static func syncRequest() -> Data {
        var payload = Data([0x07, 0x07, 0x12, 0x20])
        payload.append(Data(repeating: 0x55, count: 32))
        return request(.sync, data: payload)
    }

    static func flashBeginRequest(size: UInt32, blockCount: UInt32,
                                  blockSize: UInt32, offset: UInt32) -> Data {
        var data = Data()
        data.append(littleEndian: size)
        data.append(littleEndian: blockCount)
        data.append(littleEndian: blockSize)
        data.append(littleEndian: offset)
        return request(.flashBegin, data: data)
    }

    static func flashDataRequest(payload: Data, sequence: UInt32) -> Data {
        var data = Data()
        data.append(littleEndian: UInt32(payload.count))
        data.append(littleEndian: sequence)
        data.append(littleEndian: UInt32(0))
        data.append(littleEndian: UInt32(0))
        data.append(payload)
        return request(.flashData, data: data, checksum: checksum(payload))
    }

    static func flashEndRequest(reboot: Bool) -> Data {
        var data = Data()
        data.append(littleEndian: UInt32(reboot ? 0 : 1))
        return request(.flashEnd, data: data)
    }

    static func readRegisterRequest(address: UInt32) -> Data {
        var data = Data()
        data.append(littleEndian: address)
        return request(.readRegister, data: data)
    }

    static func spiAttachRequest() -> Data {
        var data = Data()
        data.append(littleEndian: UInt32(0))
        data.append(littleEndian: UInt32(0))
        return request(.spiAttach, data: data)
    }

    static func spiSetParametersRequest(flashSize: UInt32) -> Data {
        var data = Data()
        data.append(littleEndian: UInt32(0))
        data.append(littleEndian: flashSize)
        data.append(littleEndian: UInt32(64 * 1024))
        data.append(littleEndian: UInt32(4 * 1024))
        data.append(littleEndian: UInt32(256))
        data.append(littleEndian: UInt32(0xFFFF))
        return request(.spiSetParameters, data: data)
    }

    static func changeBaudRateRequest(to newRate: UInt32, from oldRate: UInt32) -> Data {
        var data = Data()
        data.append(littleEndian: newRate)
        data.append(littleEndian: oldRate)
        return request(.changeBaudRate, data: data)
    }

    static func flashMD5Request(address: UInt32, size: UInt32) -> Data {
        var data = Data()
        data.append(littleEndian: address)
        data.append(littleEndian: size)
        data.append(littleEndian: UInt32(0))
        data.append(littleEndian: UInt32(0))
        return request(.spiFlashMD5, data: data)
    }

    struct Response: Equatable {
        let command: UInt8
        let value: UInt32
        let body: Data
        let status: UInt8
        let errorCode: UInt8

        var isSuccess: Bool { status == 0 }
    }

    static func describeError(_ code: UInt8) -> String {
        switch code {
        case 0x05: return "the chip considered the message invalid"
        case 0x06: return "the chip failed to act on the message"
        case 0x07: return "checksum mismatch"
        case 0x08: return "flash write failed"
        case 0x09: return "flash read failed"
        case 0x0A: return "flash read length error"
        case 0x0B: return "decompression failed"
        default: return String(format: "error 0x%02x", code)
        }
    }

    static let statusByteCount = 4

    static func parseResponse(_ payload: Data) -> Response? {
        guard payload.count >= 8 else { return nil }
        let bytes = [UInt8](payload)
        guard bytes[0] == 0x01 else { return nil }

        let size = Int(UInt16(bytes[2]) | UInt16(bytes[3]) << 8)
        let value = UInt32(bytes[4]) | UInt32(bytes[5]) << 8
                  | UInt32(bytes[6]) << 16 | UInt32(bytes[7]) << 24

        let available = bytes.count - 8
        let dataLength = min(size, available)
        guard dataLength >= statusByteCount else { return nil }

        let data = Array(bytes[8..<(8 + dataLength)])
        let statusStart = data.count - statusByteCount
        let status = data[statusStart]
        let errorCode = data[statusStart + 1]
        let body = Data(data[0..<statusStart])

        return Response(command: bytes[1], value: value, body: body,
                        status: status, errorCode: errorCode)
    }
}

private extension Data {
    mutating func append(littleEndian value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func append(littleEndian value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
