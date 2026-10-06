// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

final class ESPSerialProtocolTests: XCTestCase {

    func testEncodeWrapsInDelimiters() {
        let framed = ESPSerialProtocol.slipEncode(Data([0x01, 0x02]))
        XCTAssertEqual([UInt8](framed), [0xC0, 0x01, 0x02, 0xC0])
    }

    func testEncodeEscapesDelimiterAndEscapeBytes() {
        let framed = ESPSerialProtocol.slipEncode(Data([0xC0, 0xDB]))
        XCTAssertEqual([UInt8](framed), [0xC0, 0xDB, 0xDC, 0xDB, 0xDD, 0xC0])
    }

    func testDecodeReversesEncode() {
        let original = Data((0...255).map { UInt8($0) })
        let framed = ESPSerialProtocol.slipEncode(original)
        let inner = framed.dropFirst().dropLast()
        XCTAssertEqual(ESPSerialProtocol.slipDecode(Data(inner)), original)
    }

    func testDecodeTreatsUndefinedEscapeAsLiteral() {
        XCTAssertEqual([UInt8](ESPSerialProtocol.slipDecode(Data([0xDB, 0x41]))), [0x41])
    }

    func testDecodeSurvivesTruncatedEscape() {
        XCTAssertEqual([UInt8](ESPSerialProtocol.slipDecode(Data([0x41, 0xDB]))), [0x41])
    }

    func testNextFrameReturnsNilUntilFrameIsComplete() {
        XCTAssertNil(ESPSerialProtocol.nextFrame(in: Data()))
        XCTAssertNil(ESPSerialProtocol.nextFrame(in: Data([0xC0, 0x01])))
    }

    func testNextFrameExtractsAndReportsConsumedBytes() throws {
        let buffer = Data([0xC0, 0x01, 0x02, 0xC0, 0xFF])
        let frame = try XCTUnwrap(ESPSerialProtocol.nextFrame(in: buffer))
        XCTAssertEqual([UInt8](frame.payload), [0x01, 0x02])
        XCTAssertEqual(frame.consumed, 4)
    }

    func testNextFrameSkipsLeadingNoise() throws {
        var buffer = Data("ets Jun  8 2016 00:22:57\r\n".utf8)
        buffer.append(Data([0xC0, 0x07, 0xC0]))
        let frame = try XCTUnwrap(ESPSerialProtocol.nextFrame(in: buffer))
        XCTAssertEqual([UInt8](frame.payload), [0x07])
    }

    func testNextFrameSkipsRunsOfDelimiters() throws {
        let buffer = Data([0xC0, 0xC0, 0xC0, 0x09, 0xC0])
        let frame = try XCTUnwrap(ESPSerialProtocol.nextFrame(in: buffer))
        XCTAssertEqual([UInt8](frame.payload), [0x09])
    }

    func testTwoFramesAreReadInSequence() throws {
        var buffer = Data([0xC0, 0x0A, 0xC0, 0xC0, 0x0B, 0xC0])
        let first = try XCTUnwrap(ESPSerialProtocol.nextFrame(in: buffer))
        XCTAssertEqual([UInt8](first.payload), [0x0A])
        buffer.removeFirst(first.consumed)
        let second = try XCTUnwrap(ESPSerialProtocol.nextFrame(in: buffer))
        XCTAssertEqual([UInt8](second.payload), [0x0B])
    }

    func testChecksumIsSeededXor() {
        XCTAssertEqual(ESPSerialProtocol.checksum(Data()), 0xEF)
        XCTAssertEqual(ESPSerialProtocol.checksum(Data([0xEF])), 0x00)
        XCTAssertEqual(ESPSerialProtocol.checksum(Data([0x01, 0x02])), 0xEF ^ 0x01 ^ 0x02)
    }

    func testChecksumIgnoresOrdering() {
        XCTAssertEqual(ESPSerialProtocol.checksum(Data([0x01, 0x02, 0x03])),
                       ESPSerialProtocol.checksum(Data([0x03, 0x02, 0x01])))
    }

