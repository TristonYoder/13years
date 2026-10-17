// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS) || os(iOS)
import SwiftUI
import QuickLook

enum RunSheetReferenceRequest: Identifiable {
    case attachments(PCOTimerItem)
    case chart(PCOTimerItem)

    var id: String {
        switch self {
        case .attachments(let item): return "attachments-\(item.id)"
        case .chart(let item): return "chart-\(item.id)"
        }
    }
}

struct RunSheetReferencePresenter {
    var present: (RunSheetReferenceRequest) -> Void = { _ in }
}

private struct RunSheetReferencePresenterKey: EnvironmentKey {
    static let defaultValue = RunSheetReferencePresenter()
}

extension EnvironmentValues {
    var runSheetReferencePresenter: RunSheetReferencePresenter {
        get { self[RunSheetReferencePresenterKey.self] }
        set { self[RunSheetReferencePresenterKey.self] = newValue }
    }
}

extension CueEngine {
    func hasAttachments(_ item: PCOTimerItem) -> Bool {
        canBrowsePCOReference && !item.isHeader && !PCOAttachmentOwner.owners(for: item).isEmpty
    }

    func hasChart(_ item: PCOTimerItem) -> Bool {
        canBrowsePCOReference && !item.isHeader && PCOAttachmentOwner.chartReference(for: item) != nil
    }
}

struct AttachmentSource: Identifiable, Hashable {
    let owner: PCOAttachmentOwner
    let title: String

    var id: String { owner.cacheKey }

    static func sources(for item: PCOTimerItem) -> [AttachmentSource] {
        PCOAttachmentOwner.owners(for: item).map { owner in
            var title = owner.groupTitle
            let subject: String?
            switch owner {
            case .item: subject = nil
            case .song: subject = item.details?.song?.title
            case .arrangement: subject = item.details?.arrangement?.name
            case .media: subject = item.details?.media?.title
            case .plan: subject = nil
            }
            if let subject, !subject.isEmpty { title += " \u{00B7} \(subject)" }
            return AttachmentSource(owner: owner, title: title)
        }
    }
}

@MainActor
final class AttachmentOpener: ObservableObject {
    @Published var openingId: String?
    @Published var previewURL: URL?
    @Published var errorMessage: String?

    private var downloadedDirectory: URL?

    func open(_ attachment: PCOAttachmentInfo, owner: PCOAttachmentOwner, engine: CueEngine, openURL: OpenURLAction) {
        guard openingId == nil else { return }
        if let link = attachment.externalLink {
            openURL(link)
            return
        }
        openingId = attachment.id
        errorMessage = nil
        Task {
            defer { openingId = nil }
            do {
                let file = try await engine.downloadPCOAttachment(attachment, owner: owner)
                discardPreviousDownload()
                downloadedDirectory = file.deletingLastPathComponent()
                previewURL = file
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func discardPreviousDownload() {
        if let downloadedDirectory {
            try? FileManager.default.removeItem(at: downloadedDirectory)
        }
        downloadedDirectory = nil
    }
}

private struct AttachmentPreviewModifier: ViewModifier {
    @ObservedObject var opener: AttachmentOpener

    func body(content: Content) -> some View {
        content
            .quickLookPreview($opener.previewURL)
            .alert("Couldn't Open Attachment", isPresented: Binding(
                get: { opener.errorMessage != nil },
                set: { if !$0 { opener.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(opener.errorMessage ?? "")
            }
    }
}

extension View {
    func attachmentPreview(_ opener: AttachmentOpener) -> some View {
        modifier(AttachmentPreviewModifier(opener: opener))
    }
}

struct AttachmentRows: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.openURL) private var openURL
    @ObservedObject var opener: AttachmentOpener
    let owner: PCOAttachmentOwner
    var refreshToken: Date?
    var emptyText = "No attachments"

    @State private var attachments: [PCOAttachmentInfo]?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let attachments {
                if attachments.isEmpty {
                    Text(emptyText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(attachments) { attachment in
                        row(attachment)
                    }
                }
            } else if let loadError {
                VStack(alignment: .leading, spacing: 6) {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Button("Try Again") { Task { await load(force: true) } }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading\u{2026}")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: LoadKey(owner: owner, token: refreshToken)) {
            await load(force: false)
        }
    }

    private struct LoadKey: Hashable {
        let owner: PCOAttachmentOwner
        let token: Date?
    }

    private func load(force: Bool) async {
        if force { loadError = nil }
        do {
            attachments = try await engine.pcoAttachments(for: owner, forceRefresh: force)
            loadError = nil
        } catch {
            if !(error is CancellationError) {
                attachments = nil
                loadError = error.localizedDescription
            }
        }
    }

    private func row(_ attachment: PCOAttachmentInfo) -> some View {
        Button {
            opener.open(attachment, owner: owner, engine: engine, openURL: openURL)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: Self.symbol(for: attachment.kind))
                    .frame(width: 22)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.title)
                        .lineLimit(2)
                    if let detail = Self.detail(for: attachment) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if opener.openingId == attachment.id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: attachment.isLink ? "arrow.up.right.square" : "eye")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(opener.openingId != nil && opener.openingId != attachment.id)
        .accessibilityHint(attachment.isLink ? "Opens the link" : "Downloads and previews the file")
    }

    static func symbol(for kind: PCOAttachmentKind) -> String {
        switch kind {
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .audio: return "waveform"
        case .video: return "play.rectangle"
        case .document: return "doc.text"
        case .link: return "link"
        case .other: return "paperclip"
        }
    }

    static func detail(for attachment: PCOAttachmentInfo) -> String? {
        var parts: [String] = []
        if attachment.isLink, let host = attachment.externalLink?.host {
            parts.append(host)
        } else {
            if let name = attachment.filename, name != attachment.title { parts.append(name) }
            if let size = attachment.fileSize, size > 0 {
                parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }
}

struct RunSheetAttachmentsSheet: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss
    @StateObject private var opener = AttachmentOpener()
    @State private var reloadToken = Date()
    let item: PCOTimerItem

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Attachments")
                        .font(.headline)
                    Text(item.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    engine.invalidatePCOReferenceCache()
                    reloadToken = Date()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            List {
                ForEach(AttachmentSource.sources(for: item)) { source in
                    Section(source.title) {
                        AttachmentRows(opener: opener, owner: source.owner, refreshToken: reloadToken)
                    }
                }
            }
        }
        .attachmentPreview(opener)
        .onDisappear { opener.discardPreviousDownload() }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 380)
        #endif
    }
}
#endif
