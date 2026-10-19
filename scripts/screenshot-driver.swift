// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import AppKit
import CryptoKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct Arguments {
    var work = ""
    var out = ""
    var pid: pid_t = 0
    var version = ""
    var build = ""
    var commit = ""
    var appearance = ""
    var app = "producer-mac"
    var device = ""
    var simulator = ""
    var timeout: TimeInterval = 600

    init() {
        var iterator = CommandLine.arguments.dropFirst().makeIterator()
        while let flag = iterator.next() {
            let value = iterator.next() ?? ""
            switch flag {
            case "--work": work = value
            case "--out": out = value
            case "--pid": pid = pid_t(value) ?? 0
            case "--version": version = value
            case "--build": build = value
            case "--commit": commit = value
            case "--appearance": appearance = value
            case "--app": app = value
            case "--device": device = value
            case "--simulator": simulator = value
            case "--timeout": timeout = TimeInterval(value) ?? 600
            default: break
            }
        }
    }
}

struct Request: Decodable {
    let index: Int
    let id: String
    let title: String
    let file: String
    let pid: Int
    let windowIDs: [Int]?
    let includeMenus: Bool?
    let orientation: String?
}

struct TourRecord: Decodable {
    let index: Int
    let id: String
    let title: String
    let file: String?
    let status: String
    let reason: String?
}

struct ManifestImage: Encodable {
    let id: String
    let index: Int
    let title: String
    let file: String
    let width: Int
    let height: Int
    let sha256: String
}

struct ManifestSkip: Encodable {
    let id: String
    let index: Int
    let title: String
    let status: String
    let reason: String
}

struct Manifest: Encodable {
    let app: String
    let device: String
    let version: String
    let build: String
    let commit: String
    let date: String
    let appearance: String
    let images: [ManifestImage]
    let missing: [ManifestSkip]
}

enum CaptureError: Error, CustomStringConvertible {
    case noWindows
    case noDisplay
    case writeFailed
    case simulator(String)

    var description: String {
        switch self {
        case .noWindows: return "no matching on-screen windows"
        case .noDisplay: return "windows are not on a single display"
        case .writeFailed: return "could not write PNG"
        case .simulator(let message): return "simctl screenshot failed: \(message)"
        }
    }
}

func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

func capture(_ request: Request, to url: URL) async throws -> (Int, Int) {
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    let owned = content.windows.filter { $0.owningApplication?.processID == pid_t(request.pid) }
    let ids = request.windowIDs ?? []
    var windows = owned.filter { ids.contains(Int($0.windowID)) }
    if request.includeMenus == true {
        windows += owned.filter { $0.windowLayer >= 100 && !ids.contains(Int($0.windowID)) && $0.frame.width > 4 }
    }
    guard !windows.isEmpty else { throw CaptureError.noWindows }
    let union = windows.map(\.frame).reduce(windows[0].frame) { $0.union($1) }
    guard let display = content.displays.first(where: { $0.frame.intersects(union) && $0.frame.contains(CGPoint(x: union.midX, y: union.midY)) }) else {
        throw CaptureError.noDisplay
    }
    let rect = union.intersection(display.frame)
    let filter = SCContentFilter(display: display, including: windows)
    let scale = CGFloat(filter.pointPixelScale)
    let configuration = SCStreamConfiguration()
    configuration.sourceRect = CGRect(x: rect.minX - display.frame.minX, y: rect.minY - display.frame.minY, width: rect.width, height: rect.height)
    configuration.width = Int((rect.width * scale).rounded())
    configuration.height = Int((rect.height * scale).rounded())
    configuration.showsCursor = false
    configuration.backgroundColor = CGColor.clear
    configuration.ignoreShadowsDisplay = true
    configuration.captureResolution = .best
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CaptureError.writeFailed }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CaptureError.writeFailed }
    return (image.width, image.height)
}

func simulatorCapture(_ request: Request, udid: String, to url: URL) throws -> (Int, Int) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["simctl", "io", udid, "screenshot", "--type=png", url.path]
    let errors = Pipe()
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw CaptureError.simulator(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CaptureError.writeFailed }
    let landscape = request.orientation?.hasPrefix("landscape") == true
    guard landscape, image.height > image.width else { return (image.width, image.height) }
    let clockwise = request.orientation == "landscapeLeft"
    guard let context = CGContext(data: nil, width: image.height, height: image.width, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw CaptureError.writeFailed
    }
    if clockwise {
        context.translateBy(x: 0, y: CGFloat(image.width))
        context.rotate(by: -.pi / 2)
    } else {
        context.translateBy(x: CGFloat(image.height), y: 0)
        context.rotate(by: .pi / 2)
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let rotated = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CaptureError.writeFailed }
    CGImageDestinationAddImage(destination, rotated, nil)
    guard CGImageDestinationFinalize(destination) else { throw CaptureError.writeFailed }
    return (rotated.width, rotated.height)
}

