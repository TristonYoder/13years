// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
import CryptoKit

public enum WebSocketOpcode: UInt8, Sendable {
    case continuation = 0x0
    case text = 0x1
    case binary = 0x2
    case close = 0x8
    case ping = 0x9
    case pong = 0xA

    public var isControl: Bool {
        switch self {
        case .close, .ping, .pong:
            return true
        case .continuation, .text, .binary:
            return false
        }
    }
}

public struct WebSocketFrame: Sendable, Equatable {
    public var isFinal: Bool

    public var opcode: WebSocketOpcode

    public var payload: Data

    public init(isFinal: Bool = true, opcode: WebSocketOpcode, payload: Data = Data()) {
        self.isFinal = isFinal
        self.opcode = opcode
        self.payload = payload
    }
}

public enum WebSocketDecodeResult: Sendable {
    case incomplete

    case frame(WebSocketFrame, consumed: Int)

    case failure(String)
}

public enum WebSocketCodec {
    public static let maxPayloadBytes = 1 * 1024 * 1024

    public static func decode(_ buffer: [UInt8]) -> WebSocketDecodeResult {
        guard buffer.count >= 2 else {
            return .incomplete
        }

        let byte0 = buffer[0]
        let byte1 = buffer[1]

        let isFinal = (byte0 & 0x80) != 0
        let rsv = (byte0 & 0x70)
        let opcodeRaw = byte0 & 0x0F

        guard rsv == 0 else {
            return .failure("Reserved bits set in frame header")
        }

        guard let opcode = WebSocketOpcode(rawValue: opcodeRaw) else {
            return .failure("Invalid opcode: \(opcodeRaw)")
        }

        let isMasked = (byte1 & 0x80) != 0
        let payloadLen7 = Int(byte1 & 0x7F)

        var headerSize = 2
        var payloadLength: Int

        switch payloadLen7 {
        case 126:
            guard buffer.count >= 4 else {
                return .incomplete
            }
            payloadLength = Int(UInt16(buffer[2]) << 8 | UInt16(buffer[3]))
            headerSize = 4
        case 127:
            guard buffer.count >= 10 else {
                return .incomplete
            }
            var len64: UInt64 = 0
            for i in 0..<8 {
                len64 = (len64 << 8) | UInt64(buffer[2 + i])
            }
            guard len64 <= UInt64(Int.max) else {
                return .failure("Payload length exceeds Int.max")
            }
            payloadLength = Int(len64)
            headerSize = 10
        default:
            payloadLength = payloadLen7
        }

        guard payloadLength <= maxPayloadBytes else {
            return .failure("Payload length \(payloadLength) exceeds maximum \(maxPayloadBytes)")
        }

        if opcode.isControl {
            guard isFinal else {
                return .failure("Control frame is not final")
            }
            guard payloadLength <= 125 else {
                return .failure("Control frame payload exceeds 125 bytes")
            }
        }

        let maskKeySize = isMasked ? 4 : 0
        let totalFrameSize = headerSize + maskKeySize + payloadLength

        guard buffer.count >= totalFrameSize else {
            return .incomplete
        }

        var payload = Data()
        if payloadLength > 0 {
            let payloadStart = headerSize + maskKeySize
            if isMasked {
                let maskKey = [UInt8](buffer[headerSize..<(headerSize + 4)])
                for i in 0..<payloadLength {
                    payload.append(buffer[payloadStart + i] ^ maskKey[i % 4])
                }
            } else {
                payload = Data(buffer[payloadStart..<payloadStart + payloadLength])
            }
        }

        let frame = WebSocketFrame(isFinal: isFinal, opcode: opcode, payload: payload)
        return .frame(frame, consumed: totalFrameSize)
    }

    public static func encode(_ frame: WebSocketFrame, mask: Bool = false) -> Data {
        var result = Data()

        let byte0: UInt8 = (frame.isFinal ? 0x80 : 0x00) | frame.opcode.rawValue
        result.append(byte0)

        let payloadLen = frame.payload.count
        let payloadLenByte: UInt8

        if payloadLen <= 125 {
            payloadLenByte = UInt8(payloadLen)
        } else if payloadLen <= UInt16.max {
            payloadLenByte = 126
        } else {
            payloadLenByte = 127
        }

        let byte1: UInt8 = (mask ? 0x80 : 0x00) | payloadLenByte
        result.append(byte1)

        if payloadLen > 125 && payloadLen <= UInt16.max {
            let len16 = UInt16(payloadLen)
            result.append(UInt8((len16 >> 8) & 0xFF))
            result.append(UInt8(len16 & 0xFF))
        } else if payloadLen > UInt16.max {
            let len64 = UInt64(payloadLen)
            for i in (0..<8).reversed() {
                result.append(UInt8((len64 >> (i * 8)) & 0xFF))
            }
        }

        if mask {
            let maskKey = (0..<4).map { _ in UInt8.random(in: 0...255) }
            result.append(contentsOf: maskKey)
            for (i, byte) in frame.payload.enumerated() {
                result.append(byte ^ maskKey[i % 4])
            }
        } else {
            result.append(frame.payload)
        }

        return result
    }

    public static func acceptKey(forClientKey key: String) -> String {
        let magicGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let concatenated = key + magicGUID
        guard let data = concatenated.data(using: .utf8) else {
            return ""
        }

        let digest = Insecure.SHA1.hash(data: data)
        let digestBytes = [UInt8](digest)
        return Data(digestBytes).base64EncodedString()
    }

    public static func text(_ string: String) -> WebSocketFrame {
        let payload = string.data(using: .utf8) ?? Data()
        return WebSocketFrame(isFinal: true, opcode: .text, payload: payload)
    }

    public static func close(code: UInt16, reason: String = "") -> WebSocketFrame {
        var payload = Data()
        payload.append(UInt8((code >> 8) & 0xFF))
        payload.append(UInt8(code & 0xFF))
        if let reasonData = reason.data(using: .utf8) {
            payload.append(reasonData)
        }
        return WebSocketFrame(isFinal: true, opcode: .close, payload: payload)
    }
}

public final class WebSocketMessageAssembler {
    private let maxMessageBytes: Int
    private var fragmentBuffer: WebSocketFrame?

    public init(maxMessageBytes: Int = 1 * 1024 * 1024) {
        self.maxMessageBytes = maxMessageBytes
    }

    public enum Output: Sendable {
        case none

        case message(WebSocketFrame)

        case control(WebSocketFrame)

        case failure(String)
    }

    public func accept(_ frame: WebSocketFrame) -> Output {
        if frame.opcode.isControl {
            return .control(frame)
        }

        switch frame.opcode {
        case .text, .binary:
            if fragmentBuffer != nil {
                return .failure("Received new data frame while message fragments are pending")
            }

            if frame.isFinal {
                return .message(frame)
            } else {
                fragmentBuffer = frame
                return .none
            }

        case .continuation:
            guard var buffer = fragmentBuffer else {
                return .failure("Received continuation frame without an active message sequence")
            }

            buffer.payload.append(frame.payload)
            guard buffer.payload.count <= maxMessageBytes else {
                return .failure("Reassembled message exceeds maximum size \(maxMessageBytes)")
            }

            if frame.isFinal {
                var result = buffer
                result.isFinal = true
                fragmentBuffer = nil
                return .message(result)
            } else {
                fragmentBuffer = buffer
                return .none
            }

        case .close, .ping, .pong:
            return .failure("Unexpected control frame opcode in data path")
        }
    }
}
