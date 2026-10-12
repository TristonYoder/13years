// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS) || os(iOS)
import SwiftUI

struct LauncherActions {
    var newDocument: () -> Void
    var newFromTemplate: () -> Void
    var open: () -> Void
    var openRecent: (URL) -> Void
    var connect: () -> Void
    var refreshRecents: () -> Void = {}
}

struct LauncherView: View {
    let recentURLs: [URL]
    let actions: LauncherActions
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            launcherGround
                .overlay(
                    RadialGradient(
                        colors: [Color.purple.opacity(colorScheme == .dark ? 0.28 : 0.14), .clear],
                        center: .top,
                        startRadius: 40,
                        endRadius: 620
                    )
                )
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    panel
                        .frame(maxWidth: 640)
                        .padding(24)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear { actions.refreshRecents() }
    }

    private var panel: some View {
        VStack(spacing: 28) {
            header

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { cards }
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 12) {
                    HStack(spacing: 12) { newCards }
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) { openCards }
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 12) { cards }
            }

            recents
        }
        .padding(36)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.08 : 0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 30, y: 14)
    }

    @ViewBuilder
    private var newCards: some View {
        actionCard(title: "New Document…", subtitle: "A blank service", systemImage: "plus") {
            actions.newDocument()
        }
        actionCard(title: "From Template", subtitle: "Start from a saved layout", systemImage: "doc.on.doc") {
            actions.newFromTemplate()
        }
    }

    @ViewBuilder
    private var openCards: some View {
        actionCard(title: "Open…", subtitle: "An existing document", systemImage: "folder") {
            actions.open()
        }
        actionCard(title: "Connect To…", subtitle: "Control another Producer", systemImage: "dot.radiowaves.left.and.right") {
            actions.connect()
        }
    }

    @ViewBuilder
    private var cards: some View {
        newCards
        openCards
    }

    private var launcherGround: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    private var header: some View {
        VStack(spacing: 12) {
            StoplightMarkView(palette: colorScheme == .dark ? .dark : .light)
                .frame(height: 54)
            Text("13 Years Producer")
                .font(.system(size: 26, weight: .bold))
            Text("Start something new, or pick up where you left off.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func actionCard(title: String, subtitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(spacing: 2) {
                    Text(title).font(.headline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
            .frame(minWidth: 120, idealWidth: 120, maxWidth: .infinity, minHeight: 132, maxHeight: .infinity)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(LauncherCardButtonStyle())
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
                .padding(.horizontal, 4)

            if recentURLs.isEmpty {
                Text("Documents you open or save will show up here.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(recentURLs, id: \.self) { url in
                            RecentRow(url: url) { actions.openRecent(url) }
                        }
                    }
                }
                .frame(minHeight: 54, maxHeight: min(CGFloat(recentURLs.count) * 54, 240))
            }
        }
    }
}

private struct LauncherCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct RecentRow: View {
    let url: URL
    let action: () -> Void
    @State private var isHovering = false

    private var folder: String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    private var modified: Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(RecentDocuments.title(for: url))
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(folder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 8)
                if let modified {
                    Text(modified, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(url.path)
    }
}
#endif
