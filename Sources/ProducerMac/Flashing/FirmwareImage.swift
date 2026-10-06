// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
import CryptoKit

public struct FirmwareImage: Sendable {
    public let data: Data
    public let sourceURL: URL?

    public let md5: String

    public var byteCount: Int { data.count }

    public var displayName: String {
        sourceURL?.lastPathComponent ?? "Bundled firmware"
    }

    private static let bootloaderOffset = 0x1000
    private static let partitionTableOffset = 0x8000
    private static let imageMagic: UInt8 = 0xE9
    private static let partitionMagic: [UInt8] = [0xAA, 0x50]
    private static let minimumPlausibleSize = 0x9000

    public enum ValidationError: LocalizedError, Equatable {
        case empty
        case tooSmall(bytes: Int)
        case looksLikeAppImage
        case missingBootloader
        case missingPartitionTable
        case largerThanFlash(bytes: Int, flashBytes: Int)

        public var errorDescription: String? {
            switch self {
            case .empty:
                return "That file is empty."
            case let .tooSmall(bytes):
                return "That file is only \(bytes) bytes — too small to be a pager firmware image."
            case .looksLikeAppImage:
                return "That looks like firmware.bin, the application image on its own. "
                     + "Flashing it at offset 0 would leave the pager unable to boot. "
                     + "Use the merged image from tools/build-firmware.py (13years-pager-merged.bin)."
            case .missingBootloader:
                return "That file has no bootloader at offset 0x1000, so it isn’t a merged pager image."
            case .missingPartitionTable:
                return "That file has no partition table at offset 0x8000, so it isn’t a merged pager image."
            case let .largerThanFlash(bytes, flashBytes):
                return "That image is \(bytes) bytes, larger than the board’s \(flashBytes)-byte flash."
            }
        }
    }

    public init(validating data: Data, sourceURL: URL? = nil,
                flashSize: Int = 4 * 1024 * 1024) throws {
        guard !data.isEmpty else { throw ValidationError.empty }
        guard data.count <= flashSize else {
            throw ValidationError.largerThanFlash(bytes: data.count, flashBytes: flashSize)
        }

        if data.first == Self.imageMagic {
            throw ValidationError.looksLikeAppImage
        }
        guard data.count >= Self.minimumPlausibleSize else {
            throw ValidationError.tooSmall(bytes: data.count)
        }
        guard data[Self.bootloaderOffset] == Self.imageMagic else {
            throw ValidationError.missingBootloader
        }
        let tableMagic = [UInt8](data[Self.partitionTableOffset..<(Self.partitionTableOffset + 2)])
        guard tableMagic == Self.partitionMagic else {
            throw ValidationError.missingPartitionTable
        }

        self.data = data
        self.sourceURL = sourceURL
        self.md5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public init(validating url: URL) throws {
        try self.init(validating: try Data(contentsOf: url), sourceURL: url)
    }

    public static func bundled(in bundle: Bundle = .main) -> FirmwareImage? {
        guard let url = bundle.url(forResource: "13years-pager-merged", withExtension: "bin") else {
            return nil
        }
        return try? FirmwareImage(validating: url)
    }
}
