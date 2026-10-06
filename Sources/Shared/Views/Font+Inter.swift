// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI
import CoreText

extension Font {
    public static func inter(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let attributes: [CFString: Any] = [
            kCTFontNameAttribute: interPostScriptName(for: weight) as CFString,
            kCTFontFeatureSettingsAttribute: [
                [
                    kCTFontOpenTypeFeatureTag: "zero" as CFString,
                    kCTFontOpenTypeFeatureValue: 1,
                ] as CFDictionary
            ],
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let ctFont = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        return Font(ctFont)
    }

    private static func interPostScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .black: return "Inter-Black"
        case .heavy: return "Inter-ExtraBold"
        case .bold: return "Inter-Bold"
        case .semibold: return "Inter-SemiBold"
        case .medium: return "Inter-Medium"
        default: return "Inter-Regular"
        }
    }
}
