// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension PCOClient {
    public static let maxAttachmentDownloadBytes = 250 * 1024 * 1024

    public func fetchAttachments(for owner: PCOAttachmentOwner) async throws -> [PCOAttachmentInfo] {
        var components = URLComponents(url: URL(string: owner.attachmentsPath, relativeTo: Self.baseURL)!, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "per_page", value: "100")]
        do {
            let json = try await fetchAllPages(from: components.url!, failureMessage: "Couldn't fetch the attachments from Planning Center.")
            return Self.parseAttachments(json)
        } catch let error as NSError where error.domain == "PCOClient" && (error.code == 403 || error.code == 404) {
            return []
        }
    }

    public func openAttachment(_ attachmentId: String, owner: PCOAttachmentOwner) async throws -> URL {
        let url = URL(string: owner.attachmentsPath + "/\(attachmentId)/open", relativeTo: Self.baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "PCOClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: "Planning Center wouldn't open that attachment."
            ])
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let signed = Self.parseAttachmentOpenURL(json) else {
            throw NSError(domain: "PCOClient", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Planning Center didn't return a secure link for that attachment."
            ])
        }
        return signed
    }

    public func downloadAttachment(from signedURL: URL, suggestedName: String) async throws -> URL {
        guard Self.isSignedDownloadURL(signedURL) else {
            throw NSError(domain: "PCOClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "That attachment link isn't secure."])
        }
        var request = URLRequest(url: signedURL)
        request.timeoutInterval = 120
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "PCOClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: "Couldn't download the attachment."
            ])
        }
        guard data.count <= Self.maxAttachmentDownloadBytes else {
            throw NSError(domain: "PCOClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "That attachment is too large to preview."])
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThirteenYearsAttachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(Self.safeFileName(suggestedName, fallbackExtension: signedURL.pathExtension))
        try data.write(to: file, options: .atomic)
        return file
    }

    public func fetchArrangementChart(songId: String, arrangementId: String) async throws -> PCOArrangementChart {
        let url = URL(string: "services/v2/songs/\(songId)/arrangements/\(arrangementId)", relativeTo: Self.baseURL)!
        let json = try await fetchJSON(from: url, failureMessage: "Couldn't fetch the chart from Planning Center.")
        guard let chart = Self.parseArrangementChart(json) else {
            throw NSError(domain: "PCOClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Planning Center didn't return that arrangement."])
        }
        return chart
    }

    static func parseAttachments(_ json: [String: Any]) -> [PCOAttachmentInfo] {
        (json["data"] as? [[String: Any]] ?? []).compactMap { resource in
            guard let id = resource["id"] as? String else { return nil }
            let attrs = attributes(resource)
            return PCOAttachmentInfo(
                id: id,
                filename: string(attrs["filename"]),
                contentType: string(attrs["content_type"]),
                fileSize: int(attrs["file_size"]),
                linkedURL: string(attrs["linked_url"]) ?? string(attrs["remote_link"]),
                pcoType: string(attrs["pco_type"]),
                displayName: string(attrs["display_name"]),
                attachableType: string(attrs["attachable_type"]),
                isStreamable: attrs["streamable"] as? Bool ?? false,
                isDownloadable: attrs["downloadable"] as? Bool ?? false
            )
        }
    }

    static func parseAttachmentOpenURL(_ json: [String: Any]) -> URL? {
        let attrs = attributes(json["data"] as? [String: Any])
        guard let raw = string(attrs["attachment_url"]) ?? string(attrs["url"]),
              let url = URL(string: raw),
              isSignedDownloadURL(url) else { return nil }
        return url
    }

    static func isSignedDownloadURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false && url.user == nil
    }

    static func parseArrangementChart(_ json: [String: Any]) -> PCOArrangementChart? {
        guard let resource = json["data"] as? [String: Any], let id = resource["id"] as? String else { return nil }
        let attrs = attributes(resource)
        return PCOArrangementChart(
            arrangementId: id,
            name: string(attrs["name"]),
            chordChart: string(attrs["chord_chart"]),
            lyrics: string(attrs["lyrics"]),
            chordChartKey: string(attrs["chord_chart_key"]),
            sequence: stringArray(attrs["sequence"]),
            bpm: double(attrs["bpm"]),
            meter: string(attrs["meter"])
        )
    }

    public static func safeFileName(_ name: String, fallbackExtension: String = "") -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        var cleaned = name.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
        if cleaned.isEmpty { cleaned = "Attachment" }
        if cleaned.count > 120 {
            let ext = URL(fileURLWithPath: cleaned).pathExtension
            let stem = String(URL(fileURLWithPath: cleaned).deletingPathExtension().lastPathComponent.prefix(100))
            cleaned = ext.isEmpty ? stem : stem + "." + ext
        }
        if URL(fileURLWithPath: cleaned).pathExtension.isEmpty, !fallbackExtension.isEmpty {
            cleaned += "." + fallbackExtension
        }
        return cleaned
    }
}
