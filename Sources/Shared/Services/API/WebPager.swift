// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

@MainActor
public enum WebPager {
    public nonisolated static let path = "/pager"

    private static let fontPrefix = "/pager/fonts/"

    public static func route(_ request: HTTPRequest) -> HTTPResponse? {
        let method = request.method.uppercased()
        guard method == "GET" || method == "HEAD" || method == "ANY" else { return nil }

        let response: HTTPResponse?
        switch request.path {
        case "/":
            response = .redirect(to: path)
        case path, path + "/", "/pager/index.html":
            response = page()
        default:
            response = request.path.hasPrefix(fontPrefix)
                ? font(named: String(request.path.dropFirst(fontPrefix.count)))
                : nil
        }

        guard var response, method == "HEAD" else { return response }
        response.headers["content-length"] = String(response.body.count)
        response.body = Data()
        return response
    }

    private static var cachedPage: Data?

    static func page() -> HTTPResponse {
        if let cachedPage {
            return .html(body: cachedPage)
        }
        guard let url = bundle.url(forResource: "pager", withExtension: "html"),
              let data = try? Data(contentsOf: url)
        else {
            AppLog.networking.error("WebPager: pager.html missing from the bundle — check Sources/Shared/Resources/WebPager")
            return ControlAPIRouter.error(500, "Web pager unavailable", detail: "pager.html is missing from this build.")
        }
        cachedPage = data
        return .html(body: data)
    }

    private static func font(named name: String) -> HTTPResponse {
        let base = name.hasSuffix(".ttf") ? String(name.dropLast(4)) : name
        guard AppFonts.interPostScriptNames.contains(base),
              let url = bundle.url(forResource: base, withExtension: "ttf"),
              let data = try? Data(contentsOf: url)
        else {
            return ControlAPIRouter.error(404, "Unknown font", detail: name)
        }
        return HTTPResponse(
            status: 200,
            headers: [
                "content-type": "font/ttf",
                "cache-control": "public, max-age=86400",
            ],
            body: data
        )
    }

    private final class BundleAnchor {}

    private static var bundle: Bundle {
        Bundle(for: BundleAnchor.self)
    }
}
