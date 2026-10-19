// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

enum TourUIError: Error, CustomStringConvertible {
    case notFound(String)
    case timedOut(String)
    case skipped(String)

    var description: String {
        switch self {
        case .notFound(let what): return "not found: \(what)"
        case .timedOut(let what): return "timed out waiting for \(what)"
        case .skipped(let reason): return reason
        }
    }
}

@MainActor
final class ScreenshotTour {
    struct Step {
        let id: String
        let title: String
        var capture: Capture = .standard
        var prepare: () async throws -> Void = {}
        #if os(macOS)
        var tracking: ((TrackingSession) -> Void)?
        #endif
        var cleanup: () async -> Void = {}
    }

    enum Outcome {
        case captured
        case skipped(String)
        case failed(String)
    }

    private struct Record: Encodable {
        let index: Int
        let id: String
        let title: String
        let file: String?
        let status: String
        let reason: String?
        let seconds: Double
    }

    let options: ScreenshotTourOptions
    var beforeCapture: () -> Void = {}
    private var records: [Record] = []

    init(options: ScreenshotTourOptions) {
        self.options = options
    }

    static func prepareProcess() {
        guard let options = ScreenshotTourOptions.current else { return }
        setenv("THIRTEEN_EPHEMERAL_KEYCHAIN", "1", 1)
        UpdateChecker.shared.isAutomaticCheckingSuspended = true
        try? FileManager.default.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)
    }

    var pendingURL: URL { options.outputDirectory.appendingPathComponent(".pending.json") }
    var ackURL: URL { options.outputDirectory.appendingPathComponent(".ack.json") }
    private var debugDirectory: URL { options.outputDirectory.appendingPathComponent(".debug", isDirectory: true) }

    func run(setUp: () async -> Void, steps: () -> [Step]) async {
        await waitForInterface()
        await setUp()
        await pause(1.0)
        arrangeInterface()
        let all = steps()
        for (offset, step) in all.enumerated() where options.includes(step.id) {
            let index = offset + 1
            let file = String(format: "%02d-%@.png", index, step.id.replacingOccurrences(of: ".", with: "-"))
            let began = Date()
            let outcome = await perform(step, index: index, file: file)
            await step.cleanup()
            await dismissOverlays()
            let seconds = (Date().timeIntervalSince(began) * 10).rounded() / 10
            switch outcome {
            case .captured:
                records.append(Record(index: index, id: step.id, title: step.title, file: file, status: "ok", reason: nil, seconds: seconds))
            case .skipped(let reason):
                records.append(Record(index: index, id: step.id, title: step.title, file: nil, status: "skipped", reason: reason, seconds: seconds))
            case .failed(let reason):
                records.append(Record(index: index, id: step.id, title: step.title, file: nil, status: "failed", reason: reason, seconds: seconds))
                writeDebug(step.id)
            }
        }
        finish()
    }

    private func perform(_ step: Step, index: Int, file: String) async -> Outcome {
        do {
            try await step.prepare()
        } catch let error as TourUIError {
            if case .skipped(let reason) = error { return .skipped(reason) }
            return .failed(error.description)
        } catch {
            return .failed(String(describing: error))
        }
        #if os(macOS)
        if let tracking = step.tracking {
            return await captureWhileTracking(step, index: index, file: file, open: tracking)
        }
        #endif
        await pause(0.9)
        await tidyBeforeCapture()
        beforeCapture()
        await pause(0.3)
        return await capture(step, index: index, file: file)
    }

    func writeRequest(_ step: Step, index: Int, file: String) -> String? {
        let fields: [String: Any]
        do {
            fields = try requestFields(for: step.capture)
        } catch {
            return String(describing: error)
        }
        try? FileManager.default.removeItem(at: ackURL)
        var pending: [String: Any] = [
            "index": index,
            "id": step.id,
            "title": step.title,
            "file": file,
            "pid": Int(ProcessInfo.processInfo.processIdentifier)
        ]
        pending.merge(fields) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: pending, options: [.sortedKeys]) else { return "could not encode request" }
        do {
            try data.write(to: pendingURL, options: .atomic)
        } catch {
            return "could not write request: \(error.localizedDescription)"
        }
        return nil
    }

    func readAck(index: Int) -> Outcome? {
        guard let ack = try? Data(contentsOf: ackURL),
              let object = try? JSONSerialization.jsonObject(with: ack) as? [String: Any],
              object["index"] as? Int == index else { return nil }
        if object["ok"] as? Bool == true { return .captured }
        return .failed(object["error"] as? String ?? "capture failed")
    }

    private func capture(_ step: Step, index: Int, file: String) async -> Outcome {
        if let error = writeRequest(step, index: index, file: file) { return .failed(error) }
        for _ in 0..<300 {
            if let outcome = readAck(index: index) { return outcome }
            await pause(0.1)
        }
        return .failed("no capture acknowledgement")
    }

    private func finish() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(records) {
            try? data.write(to: options.outputDirectory.appendingPathComponent(".tour.json"), options: .atomic)
        }
        terminate()
    }

    private func writeDebug(_ id: String) {
        try? FileManager.default.createDirectory(at: debugDirectory, withIntermediateDirectories: true)
        try? debugText().write(to: debugDirectory.appendingPathComponent("\(id).txt"), atomically: true, encoding: .utf8)
    }

    func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

@MainActor
protocol ScreenshotTourClient: AnyObject {
    var runner: ScreenshotTour { get }
}

extension ScreenshotTourClient {
    typealias Step = ScreenshotTour.Step

    func pause(_ seconds: Double) async {
        await runner.pause(seconds)
    }
}
