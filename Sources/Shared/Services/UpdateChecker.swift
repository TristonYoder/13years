// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public struct AppRelease: Equatable, Sendable {
    public let version: String
    public let url: URL
}

public enum AppVersion {
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate)
        let b = components(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func components(_ version: String) -> [Int] {
        var text = version.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("v") { text.removeFirst() }
        let core = text.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? text
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }
}

@MainActor
public final class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()

    private static let endpoint = URL(string: "https://api.github.com/repos/TristonYoder/13years/releases/latest")!
    private static let interval: TimeInterval = 24 * 60 * 60
    private static let dismissedKey = "dismissedUpdateVersion"

    @Published public private(set) var availableRelease: AppRelease?
    @Published public private(set) var isChecking = false
    @Published public private(set) var lastCheckFailed = false
    @Published public private(set) var lastCheckedAt: Date?
    @Published private var dismissedVersion: String? = UserDefaults.standard.string(forKey: dismissedKey)

    private var periodicTask: Task<Void, Never>?

    public var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    public var bannerRelease: AppRelease? {
        guard let release = availableRelease, release.version != dismissedVersion else { return nil }
        return release
    }

    public func startPeriodicChecks() {
        guard periodicTask == nil else { return }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(nanoseconds: UInt64(Self.interval * 1_000_000_000))
            }
        }
    }

    public func dismissBanner() {
        guard let release = availableRelease else { return }
        dismissedVersion = release.version
        UserDefaults.standard.set(release.version, forKey: Self.dismissedKey)
    }

    public func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("13years-update-check", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 404 {
                availableRelease = nil
                lastCheckFailed = false
                lastCheckedAt = Date()
                return
            }
            guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            lastCheckFailed = false
            lastCheckedAt = Date()
            if !payload.draft, !payload.prerelease,
               AppVersion.isNewer(payload.tagName, than: currentVersion),
               let url = URL(string: payload.htmlURL) {
                var version = payload.tagName
                if version.lowercased().hasPrefix("v") { version.removeFirst() }
                availableRelease = AppRelease(version: version, url: url)
            } else {
                availableRelease = nil
            }
        } catch {
            lastCheckFailed = true
            AppLog.networking.error("Update check failed: \(String(describing: error), privacy: .public)")
        }
    }

    private struct Payload: Decodable {
        let tagName: String
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
        }
    }
}
