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

    public static func clock(_ style: Font.TextStyle = .body, weight: Font.Weight = .medium) -> Font {
        inter(size: pointSize(for: style), weight: weight).monospacedDigit()
    }

    private static func pointSize(for style: Font.TextStyle) -> CGFloat {
        #if os(macOS)
        switch style {
        case .largeTitle: return 26
        case .title: return 22
        case .title2: return 17
        case .title3: return 15
        case .headline, .body: return 13
        case .callout: return 12
        case .subheadline: return 11
        case .footnote: return 10
        case .caption: return 10
        case .caption2: return 10
        @unknown default: return 13
        }
        #else
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
        #endif
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
