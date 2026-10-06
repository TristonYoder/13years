// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
import IOKit
import IOKit.serial

public struct SerialPortInfo: Sendable, Hashable, Identifiable {
    public let path: String
    public let name: String
    public let usbVendorID: Int?
    public let usbProductID: Int?

    public var id: String { path }

    public init(path: String, name: String, usbVendorID: Int?, usbProductID: Int?) {
        self.path = path
        self.name = name
        self.usbVendorID = usbVendorID
        self.usbProductID = usbProductID
    }

    private static let knownBridges: [Int: [Int: String]] = [
        0x1A86: [0x7523: "CH340", 0x7522: "CH340", 0x5523: "CH341", 0x55D4: "CH9102"],
        0x10C4: [0xEA60: "CP2102", 0xEA70: "CP2105"],
        0x0403: [0x6001: "FT232", 0x6010: "FT2232", 0x6014: "FT232H"],
        0x303A: [:],
    ]

    public var usbBridgeName: String? {
        guard let vid = usbVendorID else { return nil }
        guard let family = Self.knownBridges[vid] else { return nil }
        if let pid = usbProductID, let name = family[pid] { return name }
        return vid == 0x303A ? "Espressif USB" : nil
    }

    public var looksLikeBoard: Bool {
        if usbBridgeName != nil { return true }
        if usbVendorID != nil { return true }
        return false
    }

    public var displayName: String {
        if let bridge = usbBridgeName { return "\(bridge) (\(name))" }
        return name
    }