func writeJSON(_ object: [String: Any], to url: URL) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    try? data.write(to: url, options: .atomic)
}

func sha256(of url: URL) -> String {
    guard let data = try? Data(contentsOf: url) else { return "" }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func pixelSize(of url: URL) -> (Int, Int) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return (0, 0) }
    return ((properties[kCGImagePropertyPixelWidth] as? Int) ?? 0, (properties[kCGImagePropertyPixelHeight] as? Int) ?? 0)
}

func run(_ arguments: Arguments) async -> Int32 {
    let work = URL(fileURLWithPath: arguments.work, isDirectory: true)
    let out = URL(fileURLWithPath: arguments.out, isDirectory: true)
    let pendingURL = work.appendingPathComponent(".pending.json")
    let ackURL = work.appendingPathComponent(".ack.json")
    let tourURL = work.appendingPathComponent(".tour.json")
    let deadline = Date().addingTimeInterval(arguments.timeout)
    if arguments.simulator.isEmpty {
        CGWarpMouseCursorPosition(CGPoint(x: (NSScreen.screens.first?.frame.maxX ?? 1600) - 120, y: 600))
    }
    var lastIndex = -1
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: tourURL.path) { break }
        if let data = try? Data(contentsOf: pendingURL),
           let request = try? JSONDecoder().decode(Request.self, from: data),
           request.index != lastIndex {
            lastIndex = request.index
            let target = work.appendingPathComponent(request.file)
            do {
                let (width, height) = arguments.simulator.isEmpty
                    ? try await capture(request, to: target)
                    : try simulatorCapture(request, udid: arguments.simulator, to: target)
                print("captured \(request.file) \(width)x\(height)")
                writeJSON(["index": request.index, "ok": true], to: ackURL)
            } catch {
                print("failed \(request.id): \(error)")
                writeJSON(["index": request.index, "ok": false, "error": String(describing: error)], to: ackURL)
            }
            continue
        }
        if arguments.pid > 0, !isAlive(arguments.pid) { break }
        try? await Task.sleep(nanoseconds: 80_000_000)
    }
    guard let tourData = try? Data(contentsOf: tourURL),
          let records = try? JSONDecoder().decode([TourRecord].self, from: tourData) else {
        print("the app did not finish the tour")
        return 1
    }
    try? FileManager.default.removeItem(at: out)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    var images: [ManifestImage] = []
    var missing: [ManifestSkip] = []
    for record in records {
        if record.status == "ok", let file = record.file {
            let source = work.appendingPathComponent(file)
            let destination = out.appendingPathComponent(file)
            guard (try? FileManager.default.copyItem(at: source, to: destination)) != nil else {
                missing.append(ManifestSkip(id: record.id, index: record.index, title: record.title, status: "failed", reason: "image missing"))
                continue
            }
            let (width, height) = pixelSize(of: destination)
            images.append(ManifestImage(id: record.id, index: record.index, title: record.title, file: file, width: width, height: height, sha256: sha256(of: destination)))
        } else {
            missing.append(ManifestSkip(id: record.id, index: record.index, title: record.title, status: record.status, reason: record.reason ?? ""))
        }
    }
    let formatter = ISO8601DateFormatter()
    let manifest = Manifest(
        app: arguments.app,
        device: arguments.device,
        version: arguments.version,
        build: arguments.build,
        commit: arguments.commit,
        date: formatter.string(from: Date()),
        appearance: arguments.appearance,
        images: images,
        missing: missing
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    if let data = try? encoder.encode(manifest) {
        try? data.write(to: out.appendingPathComponent("manifest.json"), options: .atomic)
    }
    print("\(images.count) images, \(missing.count) skipped or failed")
    for item in missing { print("  \(item.status) \(item.id): \(item.reason)") }
    return 0
}

_ = NSApplication.shared
let arguments = Arguments()
let semaphore = DispatchSemaphore(value: 0)
var status: Int32 = 1
Task {
    status = await run(arguments)
    semaphore.signal()
}
semaphore.wait()
exit(status)
