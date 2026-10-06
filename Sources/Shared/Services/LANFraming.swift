// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
import Network

enum LANFraming {
    static func frame(_ payload: Data) -> Data? {
        guard payload.count <= UInt32.max else { return nil }
        var length = UInt32(payload.count).bigEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(payload)
        return framed
    }

    static func decodeLength(_ data: Data) -> UInt32 {
        precondition(data.count == 4)
        return data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
        }
    }

    static func receiveFrame(on connection: NWConnection, queue: DispatchQueue, completion: @escaping (Data?) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { lengthData, _, _, error in
            queue.async {
                guard error == nil, let lengthData, lengthData.count == 4 else {
                    completion(nil)
                    return
                }
                let length = decodeLength(lengthData)
                guard length > 0, length <= 1 * 1024 * 1024 else {
                    completion(nil)
                    return
                }
                connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { payload, _, _, error in
                    queue.async {
                        guard error == nil, let payload, payload.count == Int(length) else {
                            completion(nil)
                            return
                        }
                        completion(payload)
                    }
                }
            }
        }
    }
}