    private func unframe(_ framed: Data) -> [UInt8] {
        [UInt8](ESPSerialProtocol.slipDecode(Data(framed.dropFirst().dropLast())))
    }

    func testRequestHeaderLayout() {
        let packet = unframe(ESPSerialProtocol.request(.readRegister, data: Data([0xAA, 0xBB])))
        XCTAssertEqual(packet[0], 0x00)
        XCTAssertEqual(packet[1], 0x0A)
        XCTAssertEqual(packet[2], 0x02)
        XCTAssertEqual(packet[3], 0x00)
        XCTAssertEqual(Array(packet[4..<8]), [0, 0, 0, 0])
        XCTAssertEqual(Array(packet[8...]), [0xAA, 0xBB])
    }

    func testSyncRequestPayloadIsTheFixedPattern() {
        let packet = unframe(ESPSerialProtocol.syncRequest())
        XCTAssertEqual(packet[1], 0x08)
        let payload = Array(packet[8...])
        XCTAssertEqual(payload.count, 36)
        XCTAssertEqual(Array(payload[0..<4]), [0x07, 0x07, 0x12, 0x20])
        XCTAssertTrue(payload[4...].allSatisfy { $0 == 0x55 })
    }

    func testReadRegisterRequestEncodesAddressLittleEndian() {
        let packet = unframe(ESPSerialProtocol.readRegisterRequest(address: 0x4000_1000))
        XCTAssertEqual(Array(packet[8...]), [0x00, 0x10, 0x00, 0x40])
    }

    func testFlashBeginEncodesFourParameters() {
        let packet = unframe(ESPSerialProtocol.flashBeginRequest(size: 0x100, blockCount: 1,
                                                                blockSize: 0x400, offset: 0))
        let payload = Array(packet[8...])
        XCTAssertEqual(payload.count, 16)
        XCTAssertEqual(Array(payload[0..<4]), [0x00, 0x01, 0x00, 0x00])
        XCTAssertEqual(Array(payload[4..<8]), [0x01, 0x00, 0x00, 0x00])
        XCTAssertEqual(Array(payload[8..<12]), [0x00, 0x04, 0x00, 0x00])
    }

    func testFlashDataChecksumCoversPayloadNotHeader() {
        let payload = Data([0x11, 0x22, 0x33])
        let packet = unframe(ESPSerialProtocol.flashDataRequest(payload: payload, sequence: 7))
        let checksum = UInt32(packet[4]) | UInt32(packet[5]) << 8
                     | UInt32(packet[6]) << 16 | UInt32(packet[7]) << 24
        XCTAssertEqual(checksum, ESPSerialProtocol.checksum(payload))

        let body = Array(packet[8...])
        XCTAssertEqual(Array(body[0..<4]), [0x03, 0x00, 0x00, 0x00])
        XCTAssertEqual(Array(body[4..<8]), [0x07, 0x00, 0x00, 0x00])
        XCTAssertEqual(Array(body[16...]), [0x11, 0x22, 0x33])
    }

    func testFlashEndInvertsTheRebootFlag() {
        XCTAssertEqual(unframe(ESPSerialProtocol.flashEndRequest(reboot: false))[8], 1)
        XCTAssertEqual(unframe(ESPSerialProtocol.flashEndRequest(reboot: true))[8], 0)
    }

    func testChangeBaudRateSendsBothRates() {
        let payload = Array(unframe(ESPSerialProtocol.changeBaudRateRequest(to: 460_800, from: 115_200))[8...])
        XCTAssertEqual(payload.count, 8)
        XCTAssertEqual(UInt32(payload[0]) | UInt32(payload[1]) << 8
                     | UInt32(payload[2]) << 16 | UInt32(payload[3]) << 24, 460_800)
        XCTAssertEqual(UInt32(payload[4]) | UInt32(payload[5]) << 8
                     | UInt32(payload[6]) << 16 | UInt32(payload[7]) << 24, 115_200)
    }

