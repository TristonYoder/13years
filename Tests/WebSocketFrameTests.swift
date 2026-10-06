// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

final class WebSocketFrameTests: XCTestCase {

    func testRFC6455HandshakeAcceptKey() {
        let result = WebSocketCodec.acceptKey(forClientKey: "dGhlIHNhbXBsZSBub25jZQ==")
        XCTAssertEqual(result, "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    func testShortTextFrameRoundTrip() {
        let original = WebSocketFrame(isFinal: true, opcode: .text, payload: "Hello".data(using: .utf8) ?? Data())
        let encoded = WebSocketCodec.encode(original, mask: false)

        let buffer = [UInt8](encoded)
        let result = WebSocketCodec.decode(buffer)

        switch result {
        case .frame(let frame, let consumed):
            XCTAssertEqual(frame.opcode, .text)
            XCTAssertTrue(frame.isFinal)
            XCTAssertEqual(frame.payload, original.payload)
            XCTAssertEqual(consumed, encoded.count)
        default:
            XCTFail("Expected .frame but got \(result)")
        }
    }

    func testBinaryFrame200BytesRoundTrip() {
        let payload = Data(repeating: 0xAA, count: 200)
        let original = WebSocketFrame(isFinal: true, opcode: .binary, payload: payload)
        let encoded = WebSocketCodec.encode(original, mask: false)

        let buffer = [UInt8](encoded)
        let result = WebSocketCodec.decode(buffer)

        switch result {
        case .frame(let frame, let consumed):
            XCTAssertEqual(frame.opcode, .binary)
            XCTAssertTrue(frame.isFinal)
            XCTAssertEqual(frame.payload, payload)
            XCTAssertEqual(consumed, encoded.count)
        default:
            XCTFail("Expected .frame but got \(result)")
        }
    }

    func testBinaryFrame70000BytesRoundTrip() {
        let payload = Data(repeating: 0xBB, count: 70000)
        let original = WebSocketFrame(isFinal: true, opcode: .binary, payload: payload)
        let encoded = WebSocketCodec.encode(original, mask: false)

        let buffer = [UInt8](encoded)
        let result = WebSocketCodec.decode(buffer)

        switch result {
        case .frame(let frame, let consumed):
            XCTAssertEqual(frame.opcode, .binary)
            XCTAssertTrue(frame.isFinal)
            XCTAssertEqual(frame.payload, payload)
            XCTAssertEqual(consumed, encoded.count)
        default:
            XCTFail("Expected .frame but got \(result)")
        }
    }

    func testMaskedClientFrameDecodesCorrectly() {
        let original = WebSocketFrame(isFinal: true, opcode: .text, payload: "Test".data(using: .utf8) ?? Data())
        let encoded = WebSocketCodec.encode(original, mask: true)

        let buffer = [UInt8](encoded)
        let result = WebSocketCodec.decode(buffer)

        switch result {
        case .frame(let frame, _):
            XCTAssertEqual(frame.payload, original.payload)
            XCTAssertEqual(frame.opcode, .text)
        default:
            XCTFail("Expected .frame but got \(result)")
        }
    }

    func testSingleByteBufferReturnsIncomplete() {
        let buffer: [UInt8] = [0x81]
        let result = WebSocketCodec.decode(buffer)

        switch result {
        case .incomplete:
            break
        default:
            XCTFail("Expected .incomplete but got \(result)")
        }
    }

    func testFullHeaderWithPartialPayloadReturnsIncomplete() {
        let frame = WebSocketFrame(isFinal: true, opcode: .text, payload: "Hello".data(using: .utf8) ?? Data())
        let encoded = WebSocketCodec.encode(frame, mask: false)

        let buffer = Array(encoded.prefix(3))
        let result = WebSocketCodec.decode(buffer)

        switch result {
        case .incomplete:
            break
        default:
            XCTFail("Expected .incomplete but got \(result)")
        }
    }

    func testPayloadExceedingMaxBytesReturnsFailure() {
        var buffer: [UInt8] = [
            0x82,
            0x7F,
        ]
        let oversized = UInt64(WebSocketCodec.maxPayloadBytes) + 1
        for i in (0..<8).reversed() {
            buffer.append(UInt8((oversized >> (i * 8)) & 0xFF))
        }

        let result = WebSocketCodec.decode(buffer)

        switch result {
        case .failure:
            break
        default:
            XCTFail("Expected .failure but got \(result)")
        }
    }

    func testReservedBitSetReturnsFailure() {
        let buffer: [UInt8] = [
            0xC2,
            0x00,
        ]

        let result = WebSocketCodec.decode(buffer)

        switch result {
        case .failure:
            break
        default:
            XCTFail("Expected .failure but got \(result)")
        }
    }

    func testAssemblerJoinsFragmentedTextMessage() {
        let assembler = WebSocketMessageAssembler()

        let firstFrame = WebSocketFrame(
            isFinal: false,
            opcode: .text,
            payload: "Hel".data(using: .utf8) ?? Data()
        )
        let firstResult = assembler.accept(firstFrame)

        switch firstResult {
        case .none:
            break
        default:
            XCTFail("Expected .none for first fragment but got \(firstResult)")
        }

        let secondFrame = WebSocketFrame(
            isFinal: true,
            opcode: .continuation,
            payload: "lo".data(using: .utf8) ?? Data()
        )
        let secondResult = assembler.accept(secondFrame)

        switch secondResult {
        case .message(let frame):
            XCTAssertEqual(frame.opcode, .text)
            XCTAssertEqual(frame.payload, "Hello".data(using: .utf8) ?? Data())
            XCTAssertTrue(frame.isFinal)
        default:
            XCTFail("Expected .message but got \(secondResult)")
        }
    }

    func testAssemblerPassesPingThroughAsControl() {
        let assembler = WebSocketMessageAssembler()

        let pingFrame = WebSocketFrame(isFinal: true, opcode: .ping, payload: "ping".data(using: .utf8) ?? Data())
        let result = assembler.accept(pingFrame)

        switch result {
        case .control(let frame):
            XCTAssertEqual(frame.opcode, .ping)
        default:
            XCTFail("Expected .control but got \(result)")
        }
    }

    func testContinuationWithoutActiveSequenceReturnsFailure() {
        let assembler = WebSocketMessageAssembler()

        let orphanedContinuation = WebSocketFrame(
            isFinal: true,
            opcode: .continuation,
            payload: "orphan".data(using: .utf8) ?? Data()
        )
        let result = assembler.accept(orphanedContinuation)

        switch result {
        case .failure:
            break
        default:
            XCTFail("Expected .failure but got \(result)")
        }
    }
}
