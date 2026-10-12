// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS) || os(iOS)
import SwiftUI

struct LauncherActions {
    var newDocument: () -> Void
    var newFromTemplate: () -> Void
    var open: () -> Void
    var openRecent: (URL) -> Void
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

            VStack(spacing: 28) {
                header

                HStack(spacing: 12) {
                    actionCard(title: "New", subtitle: "A blank service", systemImage: "plus") {
                        actions.newDocument()
                    }
                    actionCard(title: "From Template", subtitle: "Start from a saved layout", systemImage: "doc.on.doc") {
                        actions.newFromTemplate()
                    }
                    actionCard(title: "Open…", subtitle: "An existing file", systemImage: "folder") {
                        actions.open()
                    }
                }

                recents
            }
            .padding(36)
            .frame(width: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(colorScheme == .dark ? 0.08 : 0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 30, y: 14)
        }
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
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
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
                Text("Files you open or save will show up here.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(recentURLs, id: \.self) { url in
                            RecentRow(url: url) { actions.openRecent(url) }
                        }
                    }
                }
                .frame(height: min(CGFloat(recentURLs.count) * 54, 240))
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
                    Text(url.deletingPathExtension().lastPathComponent)
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
