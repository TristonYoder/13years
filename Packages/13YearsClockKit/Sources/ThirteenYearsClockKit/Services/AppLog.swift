// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if canImport(os)
import os
#else
import Foundation
#endif

public enum AppLog {
    public static let networking = Logger(subsystem: "dev.7co.13years", category: "networking")
    public static let cue = Logger(subsystem: "dev.7co.13years", category: "cue")
    public static let bridge = Logger(subsystem: "dev.7co.13years", category: "bridge")
}

#if !canImport(os)
public struct OSLogPrivacy: Sendable {
    public enum Mask: Sendable {
        case hash
        case none
    }

    public static let `public` = OSLogPrivacy()
    public static let `private` = OSLogPrivacy()
    public static let auto = OSLogPrivacy()
    public static let sensitive = OSLogPrivacy()

    public static func `private`(mask: Mask) -> OSLogPrivacy { OSLogPrivacy() }
    public static func sensitive(mask: Mask) -> OSLogPrivacy { OSLogPrivacy() }
}

public struct ClockKitLogMessage: ExpressibleByStringInterpolation, ExpressibleByStringLiteral, Sendable {
    public let text: String

    public init(stringLiteral value: String) {
        text = value
    }

    public init(stringInterpolation: StringInterpolation) {
        text = stringInterpolation.text
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var text = ""

        public init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity)
        }

        public mutating func appendLiteral(_ literal: String) {
            text += literal
        }

        public mutating func appendInterpolation<T>(_ value: @autoclosure () -> T, privacy: OSLogPrivacy = .auto) {
            text += String(describing: value())
        }
    }
}

public struct Logger: Sendable {
    public enum Level: Int, Sendable {
        case trace = 0
        case debug
        case info
        case notice
        case warning
        case error
        case fault

        var label: String {
            switch self {
            case .trace: return "TRACE"
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .notice: return "NOTICE"
            case .warning: return "WARNING"
            case .error: return "ERROR"
            case .fault: return "FAULT"
            }
        }

        static func parse(_ raw: String) -> Level? {
            switch raw.lowercased() {
            case "trace": return .trace
            case "debug": return .debug
            case "info": return .info
            case "notice": return .notice
            case "warning", "warn": return .warning
            case "error": return .error
            case "fault": return .fault
            default: return nil
            }
        }
    }

    private static let minimumLevel: Level = {
        ProcessInfo.processInfo.environment["THIRTEEN_LOG_LEVEL"].flatMap(Level.parse) ?? .info
    }()

    public let subsystem: String
    public let category: String

    public init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
    }

    public func trace(_ message: ClockKitLogMessage) { emit(.trace, message) }
    public func debug(_ message: ClockKitLogMessage) { emit(.debug, message) }
    public func info(_ message: ClockKitLogMessage) { emit(.info, message) }
    public func notice(_ message: ClockKitLogMessage) { emit(.notice, message) }
    public func warning(_ message: ClockKitLogMessage) { emit(.warning, message) }
    public func error(_ message: ClockKitLogMessage) { emit(.error, message) }
    public func fault(_ message: ClockKitLogMessage) { emit(.fault, message) }
    public func log(_ message: ClockKitLogMessage) { emit(.info, message) }
    public func log(level: Level, _ message: ClockKitLogMessage) { emit(level, message) }

    private func emit(_ level: Level, _ message: ClockKitLogMessage) {
        guard level.rawValue >= Self.minimumLevel.rawValue else { return }
        let line = "\(level.label) [\(category)] \(message.text)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
#endif
