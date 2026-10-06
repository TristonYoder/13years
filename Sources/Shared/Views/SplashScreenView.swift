// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct SplashScreenView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let status: String?

    public init(status: String? = nil) {
        self.status = status
    }

    public static func ground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0x10 / 255, green: 0x10 / 255, blue: 0x14 / 255)
            : Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF3 / 255)
    }

    public var body: some View {
        let palette = StoplightMarkView.Palette.matching(colorScheme)

        ZStack {
            Self.ground(for: colorScheme)
                .ignoresSafeArea()

            SkeletonLoaderView(ink: palette.ink)

            VStack(spacing: 22) {
                StoplightMarkView(palette: palette)
                    .frame(maxWidth: 200)
                    .padding(.horizontal, 48)

                if let status {
                    Text(status)
                        .font(.inter(size: 13, weight: .medium))
                        .foregroundStyle(palette.ink.opacity(0.55))
                        .transition(.opacity)
                        .id(status)
                }
            }
            .padding(80)
            .background {
                let ground = Self.ground(for: colorScheme)
                RadialGradient(
                    stops: [
                        .init(color: ground, location: 0.0),
                        .init(color: ground, location: 0.5),
                        .init(color: ground.opacity(0.85), location: 0.72),
                        .init(color: ground.opacity(0), location: 1.0),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 300
                )
            }
        }
    }
}

public extension View {
    func splashScreen(isPresented: Bool, status: String? = nil) -> some View {
        overlay {
            if isPresented {
                SplashScreenView(status: status)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: isPresented)
    }
}

@MainActor
public final class SplashCoordinator: ObservableObject {
    @Published public private(set) var isPresented = true

    public static let minimumDisplay: TimeInterval = 2.0

    private var isReady = false
    private var minimumElapsed = false

    public init(autoStart: Bool = true) {
        guard autoStart else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.minimumDisplay * 1_000_000_000))
            self?.minimumElapsed = true
            self?.dismissIfDone()
        }
    }

    public func markReady() {
        isReady = true
        dismissIfDone()
    }

    private func dismissIfDone() {
        guard minimumElapsed, isReady, isPresented else { return }
        isPresented = false
    }
}
