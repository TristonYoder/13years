// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct HTTPRequest: Sendable {
    public var method: String
    public var path: String
    public var query: [String: String]
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, query: [String: String] = [:], headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public func serialize() -> Data {
        var canonical: [String: String] = [:]
        for (name, value) in headers {
            canonical[Self.canonicalName(name)] = value
        }
        if canonical["Content-Length"] == nil {
            canonical["Content-Length"] = String(body.count)
        }
        if canonical["Connection"] == nil {
            canonical["Connection"] = "keep-alive"
        }

        var result = Data("HTTP/1.1 \(status) \(Self.reasonPhrase(for: status))\r\n".utf8)
        for (name, value) in canonical.sorted(by: { $0.key < $1.key }) {
            result.append(Data("\(name): \(value)\r\n".utf8))
        }
        result.append(Data("\r\n".utf8))
        result.append(body)
        return result
    }

    public static func json(status: Int, body: Data) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["content-type": "application/json"], body: body)
    }

    public static func empty(status: Int) -> HTTPResponse {
        HTTPResponse(status: status)
    }

    public static func html(status: Int = 200, body: Data) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: ["content-type": "text/html; charset=utf-8", "cache-control": "no-store"],
            body: body
        )
    }

    public static func redirect(to location: String) -> HTTPResponse {
        HTTPResponse(status: 302, headers: ["location": location])
    }

    static func canonicalName(_ name: String) -> String {
        name.split(separator: "-", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: "-")
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 415: return "Unsupported Media Type"
        case 426: return "Upgrade Required"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return status < 400 ? "OK" : "Error"
        }
    }
}

public enum HTTPParseResult: Sendable {
    case incomplete
    case request(HTTPRequest, consumed: Int)
    case failure(String)
}

public enum HTTPMessageParser {
    public static let maxHeadBytes = 16 * 1024
    public static let maxBodyBytes = 1 * 1024 * 1024

    private static let crlfcrlf: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]
    private static let crlf: [UInt8] = [0x0D, 0x0A]

    public static func parse(_ buffer: [UInt8]) -> HTTPParseResult {
        guard let headEnd = firstIndex(of: crlfcrlf, in: buffer) else {
            return buffer.count > maxHeadBytes ? .failure("Request head exceeds \(maxHeadBytes) bytes") : .incomplete
        }

        let headLines = splitLines(Array(buffer[..<headEnd]))
        guard let requestLine = headLines.first else {
            return .failure("Empty request head")
        }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 3, parts[2].uppercased().hasPrefix("HTTP/1") else {
            return .failure("Malformed request line")
        }
        let method = parts[0].uppercased()
        let (path, query) = splitTarget(parts[1])

        var headers: [String: String] = [:]
        for line in headLines.dropFirst() {
            guard !line.isEmpty else { continue }
            guard let colon = line.firstIndex(of: ":") else {
                return .failure("Header line missing colon")
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return .failure("Header line with empty name") }
            headers[name] = value
        }

        if headers["transfer-encoding"] != nil {
            return .failure("Chunked transfer-encoding is not supported")
        }

        var bodyLength = 0
        if let raw = headers["content-length"] {
            guard let length = Int(raw), length >= 0 else {
                return .failure("Invalid Content-Length: \(raw)")
            }
            guard length <= maxBodyBytes else {
                return .failure("Content-Length \(length) exceeds \(maxBodyBytes)")
            }
            bodyLength = length
        }

        let bodyStart = headEnd + crlfcrlf.count
        let total = bodyStart + bodyLength
        guard buffer.count >= total else { return .incomplete }

        return .request(
            HTTPRequest(
                method: method,
                path: path,
                query: query,
                headers: headers,
                body: Data(buffer[bodyStart..<total])
            ),
            consumed: total
        )
    }

    private static func firstIndex(of pattern: [UInt8], in buffer: [UInt8]) -> Int? {
        guard buffer.count >= pattern.count else { return nil }
        for start in 0...(buffer.count - pattern.count) where buffer[start..<(start + pattern.count)].elementsEqual(pattern) {
            return start
        }
        return nil
    }

    private static func splitLines(_ bytes: [UInt8]) -> [String] {
        var lines: [String] = []
        var current: [UInt8] = []
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x0D, index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                lines.append(String(decoding: current, as: UTF8.self))
                current.removeAll(keepingCapacity: true)
                index += 2
            } else if bytes[index] == 0x0A {
                lines.append(String(decoding: current, as: UTF8.self))
                current.removeAll(keepingCapacity: true)
                index += 1
            } else {
                current.append(bytes[index])
                index += 1
            }
        }
        if !current.isEmpty {
            lines.append(String(decoding: current, as: UTF8.self))
        }
        return lines
    }

    private static func splitTarget(_ target: String) -> (path: String, query: [String: String]) {
        guard let mark = target.firstIndex(of: "?") else {
            return (percentDecode(target), [:])
        }
        let path = percentDecode(String(target[..<mark]))
        var query: [String: String] = [:]
        for pair in target[target.index(after: mark)...].split(separator: "&") {
            let halves = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = percentDecode(String(halves[0]), plusAsSpace: true)
            guard !key.isEmpty else { continue }
            query[key] = halves.count > 1 ? percentDecode(String(halves[1]), plusAsSpace: true) : ""
        }
        return (path, query)
    }

    static func percentDecode(_ text: String, plusAsSpace: Bool = false) -> String {
        let source = Array(text.utf8)
        var output: [UInt8] = []
        output.reserveCapacity(source.count)
        var index = 0
        while index < source.count {
            let byte = source[index]
            if plusAsSpace, byte == UInt8(ascii: "+") {
                output.append(UInt8(ascii: " "))
                index += 1
            } else if byte == UInt8(ascii: "%"), index + 2 < source.count,
                      let high = hexValue(source[index + 1]), let low = hexValue(source[index + 2]) {
                output.append(high << 4 | low)
                index += 3
            } else {
                output.append(byte)
                index += 1
            }
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
}
