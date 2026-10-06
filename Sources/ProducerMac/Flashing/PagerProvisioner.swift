// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct PagerProvisioning: Sendable, Equatable {
    public var ssid: String
    public var password: String
    public var roleID: String?
    public var producerHost: String?
    public var rotate180: Bool?

    public init(ssid: String, password: String, roleID: String? = nil,
                producerHost: String? = nil, rotate180: Bool? = nil) {
        self.ssid = ssid
        self.password = password
        self.roleID = roleID
        self.producerHost = producerHost
        self.rotate180 = rotate180
    }

    public var redactedDescription: String {
        let pass = password.isEmpty ? "(open network)" : "(\(password.count) characters)"
        let rotation = rotate180.map { $0 ? "180" : "normal" } ?? "unchanged"
        return "ssid=\(ssid) password=\(pass) role=\(roleID ?? "unchanged") "
             + "producer=\(producerHost ?? "unchanged") rotation=\(rotation)"
    }

    func commandJSON() throws -> String {
        var object: [String: Any] = ["ssid": ssid, "pass": password]
        if let roleID { object["role"] = roleID }
        if let producerHost { object["producer"] = producerHost }
        if let rotate180 { object["rotate180"] = rotate180 }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw PagerProvisioningError.malformedRequest
        }
        return json
    }

    public var validationError: String? {
        if ssid.isEmpty { return "Enter a Wi-Fi network name." }
        if ssid.utf8.count > 32 { return "Wi-Fi network names can’t be longer than 32 bytes." }
        if password.utf8.count > 63 { return "Wi-Fi passwords can’t be longer than 63 bytes." }
        if let roleID, roleID.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Choose a role for this pager."
        }
        if let producerHost, producerHost != "auto",
           IPv4Address.isValid(producerHost) == false {
            return "“\(producerHost)” isn’t a valid IP address."
        }
        return nil
    }
}

enum IPv4Address {
    static func isValid(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber) else { return false }
            guard let value = Int(part) else { return false }
            return value >= 0 && value <= 255
        }
    }
}

public struct PagerIdentity: Sendable, Equatable {
    public let deviceID: String
    public let ssid: String
    public let roleID: String
    public let producer: String
    public let rotate180: Bool
}

public enum PagerProvisioningError: LocalizedError, Equatable {
    case rejected(reason: String)
    case noAcknowledgement(timeout: TimeInterval)
    case malformedAcknowledgement(line: String)
    case malformedRequest
    case validation(String)

    public var errorDescription: String? {
        switch self {
        case let .rejected(reason):
            return Self.humanReadable(reason)
        case let .noAcknowledgement(timeout):
            return "The pager didn’t acknowledge within \(Int(timeout)) seconds. "
                 + "Check the cable, and that the firmware on it is current enough to support provisioning."
        case let .malformedAcknowledgement(line):
            return "The pager sent a reply this app didn’t understand: “\(line)”."
        case .malformedRequest:
            return "Couldn’t encode the provisioning request."
        case let .validation(message):
            return message
        }
    }

    private static func humanReadable(_ reason: String) -> String {
        switch reason {
        case "malformed-json", "expected-json-object":
            return "The pager couldn’t read the provisioning request. This is a bug in the app."
        case "missing-ssid":
            return "The pager rejected the request: no Wi-Fi network name was sent."
        case "bad-ssid-length":
            return "The pager rejected the Wi-Fi network name as too long (32 bytes maximum)."
        case "bad-password-length":
            return "The pager rejected the Wi-Fi password as too long (63 bytes maximum)."
        case "bad-role":
            return "The pager rejected the role as empty."
        case "bad-producer-ip":
            return "The pager rejected the producer address as not a valid IP."
        case "bad-rotate180":
            return "The pager rejected the screen-rotation setting. This is a bug in the app."
        default:
            return "The pager rejected the request: \(reason)."
        }
    }
}

public enum PagerProvisioner {
    private static let okPrefix = "[ok] provision "
    private static let errorPrefix = "[err] provision "

    enum Acknowledgement: Equatable {
        case success(PagerIdentity)
        case failure(reason: String)
        case unrelated
    }

    static func classify(line: String) throws -> Acknowledgement {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix(errorPrefix) {
            let reason = String(trimmed.dropFirst(errorPrefix.count))
                .trimmingCharacters(in: .whitespaces)
            return .failure(reason: reason.isEmpty ? "unspecified" : reason)
        }

        guard trimmed.hasPrefix(okPrefix) else { return .unrelated }

        let payload = String(trimmed.dropFirst(okPrefix.count))
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceID = object["deviceId"] as? String,
              let ssid = object["ssid"] as? String,
              let role = object["role"] as? String,
              let producer = object["producer"] as? String
        else {
            throw PagerProvisioningError.malformedAcknowledgement(line: trimmed)
        }
        let rotated = object["rotate180"] as? Bool ?? false
        return .success(PagerIdentity(deviceID: deviceID, ssid: ssid,
                                      roleID: role, producer: producer,
                                      rotate180: rotated))
    }

    private static let bannerMarker = "13years ESP32"

    @discardableResult
    public static func waitForConsole(on port: SerialPort, timeout: TimeInterval = 10) -> Bool {
        var seen = ""
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard let chunk = try? port.read(timeout: 0.25), !chunk.isEmpty else { continue }
            seen += String(decoding: chunk, as: UTF8.self)
            if seen.contains(bannerMarker) {
                Thread.sleep(forTimeInterval: 1.5)
                return true
            }
        }
        return false
    }

    static func takeLines(from buffer: inout Data) -> [String] {
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
            buffer = Data(buffer[buffer.index(after: newline)...])
        }
        return lines
    }

    public static func provision(
        _ provisioning: PagerProvisioning,
        over port: SerialPort,
        timeout: TimeInterval = 15
    ) throws -> PagerIdentity {
        if let message = provisioning.validationError {
            throw PagerProvisioningError.validation(message)
        }

        port.flush()
        try port.write("provision \(provisioning.commandJSON())\n")

        let deadline = Date().addingTimeInterval(timeout)
        var pending = Data()

        while Date() < deadline {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            let chunk = try port.read(timeout: min(remaining, 0.5))
            guard !chunk.isEmpty else { continue }
            pending.append(chunk)

            for line in takeLines(from: &pending) {
                switch try classify(line: line) {
                case let .success(identity):
                    return identity
                case let .failure(reason):
                    throw PagerProvisioningError.rejected(reason: reason)
                case .unrelated:
                    continue
                }
            }
        }

        throw PagerProvisioningError.noAcknowledgement(timeout: timeout)
    }
}
