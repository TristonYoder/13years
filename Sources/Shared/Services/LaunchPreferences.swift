// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS) || os(iOS)
import Foundation

public enum LaunchBehavior: String, CaseIterable, Identifiable, Sendable {
    case showLauncher
    case reopenLast
    case openFile
    case connectRemote

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .showLauncher: return "Show the start window"
        case .reopenLast: return "Reopen the last document"
        case .openFile: return "Open a specific document"
        case .connectRemote: return "Connect to a remote Producer"
        }
    }
}

public enum LaunchAction: Equatable {
    case showLauncher
    case reopenLast
    case openFile
    case connectRemote(RemoteEndpoint)
}

public enum LaunchPolicy {
    public static func decide(behavior: LaunchBehavior, remoteAddress: String) -> LaunchAction {
        switch behavior {
        case .showLauncher: return .showLauncher
        case .reopenLast: return .reopenLast
        case .openFile: return .openFile
        case .connectRemote:
            guard let endpoint = RemoteEndpoint.parse(remoteAddress) else { return .showLauncher }
            return .connectRemote(endpoint)
        }
    }
}

@MainActor
public final class LaunchPreferences: ObservableObject {
    private static let behaviorKey = "launchBehavior"
    private static let fileBookmarkKey = "launchFileBookmark"
    private static let remoteAddressKey = "launchRemoteAddress"

    private let defaults: UserDefaults

    @Published public var behavior: LaunchBehavior {
        didSet { defaults.set(behavior.rawValue, forKey: Self.behaviorKey) }
    }

    @Published public var remoteAddress: String {
        didSet { defaults.set(remoteAddress, forKey: Self.remoteAddressKey) }
    }

    @Published public private(set) var fileURL: URL?
    @Published public private(set) var bookmarkError: String?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.behavior = defaults.string(forKey: Self.behaviorKey).flatMap(LaunchBehavior.init(rawValue:)) ?? .showLauncher
        self.remoteAddress = defaults.string(forKey: Self.remoteAddressKey) ?? ""
        if let data = defaults.data(forKey: Self.fileBookmarkKey), let resolved = try? DocumentBookmark.resolved(data) {
            self.fileURL = resolved.url
            if resolved.bookmark != data { defaults.set(resolved.bookmark, forKey: Self.fileBookmarkKey) }
        }
    }

    public var action: LaunchAction {
        LaunchPolicy.decide(behavior: behavior, remoteAddress: remoteAddress)
    }

    public var isTemplate: Bool {
        fileURL?.pathExtension.lowercased() == ProducerDocument.templateExtension
    }

    public func setFile(_ url: URL) {
        do {
            let data = try DocumentBookmark.make(for: url)
            defaults.set(data, forKey: Self.fileBookmarkKey)
            fileURL = url
            bookmarkError = nil
        } catch {
            bookmarkError = "Couldn’t remember “\(url.lastPathComponent)” for the next launch. \(error.localizedDescription)"
        }
    }

    public func clearFile() {
        defaults.removeObject(forKey: Self.fileBookmarkKey)
        fileURL = nil
        bookmarkError = nil
    }
}
#endif
