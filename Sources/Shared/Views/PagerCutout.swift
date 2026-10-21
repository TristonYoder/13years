// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(iOS)
import SwiftUI
import UIKit

struct PagerCutout: Equatable {
    enum Side: Equatable {
        case top, leading, trailing
    }

    let notchWidth: CGFloat
    let side: Side

    @MainActor
    static func current(safe: EdgeInsets, size: CGSize) -> PagerCutout? {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return nil }
        let landscape = size.width > size.height
        let depth = landscape ? max(safe.leading, safe.trailing) : safe.top
        guard depth >= 40, depth < 54 else { return nil }
        let width = notchWidth(model: modelIdentifier())
        guard landscape else { return PagerCutout(notchWidth: width, side: .top) }
        switch interfaceOrientation() {
        case .landscapeRight: return PagerCutout(notchWidth: width, side: .leading)
        case .landscapeLeft: return PagerCutout(notchWidth: width, side: .trailing)
        default: return nil
        }
    }

    static func notchWidth(model: String) -> CGFloat {
        if model.hasPrefix("iPhone13,") { return 210 }
        if ["iPhone10,", "iPhone11,", "iPhone12,"].contains(where: model.hasPrefix) { return 209 }
        return 162
    }

    private static func modelIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    @MainActor
    private static func interfaceOrientation() -> UIInterfaceOrientation {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.effectiveGeometry.interfaceOrientation ?? .unknown
    }

    func hole(in bounds: CGRect) -> (rect: CGRect, radius: CGFloat) {
        let along = notchWidth
        let depth: CGFloat = 52
        let offset: CGFloat = -22
        let radius: CGFloat = 21
        switch side {
        case .top:
            return (CGRect(x: bounds.midX - along / 2, y: bounds.minY + offset, width: along, height: depth), radius)
        case .leading:
            return (CGRect(x: bounds.minX + offset, y: bounds.midY - along / 2, width: depth, height: along), radius)
        case .trailing:
            return (CGRect(x: bounds.maxX - offset - depth, y: bounds.midY - along / 2, width: depth, height: along), radius)
        }
    }
}

struct PagerCutoutBand: Shape {
    let cutout: PagerCutout
    let thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        let (hole, radius) = cutout.hole(in: rect)
        let outer = hole.insetBy(dx: -thickness, dy: -thickness)
        return Path(roundedRect: outer, cornerRadius: radius + thickness, style: .continuous)
    }
}
#endif
