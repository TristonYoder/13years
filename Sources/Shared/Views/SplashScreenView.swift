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
            ? AppPalette.brandGroundDark
            : AppPalette.brandGroundLight
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
                        .font(.system(size: 13, weight: .medium))
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

private struct SplashScreenModifier: ViewModifier {
    let isPresented: Bool
    let status: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    SplashScreenView(status: status)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: isPresented)
    }
}

public extension View {
    func splashScreen(isPresented: Bool, status: String? = nil) -> some View {
        modifier(SplashScreenModifier(isPresented: isPresented, status: status))
    }
}

@MainActor
public final class SplashCoordinator: ObservableObject {
    @Published public private(set) var isPresented = true

    public static let minimumDisplay: TimeInterval = 2.0
    public static let shortDisplay: TimeInterval = 0.6
    private static let launchedBeforeKey = "hasLaunchedBefore"

    public static func displayDuration(isFirstLaunch: Bool, reduceMotion: Bool) -> TimeInterval {
        isFirstLaunch && !reduceMotion ? minimumDisplay : shortDisplay
    }

    private static var systemReduceMotion: Bool {
        #if os(macOS)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #elseif os(watchOS)
        false
        #else
        UIAccessibility.isReduceMotionEnabled
        #endif
    }

    private static func resolvedDisplay(defaults: UserDefaults) -> TimeInterval {
        let isFirst = !defaults.bool(forKey: launchedBeforeKey)
        defaults.set(true, forKey: launchedBeforeKey)
        return displayDuration(isFirstLaunch: isFirst, reduceMotion: systemReduceMotion)
    }

    private let displayDuration: TimeInterval

    private var isReady = false
    private var minimumElapsed = false

    private let autoStart: Bool
    private var hasStartedClock = false

    public init(autoStart: Bool = true, defaults: UserDefaults = .standard) {
        self.autoStart = autoStart
        self.displayDuration = autoStart ? Self.resolvedDisplay(defaults: defaults) : Self.minimumDisplay
    }

    public func markReady() {
        isReady = true
        startClockIfNeeded()
        dismissIfDone()
    }

    private func startClockIfNeeded() {
        guard autoStart, !hasStartedClock else { return }
        hasStartedClock = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.displayDuration ?? Self.shortDisplay) * 1_000_000_000))
            self?.minimumElapsed = true
            self?.dismissIfDone()
        }
    }

    private func dismissIfDone() {
        guard minimumElapsed, isReady, isPresented else { return }
        isPresented = false
    }
}
