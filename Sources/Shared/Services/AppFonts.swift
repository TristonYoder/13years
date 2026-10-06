// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import CoreText
import Foundation

public enum AppFonts {
    public static let interPostScriptNames = [
        "Inter-Regular", "Inter-Medium", "Inter-SemiBold",
        "Inter-Bold", "Inter-ExtraBold", "Inter-Black"
    ]

    public static let spaceGroteskPostScriptName = "SpaceGrotesk-Bold"

    private static var didRegister = false

    public static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true

        for name in interPostScriptNames + [spaceGroteskPostScriptName] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                AppLog.cue.error("AppFonts: bundled font \(name, privacy: .public).ttf not found — check Sources/Shared/Resources/Fonts and project.yml")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                AppLog.cue.error("AppFonts: failed to register \(name, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }
}
