// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum PCOAttachmentOwner: Hashable, Sendable {
    case item(serviceTypeId: String, planId: String, itemId: String)
    case song(id: String)
    case arrangement(songId: String, arrangementId: String)
    case media(id: String)
    case plan(serviceTypeId: String, planId: String)

    public var resourcePath: String {
        switch self {
        case .item(let serviceTypeId, let planId, let itemId):
            return "services/v2/service_types/\(serviceTypeId)/plans/\(planId)/items/\(itemId)"
        case .song(let id):
            return "services/v2/songs/\(id)"
        case .arrangement(let songId, let arrangementId):
            return "services/v2/songs/\(songId)/arrangements/\(arrangementId)"
        case .media(let id):
            return "services/v2/media/\(id)"
        case .plan(let serviceTypeId, let planId):
            return "services/v2/service_types/\(serviceTypeId)/plans/\(planId)"
        }
    }

    public var attachmentsPath: String { resourcePath + "/attachments" }

    public var cacheKey: String { attachmentsPath }

    public var groupTitle: String {
        switch self {
        case .item: return "Item"
        case .song: return "Song"
        case .arrangement: return "Arrangement"
        case .media: return "Media"
        case .plan: return "Plan"
        }
    }

    public static func owners(for item: PCOTimerItem) -> [PCOAttachmentOwner] {
        var owners: [PCOAttachmentOwner] = []
        if let serviceTypeId = item.pcoServiceTypeId, let planId = item.pcoPlanId {
            owners.append(.item(serviceTypeId: serviceTypeId, planId: planId, itemId: item.id))
        }
        if let songId = item.details?.song?.id {
            owners.append(.song(id: songId))
            if let arrangementId = item.details?.arrangement?.id {
                owners.append(.arrangement(songId: songId, arrangementId: arrangementId))
            }
        }
        if let mediaId = item.details?.media?.id {
            owners.append(.media(id: mediaId))
        }
        return owners
    }

    public static func chartReference(for item: PCOTimerItem) -> (songId: String, arrangementId: String)? {
        guard item.pcoPlanId != nil,
              let songId = item.details?.song?.id,
              let arrangementId = item.details?.arrangement?.id else { return nil }
        return (songId, arrangementId)
    }
}

public enum PCOAttachmentKind: String, Sendable, Hashable {
    case pdf
    case image
    case audio
    case video
    case document
    case link
    case other
}

public struct PCOAttachmentInfo: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var filename: String?
    public var contentType: String?
    public var fileSize: Int?
    public var linkedURL: String?
    public var pcoType: String?
    public var displayName: String?
    public var attachableType: String?
    public var isStreamable: Bool
    public var isDownloadable: Bool

    public init(
        id: String,
        filename: String? = nil,
        contentType: String? = nil,
        fileSize: Int? = nil,
        linkedURL: String? = nil,
        pcoType: String? = nil,
        displayName: String? = nil,
        attachableType: String? = nil,
        isStreamable: Bool = false,
        isDownloadable: Bool = false
    ) {
        self.id = id
        self.filename = filename
        self.contentType = contentType
        self.fileSize = fileSize
        self.linkedURL = linkedURL
        self.pcoType = pcoType
        self.displayName = displayName
        self.attachableType = attachableType
        self.isStreamable = isStreamable
        self.isDownloadable = isDownloadable
    }

    public var title: String {
        for candidate in [displayName, filename] {
            if let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        }
        return "Attachment"
    }

    public var externalLink: URL? {
        guard let raw = linkedURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    public var isLink: Bool { externalLink != nil }

    public var kind: PCOAttachmentKind {
        if isLink { return .link }
        let type = (contentType ?? "").lowercased()
        let ext = filename.map { URL(fileURLWithPath: $0).pathExtension.lowercased() } ?? ""
        if type.contains("pdf") || ext == "pdf" { return .pdf }
        if type.hasPrefix("image/") || ["png", "jpg", "jpeg", "gif", "heic", "webp", "tif", "tiff"].contains(ext) { return .image }
        if type.hasPrefix("audio/") || ["mp3", "wav", "m4a", "aac", "aif", "aiff", "flac"].contains(ext) { return .audio }
        if type.hasPrefix("video/") || ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext) { return .video }
        if type.contains("word") || type.contains("presentation") || type.contains("spreadsheet") || type.hasPrefix("text/")
            || ["doc", "docx", "ppt", "pptx", "key", "pages", "xls", "xlsx", "txt", "rtf", "odt"].contains(ext) { return .document }
        return .other
    }
}

public struct PCOArrangementChart: Equatable, Sendable {
    public var arrangementId: String
    public var name: String?
    public var chordChart: String?
    public var lyrics: String?
    public var chordChartKey: String?
    public var sequence: [String]
    public var bpm: Double?
    public var meter: String?

    public init(
        arrangementId: String,
        name: String? = nil,
        chordChart: String? = nil,
        lyrics: String? = nil,
        chordChartKey: String? = nil,
        sequence: [String] = [],
        bpm: Double? = nil,
        meter: String? = nil
    ) {
        self.arrangementId = arrangementId
        self.name = name
        self.chordChart = chordChart
        self.lyrics = lyrics
        self.chordChartKey = chordChartKey
        self.sequence = sequence
        self.bpm = bpm
        self.meter = meter
    }

    public var hasChart: Bool {
        !(chordChart ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var hasLyrics: Bool {
        !(lyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
