// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
import CommonCrypto

final class FirmwareImageTests: XCTestCase {

    private func mergedImage(size: Int = 0x11000) -> Data {
        var data = Data(repeating: 0xFF, count: 0x1000)
        data.append(0xE9)
        data.append(Data(repeating: 0x00, count: 0x8000 - data.count))
        data.append(contentsOf: [0xAA, 0x50])
        data.append(Data(repeating: 0x00, count: size - data.count))
        return data
    }

    private func appImageOnly(size: Int = 0x11000) -> Data {
        var data = Data([0xE9, 0x05])
        data.append(Data(repeating: 0x42, count: size - data.count))
        return data
    }

    func testAcceptsAMergedImage() throws {
        let image = try FirmwareImage(validating: mergedImage())
        XCTAssertEqual(image.byteCount, 0x11000)
        XCTAssertEqual(image.md5.count, 32)
        XCTAssertEqual(image.displayName, "Bundled firmware")
    }

    func testRejectsABareAppImage() {
        XCTAssertThrowsError(try FirmwareImage(validating: appImageOnly())) { error in
            XCTAssertEqual(error as? FirmwareImage.ValidationError, .looksLikeAppImage)
            let described = (error as? FirmwareImage.ValidationError)?.errorDescription ?? ""
            XCTAssertTrue(described.contains("13years-pager-merged.bin"))
        }
    }

    func testRejectsAnAppImageEvenWhenItIsSmall() {
        XCTAssertEqual(try? errorFor(Data([0xE9, 0x01, 0x02])), .looksLikeAppImage)
    }

    func testRejectsEmptyData() {
        XCTAssertEqual(try? errorFor(Data()), .empty)
    }

    func testRejectsSomethingTooSmallToBeAnImage() {
        XCTAssertEqual(try? errorFor(Data(repeating: 0xFF, count: 512)), .tooSmall(bytes: 512))
    }

    func testRejectsAnImageMissingItsBootloader() {
        var data = mergedImage()
        data[0x1000] = 0x00
        XCTAssertEqual(try? errorFor(data), .missingBootloader)
    }

    func testRejectsAnImageMissingItsPartitionTable() {
        var data = mergedImage()
        data[0x8000] = 0x00
        XCTAssertEqual(try? errorFor(data), .missingPartitionTable)
    }

    func testRejectsAnImageLargerThanFlash() {
        let oversize = mergedImage(size: 0x11000)
        XCTAssertThrowsError(try FirmwareImage(validating: oversize, flashSize: 0x10000)) { error in
            XCTAssertEqual(error as? FirmwareImage.ValidationError,
                           .largerThanFlash(bytes: 0x11000, flashBytes: 0x10000))
        }
    }

    func testMD5MatchesFoundation() throws {
        let data = mergedImage()
        let image = try FirmwareImage(validating: data)
        XCTAssertEqual(image.md5, image.md5.lowercased())
        XCTAssertEqual(image.md5, Self.referenceMD5(of: data))
    }

    func testSourceURLDrivesDisplayName() throws {
        let url = URL(fileURLWithPath: "/tmp/13years-pager-merged.bin")
        let image = try FirmwareImage(validating: mergedImage(), sourceURL: url)
        XCTAssertEqual(image.displayName, "13years-pager-merged.bin")
    }

    private var bundledFirmware: FirmwareImage? {
        FirmwareImage.bundled(in: Bundle(for: Self.self))
    }

    func testTheShippedFirmwareIsPresentAndValid() throws {
        let firmware = try XCTUnwrap(bundledFirmware,
            "The pager firmware is missing from the bundle. Rebuild it with "
          + "Hardware/esp32/tools/build-firmware.py --out "
          + "Sources/ProducerMac/Resources/13years-pager-merged.bin")
        XCTAssertGreaterThan(firmware.byteCount, 900_000)
        XCTAssertLessThanOrEqual(firmware.byteCount, 4 * 1024 * 1024)
        XCTAssertEqual(firmware.md5.count, 32)
    }

    func testTheShippedFirmwareIsAMergedImageNotABareApp() throws {
        let firmware = try XCTUnwrap(bundledFirmware)
        XCTAssertNotEqual(firmware.data.first, 0xE9, "app image magic at offset 0")
        XCTAssertEqual(firmware.data[0x1000], 0xE9, "no bootloader at 0x1000")
        XCTAssertEqual([UInt8](firmware.data[0x8000..<0x8002]), [0xAA, 0x50],
                       "no partition table at 0x8000")
    }

    func testTheShippedFirmwaresAppPartitionStillFits() throws {
        let firmware = try XCTUnwrap(bundledFirmware)
        let appBytes = firmware.byteCount - 0x10000
        XCTAssertLessThanOrEqual(appBytes, 1280 * 1024,
                                 "app image no longer fits app0 — \(appBytes) bytes")
    }

    private func errorFor(_ data: Data) throws -> FirmwareImage.ValidationError {
        do {
            _ = try FirmwareImage(validating: data)
            XCTFail("expected validation to fail")
            throw FirmwareImage.ValidationError.empty
        } catch let error as FirmwareImage.ValidationError {
            return error
        }
    }

    private static func referenceMD5(of data: Data) -> String {
        var context = CC_MD5_CTX()
        CC_MD5_Init(&context)
        data.withUnsafeBytes { _ = CC_MD5_Update(&context, $0.baseAddress, CC_LONG($0.count)) }
        var digest = [UInt8](repeating: 0, count: 16)
        CC_MD5_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
