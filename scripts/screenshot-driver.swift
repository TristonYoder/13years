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
    let windowIDs: [Int]
    let includeMenus: Bool
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

    var description: String {
        switch self {
        case .noWindows: return "no matching on-screen windows"
        case .noDisplay: return "windows are not on a single display"
        case .writeFailed: return "could not write PNG"
        }
    }
}

func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

func capture(_ request: Request, to url: URL) async throws -> (Int, Int) {
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    let owned = content.windows.filter { $0.owningApplication?.processID == pid_t(request.pid) }
    var windows = owned.filter { request.windowIDs.contains(Int($0.windowID)) }
    if request.includeMenus {
        windows += owned.filter { $0.windowLayer >= 100 && !request.windowIDs.contains(Int($0.windowID)) && $0.frame.width > 4 }
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
    CGWarpMouseCursorPosition(CGPoint(x: (NSScreen.screens.first?.frame.maxX ?? 1600) - 120, y: 600))
    var lastIndex = -1
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: tourURL.path) { break }
        if let data = try? Data(contentsOf: pendingURL),
           let request = try? JSONDecoder().decode(Request.self, from: data),
           request.index != lastIndex {
            lastIndex = request.index
            let target = work.appendingPathComponent(request.file)
            do {
                let (width, height) = try await capture(request, to: target)
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
        app: "producer-mac",
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
