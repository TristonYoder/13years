// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import CoreGraphics
import Foundation

struct ScreenshotTourOptions {
    enum Appearance: String {
        case light
        case dark
    }

    let outputDirectory: URL
    let documentURL: URL?
    let only: [String]
    let appearance: Appearance?
    let contentSize: CGSize

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
        appearance = value("-ScreenshotAppearance").flatMap { Appearance(rawValue: $0.lowercased()) }
        let size = (value("-ScreenshotWindowSize") ?? "1440x900").split(separator: "x").compactMap { Double($0) }
        contentSize = size.count == 2 ? CGSize(width: size[0], height: size[1]) : CGSize(width: 1440, height: 900)
    }

    func includes(_ id: String) -> Bool {
        only.isEmpty || only.contains { id.hasPrefix($0) }
    }
}
