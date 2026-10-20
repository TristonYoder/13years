// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import UIKit

extension ScreenshotTour {
    enum Capture {
        case screen

        static var standard: Capture { .screen }
    }

    static var windowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    static var keyWindow: UIWindow? {
        windowScene?.windows.first { $0.isKeyWindow } ?? windowScene?.windows.first
    }

    static var orientationName: String {
        #if os(tvOS)
        return "landscape"
        #else
        switch windowScene?.effectiveGeometry.interfaceOrientation {
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        case .portraitUpsideDown: return "portraitUpsideDown"
        default: return "portrait"
        }
        #endif
    }

    func waitForInterface() async {
        for _ in 0..<100 where Self.keyWindow == nil {
            await pause(0.1)
        }
        applyAppearance()
    }

    func arrangeInterface() {
        applyAppearance()
    }

    func terminate() {
        exit(0)
    }

    private func applyAppearance() {
        guard let appearance = options.appearance else { return }
        for window in Self.windowScene?.windows ?? [] {
            window.overrideUserInterfaceStyle = appearance == .dark ? .dark : .light
        }
    }

    func requestFields(for capture: Capture) throws -> [String: Any] {
        guard Self.keyWindow != nil else { throw TourUIError.notFound("window to capture") }
        return ["orientation": Self.orientationName]
    }

    func debugText() -> String {
        var lines: [String] = ["orientation=\(Self.orientationName)"]
        func visit(_ view: UIView, depth: Int) {
            guard depth < 60 else { return }
            lines.append(String(repeating: "  ", count: depth) + "\(type(of: view)) \(NSCoder.string(for: view.frame))")
            view.subviews.forEach { visit($0, depth: depth + 1) }
        }
        for window in Self.windowScene?.windows ?? [] {
            visit(window, depth: 0)
        }
        return lines.joined(separator: "\n")
    }

    func tidyBeforeCapture() async {
        Self.keyWindow?.endEditing(true)
    }

    func dismissOverlays() async {
        for _ in 0..<5 {
            guard let root = Self.keyWindow?.rootViewController, let presented = root.presentedViewController, !presented.isBeingDismissed else { return }
            presented.dismiss(animated: false)
            await pause(0.5)
        }
    }

    #if os(iOS)
    func rotate(to orientation: UIInterfaceOrientationMask) async throws {
        guard let scene = Self.windowScene else { throw TourUIError.notFound("window scene") }
        let wanted: (UIInterfaceOrientation) -> Bool = { current in
            switch current {
            case .portrait: return orientation.contains(.portrait)
            case .portraitUpsideDown: return orientation.contains(.portraitUpsideDown)
            case .landscapeLeft: return orientation.contains(.landscapeLeft)
            case .landscapeRight: return orientation.contains(.landscapeRight)
            default: return false
            }
        }
        if wanted(scene.effectiveGeometry.interfaceOrientation) { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        let refusal = RotationRefusal()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { error in
            refusal.message = error.localizedDescription
        }
        for _ in 0..<40 {
            await pause(0.1)
            if wanted(scene.effectiveGeometry.interfaceOrientation) {
                await pause(0.8)
                return
            }
        }
        let failure = refusal.message
        if let failure, UIDevice.current.userInterfaceIdiom == .pad {
            throw TourUIError.skipped("the simulator is in \(Self.orientationName.hasPrefix("landscape") ? "landscape" : "portrait") and iPadOS refused to rotate the app (\(failure)); switch the simulator to Full Screen Apps or rotate it to capture this layout")
        }
        throw TourUIError.timedOut("rotation" + (failure.map { " (\($0))" } ?? ""))
    }
    #endif

    func presentedScrollView() -> UIScrollView? {
        var root = Self.keyWindow?.rootViewController
        while let presented = root?.presentedViewController { root = presented }
        guard let view = root?.view else { return nil }
        func largest(in view: UIView) -> UIScrollView? {
            var best: UIScrollView?
            func visit(_ view: UIView) {
                if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height,
                   scroll.bounds.width * scroll.bounds.height > (best.map { $0.bounds.width * $0.bounds.height } ?? 0) {
                    best = scroll
                }
                view.subviews.forEach(visit)
            }
            visit(view)
            return best
        }
        return largest(in: view)
    }
}

#if os(iOS)
private final class RotationRefusal: @unchecked Sendable {
    var message: String?
}
#endif
