// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS)
import Foundation

public enum LaunchBehavior: String, CaseIterable, Identifiable, Sendable {
    case showLauncher
    case reopenLast
    case openFile

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .showLauncher: return "Show the start window"
        case .reopenLast: return "Reopen the last document"
        case .openFile: return "Open a specific file"
        }
    }
}

@MainActor
public final class LaunchPreferences: ObservableObject {
    private static let behaviorKey = "launchBehavior"
    private static let fileBookmarkKey = "launchFileBookmark"

    private let defaults: UserDefaults

    @Published public var behavior: LaunchBehavior {
        didSet { defaults.set(behavior.rawValue, forKey: Self.behaviorKey) }
    }

    @Published public private(set) var fileURL: URL?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.behavior = defaults.string(forKey: Self.behaviorKey).flatMap(LaunchBehavior.init(rawValue:)) ?? .showLauncher
        if let data = defaults.data(forKey: Self.fileBookmarkKey) {
            var stale = false
            self.fileURL = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
        }
    }

    public var isTemplate: Bool {
        fileURL?.pathExtension.lowercased() == ProducerDocument.templateExtension
    }

    public func setFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        defaults.set(data, forKey: Self.fileBookmarkKey)
        fileURL = url
    }

    public func clearFile() {
        defaults.removeObject(forKey: Self.fileBookmarkKey)
        fileURL = nil
    }
}
#endif
