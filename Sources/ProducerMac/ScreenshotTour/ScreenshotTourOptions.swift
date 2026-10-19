// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import AppKit

struct ScreenshotTourOptions {
    let outputDirectory: URL
    let documentURL: URL?
    let only: [String]
    let appearance: NSAppearance.Name?
    let contentSize: NSSize

    static let current = ScreenshotTourOptions(arguments: ProcessInfo.processInfo.arguments)

    static var isActive: Bool { current != nil }

    init?(arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        guard let output = value("-ScreenshotTour"), !output.isEmpty else { return nil }
        outputDirectory = URL(fileURLWithPath: output, isDirectory: true)
        documentURL = value("-ScreenshotDocument").map { URL(fileURLWithPath: $0) }
        only = (value("-ScreenshotTourOnly") ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        switch value("-ScreenshotAppearance")?.lowercased() {
        case "dark": appearance = .darkAqua
        case "light": appearance = .aqua
        default: appearance = nil
        }
        let size = (value("-ScreenshotWindowSize") ?? "1440x900").split(separator: "x").compactMap { Double($0) }
        contentSize = size.count == 2 ? NSSize(width: size[0], height: size[1]) : NSSize(width: 1440, height: 900)
    }

    func includes(_ id: String) -> Bool {
        only.isEmpty || only.contains { id.hasPrefix($0) }
    }
}
