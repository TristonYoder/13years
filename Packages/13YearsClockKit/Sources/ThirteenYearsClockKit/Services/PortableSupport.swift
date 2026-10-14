// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

#if !canImport(SwiftUI)
extension Array {
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { self[$0] }
        let before = source.filter { $0 < destination }.count
        for index in source.reversed() { remove(at: index) }
        insert(contentsOf: moving, at: destination - before)
    }
}
#endif

#if !canImport(Network)
extension CueEngine {
    static func sendAssignPing(_ payload: Data, to host: String) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        #if canImport(Glibc)
        hints.ai_socktype = Int32(SOCK_DGRAM.rawValue)
        #else
        hints.ai_socktype = SOCK_DGRAM
        #endif
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(LANUnicastServer.assignPort), &hints, &result) == 0, let info = result else { return false }
        defer { freeaddrinfo(result) }
        let descriptor = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        let sent = payload.withUnsafeBytes { buffer in
            sendto(descriptor, buffer.baseAddress, buffer.count, 0, info.pointee.ai_addr, info.pointee.ai_addrlen)
        }
        return sent == payload.count
    }
}
#endif
