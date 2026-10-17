// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS) || os(iOS) || os(tvOS)
import Foundation

@MainActor
public final class PagerItemDetailsStore: ObservableObject {
    public typealias Transport = @Sendable (URL) async throws -> (status: Int, data: Data)

    @Published public private(set) var itemId: String?
    @Published public private(set) var html: String?

    private let transport: Transport
    private let refreshInterval: TimeInterval
    private let retryInterval: TimeInterval

    public init(
        transport: @escaping Transport = PagerItemDetailsTransport.live,
        refreshInterval: TimeInterval = PagerItemDetailsFetch.refreshInterval,
        retryInterval: TimeInterval = PagerItemDetailsFetch.retryInterval
    ) {
        self.transport = transport
        self.refreshInterval = refreshInterval
        self.retryInterval = retryInterval
    }

    public func source(for itemId: String) -> String? {
        self.itemId == itemId ? html : nil
    }

    public func reset() {
        itemId = nil
        html = nil
    }

    public func run(itemId: String, host: String, port: Int) async {
        if self.itemId != itemId {
            self.itemId = itemId
            html = nil
        }
        guard let url = PagerItemDetailsFetch.url(host: host, port: port, itemId: itemId) else { return }
        while !Task.isCancelled {
            var delay = retryInterval
            if let response = try? await transport(url), !Task.isCancelled {
                if response.status == 200 {
                    html = PagerItemDetailsFetch.source(fromResponse: response.data, expectedItemId: itemId)
                    delay = refreshInterval
                } else if response.status == 404 {
                    html = nil
                    delay = refreshInterval
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(max(0.01, delay) * 1_000_000_000))
        }
    }
}

public enum PagerItemDetailsTransport {
    public static let live: PagerItemDetailsStore.Transport = { url in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 8
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (bytes, response) = try await session.bytes(for: URLRequest(url: url))
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > PagerItemDetailsFetch.maxResponseBytes { throw URLError(.dataLengthExceedsMaximum) }
        }
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}
#endif