    private func responsePacket(command: UInt8, value: UInt32 = 0,
                                body: [UInt8] = [], status: UInt8 = 0,
                                error: UInt8 = 0) -> Data {
        var packet: [UInt8] = [0x01, command]
        let payload = body + [status, error, 0x00, 0x00]
        packet += [UInt8(payload.count & 0xFF), UInt8((payload.count >> 8) & 0xFF)]
        packet += [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
                   UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
        packet += payload
        return Data(packet)
    }

    func testParseSuccessfulRegisterRead() throws {
        let response = try XCTUnwrap(
            ESPSerialProtocol.parseResponse(responsePacket(command: 0x0A, value: 0x00F0_1D83)))
        XCTAssertEqual(response.command, 0x0A)
        XCTAssertEqual(response.value, ESPSerialProtocol.esp32Magic)
        XCTAssertTrue(response.isSuccess)
    }

    func testParseFailureCarriesErrorCode() throws {
        let response = try XCTUnwrap(
            ESPSerialProtocol.parseResponse(responsePacket(command: 0x03, status: 1, error: 0x07)))
        XCTAssertFalse(response.isSuccess)
        XCTAssertEqual(response.errorCode, 0x07)
        XCTAssertTrue(ESPSerialProtocol.describeError(0x07).contains("hecksum"))
    }

    func testParseSeparatesBodyFromStatusBytes() throws {
        let digest = [UInt8]("d41d8cd98f00b204e9800998ecf8427e".utf8)
        let response = try XCTUnwrap(
            ESPSerialProtocol.parseResponse(responsePacket(command: 0x13, body: digest)))
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self),
                       "d41d8cd98f00b204e9800998ecf8427e")
    }

    func testParseRejectsRequestDirection() {
        var packet = [UInt8](responsePacket(command: 0x08))
        packet[0] = 0x00
        XCTAssertNil(ESPSerialProtocol.parseResponse(Data(packet)))
    }

    func testParseRejectsShortPackets() {
        XCTAssertNil(ESPSerialProtocol.parseResponse(Data([0x01, 0x08, 0x00])))
        XCTAssertNil(ESPSerialProtocol.parseResponse(Data([0x01, 0x08, 0x00, 0x00, 0, 0, 0, 0])))
        XCTAssertNil(ESPSerialProtocol.parseResponse(
            Data([0x01, 0x08, 0x03, 0x00, 0, 0, 0, 0, 0x00, 0x00, 0x00])))
    }

    func testParseToleratesADeclaredSizeLongerThanWhatArrived() {
        var packet = [UInt8](responsePacket(command: 0x13, body: [UInt8]("abcd".utf8)))
        packet[2] = 0xFF
        XCTAssertNotNil(ESPSerialProtocol.parseResponse(Data(packet)))
    }

    func testStatusWordIsFourBytesOnTheClassicESP32() {
        XCTAssertEqual(ESPSerialProtocol.statusByteCount, 4)
        let noData = ESPSerialProtocol.parseResponse(
            Data([0x01, 0x08, 0x04, 0x00, 0, 0, 0, 0, 0x00, 0x00, 0x00, 0x00]))
        XCTAssertEqual(noData?.body.count, 0)
        XCTAssertEqual(noData?.isSuccess, true)
    }

    func testFailureIsNotMistakenForSuccess() {
        let rejected = ESPSerialProtocol.parseResponse(
            Data([0x01, 0x02, 0x04, 0x00, 0, 0, 0, 0, 0x01, 0x08, 0x00, 0x00]))
        XCTAssertEqual(rejected?.isSuccess, false)
        XCTAssertEqual(rejected?.errorCode, 0x08)
    }

    func testChipMagicIdentifiesTheSupportedBoard() {
        XCTAssertEqual(ESPSerialProtocol.chipMagic[ESPSerialProtocol.esp32Magic], "ESP32")
    }
}
