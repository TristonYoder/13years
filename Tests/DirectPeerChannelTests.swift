// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
import Network

final class DirectPeerChannelTests: XCTestCase {

    func testFrameRoundTrip() {
        let payload = "hello direct peer".data(using: .utf8)!
        guard let framed = DirectPeerChannel.frame(payload) else {
            XCTFail("Failed to frame payload")
            return
        }

        XCTAssertEqual(framed.count, 4 + payload.count)

        let lengthPrefix = framed.prefix(4)
        let decodedLength = DirectPeerChannel.decodeLength(Data(lengthPrefix))
        XCTAssertEqual(decodedLength, UInt32(payload.count))

        let decodedPayload = framed.suffix(from: 4)
        XCTAssertEqual(Data(decodedPayload), payload)
    }

    func testFrameEmptyPayload() {
        let payload = Data()
        guard let framed = DirectPeerChannel.frame(payload) else {
            XCTFail("Failed to frame empty payload")
            return
        }
        XCTAssertEqual(framed.count, 4)
        XCTAssertEqual(DirectPeerChannel.decodeLength(framed), 0)
    }

    func testDecodeLengthBigEndianByteOrder() {
        let bytes: [UInt8] = [0x00, 0x01, 0x02, 0x03]
        let length = DirectPeerChannel.decodeLength(Data(bytes))
        XCTAssertEqual(length, 0x00_01_02_03)
    }

    func testFrameRoundTripWithCuePacketBytes() {
        let roles = RoleCue.defaultRoles
        let packet = CuePacket(type: .cueUpdate, senderId: "unit_test", roleCues: roles)
        guard let packetData = packet.encode(), let framed = DirectPeerChannel.frame(packetData) else {
            XCTFail("Failed to encode/frame CuePacket")
            return
        }

        let decodedLength = DirectPeerChannel.decodeLength(framed.prefix(4))
        XCTAssertEqual(Int(decodedLength), packetData.count)

        let decodedPacketData = Data(framed.suffix(from: 4))
        guard let decodedPacket = CuePacket.decode(from: decodedPacketData) else {
            XCTFail("Failed to decode CuePacket from framed payload")
            return
        }
        XCTAssertEqual(decodedPacket.senderId, "unit_test")
        XCTAssertEqual(decodedPacket.roleCues?.count, roles.count)
    }

    func testPeerHelloEncodeDecodeRoundTrip() {
        let hello = PeerHello(addresses: ["192.168.1.42", "10.0.0.5"], port: 54321, connectToken: "abc123==")
        guard let data = hello.encode() else {
            XCTFail("Failed to encode PeerHello")
            return
        }
        guard let decoded = PeerHello.decode(from: data) else {
            XCTFail("Failed to decode PeerHello")
            return
        }
        XCTAssertEqual(decoded.addresses, hello.addresses)
        XCTAssertEqual(decoded.port, hello.port)
        XCTAssertEqual(decoded.connectToken, hello.connectToken)
    }

    func testWrongTokenIsRejectedAndNoPacketDelivered() throws {
        let channel = DirectPeerChannel()
        let receivedPacket = XCTestExpectation(description: "packet received")
        receivedPacket.isInverted = true
        channel.onPacketReceived = { _ in receivedPacket.fulfill() }
        channel.start()
        defer { channel.stop() }

        guard let port = try waitForListenerPort(of: channel) else {
            throw XCTSkip("Could not bind a loopback listener in this environment")
        }

        let attacker = try openLoopbackConnection(port: port)
        defer { attacker.cancel() }

        guard let wrongTokenData = "not-the-real-token".data(using: .utf8),
              let framed = DirectPeerChannel.frame(wrongTokenData) else {
            XCTFail("Failed to build wrong-token frame")
            return
        }
        try send(framed, on: attacker)

        if let packetData = CuePacket(type: .cueUpdate, senderId: "attacker").encode(),
           let packetFrame = DirectPeerChannel.frame(packetData) {
            try? send(packetFrame, on: attacker)
        }

        wait(for: [receivedPacket], timeout: 2.0)
    }

    func testCorrectTokenIsAcceptedAndPacketIsDelivered() throws {
        let channel = DirectPeerChannel()
        let receivedPacket = XCTestExpectation(description: "packet received")
        var receivedSenderId: String?
        channel.onPacketReceived = { packet in
            receivedSenderId = packet.senderId
            receivedPacket.fulfill()
        }
        channel.start()
        defer { channel.stop() }

        guard let hello = try waitForHello(from: channel) else {
            throw XCTSkip("Could not bind a loopback listener in this environment")
        }

        let peer = try openLoopbackConnection(port: hello.port)
        defer { peer.cancel() }

        guard let tokenData = hello.connectToken.data(using: .utf8),
              let tokenFrame = DirectPeerChannel.frame(tokenData) else {
            XCTFail("Failed to build token frame")
            return
        }
        try send(tokenFrame, on: peer)

        guard let packetData = CuePacket(type: .cueUpdate, senderId: "peer_under_test").encode(),
              let packetFrame = DirectPeerChannel.frame(packetData) else {
            XCTFail("Failed to build CuePacket frame")
            return
        }
        try send(packetFrame, on: peer)

        wait(for: [receivedPacket], timeout: 3.0)
        XCTAssertEqual(receivedSenderId, "peer_under_test")
    }

    private func waitForHello(from channel: DirectPeerChannel, timeout: TimeInterval = 3.0) throws -> PeerHello? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let payload = channel.buildHelloPayload(), let hello = PeerHello.decode(from: payload) {
                return hello
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }

    private func waitForListenerPort(of channel: DirectPeerChannel, timeout: TimeInterval = 3.0) throws -> UInt16? {
        try waitForHello(from: channel, timeout: timeout)?.port
    }

    private func openLoopbackConnection(port: UInt16) throws -> NWConnection {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let ready = XCTestExpectation(description: "connection ready")
        connection.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        connection.start(queue: .global())
        wait(for: [ready], timeout: 3.0)
        return connection
    }

    private func send(_ data: Data, on connection: NWConnection) throws {
        let sent = XCTestExpectation(description: "data sent")
        connection.send(content: data, completion: .contentProcessed { _ in sent.fulfill() })
        wait(for: [sent], timeout: 2.0)
    }
}