    public static func available() -> [SerialPortInfo] {
        var result: [SerialPortInfo] = []
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return [] }
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let path = registryString(service, kIOCalloutDeviceKey) else { continue }
            let name = registryString(service, kIOTTYDeviceKey) ?? (path as NSString).lastPathComponent
            let ids = usbIdentifiers(for: service)
            result.append(SerialPortInfo(path: path, name: name,
                                         usbVendorID: ids?.vendor, usbProductID: ids?.product))
        }

        return result.sorted {
            if $0.looksLikeBoard != $1.looksLikeBoard { return $0.looksLikeBoard }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func registryString(_ service: io_object_t, _ key: String) -> String? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    private static func usbIdentifiers(for service: io_object_t) -> (vendor: Int, product: Int)? {
        var node = service
        IOObjectRetain(node)
        defer { IOObjectRelease(node) }

        for _ in 0..<8 {
            let vendor = IORegistryEntryCreateCFProperty(node, "idVendor" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
            let product = IORegistryEntryCreateCFProperty(node, "idProduct" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
            if let vendor, let product { return (vendor, product) }

            var parent: io_object_t = 0
            guard IORegistryEntryGetParentEntry(node, kIOServicePlane, &parent) == KERN_SUCCESS else {
                return nil
            }
            IOObjectRelease(node)
            node = parent
        }
        return nil
    }
}

public enum SerialPortError: LocalizedError {
    case openFailed(path: String, errno: Int32)
    case alreadyOpen
    case notOpen
    case configurationFailed(operation: String, errno: Int32)
    case writeFailed(errno: Int32)
    case readFailed(errno: Int32)
    case timedOut(after: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case let .openFailed(path, code):
            let reason = String(cString: strerror(code))
            if code == EPERM || code == EACCES {
                return "Couldn’t open \(path): \(reason). The app may be missing the serial-device entitlement."
            }
            if code == EBUSY {
                return "\(path) is in use by another program. Close any serial monitor and try again."
            }
            return "Couldn’t open \(path): \(reason)."
        case .alreadyOpen:
            return "That serial port is already open."
        case .notOpen:
            return "The serial port isn’t open."
        case let .configurationFailed(operation, code):
            return "Couldn’t configure the serial port (\(operation)): \(String(cString: strerror(code)))."
        case let .writeFailed(code):
            return "Couldn’t write to the serial port: \(String(cString: strerror(code)))."
        case let .readFailed(code):
            return "Couldn’t read from the serial port: \(String(cString: strerror(code)))."
        case let .timedOut(after):
            return "The pager didn’t respond within \(Int(after)) seconds."
        }
    }
}

public final class SerialPort {
    public let path: String
    private var fd: Int32 = -1
    private var originalTermios: termios?

    public var isOpen: Bool { fd >= 0 }

    public init(path: String) {
        self.path = path
    }

    deinit { close() }

    public func open(baudRate: Int = 115_200) throws {
        guard fd < 0 else { throw SerialPortError.alreadyOpen }

        let handle = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard handle >= 0 else { throw SerialPortError.openFailed(path: path, errno: errno) }
        fd = handle

        if ioctl(fd, TIOCEXCL) != 0 {
            let code = errno
            closeDescriptor()
            throw SerialPortError.configurationFailed(operation: "TIOCEXCL", errno: code)
        }
        if fcntl(fd, F_SETFL, 0) == -1 {
            let code = errno
            closeDescriptor()
            throw SerialPortError.configurationFailed(operation: "clear O_NONBLOCK", errno: code)
        }

        var saved = termios()
        guard tcgetattr(fd, &saved) == 0 else {
            let code = errno
            closeDescriptor()
            throw SerialPortError.configurationFailed(operation: "tcgetattr", errno: code)
        }
        originalTermios = saved

        do {
            try configure(baudRate: baudRate)
            try setControlLines(dtr: false, rts: false)
        } catch {
            closeDescriptor()
            throw error
        }
    }

    public func close() {
        guard fd >= 0 else { return }
        if var saved = originalTermios {
            _ = tcsetattr(fd, TCSANOW, &saved)
        }
        closeDescriptor()
    }

    private func closeDescriptor() {
        if fd >= 0 { _ = Darwin.close(fd) }
        fd = -1
        originalTermios = nil
    }

    private func configure(baudRate: Int) throws {
        var options = termios()
        guard tcgetattr(fd, &options) == 0 else {
            throw SerialPortError.configurationFailed(operation: "tcgetattr", errno: errno)
        }
        cfmakeraw(&options)
        options.c_cflag |= tcflag_t(CS8 | CLOCAL | CREAD)
        options.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CRTSCTS)
        withUnsafeMutablePointer(to: &options.c_cc) { field in
            field.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { slots in
                slots[Int(VMIN)] = 0
                slots[Int(VTIME)] = 0
            }
        }
        guard tcsetattr(fd, TCSANOW, &options) == 0 else {
            throw SerialPortError.configurationFailed(operation: "tcsetattr", errno: errno)
        }
        try setBaudRate(baudRate)
    }

    public func setBaudRate(_ baudRate: Int) throws {
        guard fd >= 0 else { throw SerialPortError.notOpen }
        var options = termios()
        guard tcgetattr(fd, &options) == 0 else {
            throw SerialPortError.configurationFailed(operation: "tcgetattr", errno: errno)
        }
        guard cfsetspeed(&options, speed_t(baudRate)) == 0 else {
            throw SerialPortError.configurationFailed(operation: "cfsetspeed", errno: errno)
        }
        guard tcsetattr(fd, TCSANOW, &options) == 0 else {
            throw SerialPortError.configurationFailed(operation: "tcsetattr", errno: errno)
        }
    }

    public func setControlLines(dtr: Bool, rts: Bool) throws {
        guard fd >= 0 else { throw SerialPortError.notOpen }
        var bits: Int32 = 0
        if dtr { bits |= TIOCM_DTR }
        if rts { bits |= TIOCM_RTS }
        guard ioctl(fd, TIOCMSET, &bits) == 0 else {
            throw SerialPortError.configurationFailed(operation: "TIOCMSET", errno: errno)
        }
    }

    public func flush() {
        guard fd >= 0 else { return }
        _ = tcflush(fd, TCIOFLUSH)
    }

    public func write(_ data: Data) throws {
        guard fd >= 0 else { throw SerialPortError.notOpen }
        guard !data.isEmpty else { return }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if written < 0 {
                    if errno == EINTR || errno == EAGAIN { continue }
                    throw SerialPortError.writeFailed(errno: errno)
                }
                offset += written
            }
        }
    }

    public func write(_ string: String) throws {
        try write(Data(string.utf8))
    }

    private func waitReadable(timeout: TimeInterval) throws -> Bool {
        guard fd >= 0 else { throw SerialPortError.notOpen }
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let milliseconds = Int32(max(0, timeout * 1000).rounded())
        while true {
            let ready = poll(&pfd, 1, milliseconds)
            if ready < 0 {
                if errno == EINTR { continue }
                throw SerialPortError.readFailed(errno: errno)
            }
            return ready > 0
        }
    }

    public func read(maxLength: Int = 4096, timeout: TimeInterval = 1.0) throws -> Data {
        guard fd >= 0 else { throw SerialPortError.notOpen }
        guard try waitReadable(timeout: timeout) else { return Data() }
        var buffer = [UInt8](repeating: 0, count: maxLength)
        let count = Darwin.read(fd, &buffer, maxLength)
        if count < 0 {
            if errno == EINTR || errno == EAGAIN { return Data() }
            throw SerialPortError.readFailed(errno: errno)
        }
        return Data(buffer.prefix(max(0, count)))
    }
}
