// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
import SwiftUI

public enum ScreenshotTourSignal {
    public static let notification = Notification.Name("dev.7co.13years.screenshotTourSignal")
    public static let targetKey = "target"

    public static func post(_ name: String, target: String? = nil) {
        NotificationCenter.default.post(name: notification, object: name, userInfo: target.map { [targetKey: $0] })
    }
}

extension View {
    func onScreenshotTourSignal(_ name: String, target: String? = nil, perform: @escaping (String?) -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: ScreenshotTourSignal.notification)) { note in
            guard note.object as? String == name else { return }
            let sent = note.userInfo?[ScreenshotTourSignal.targetKey] as? String
            if let target, sent != target { return }
            perform(sent)
        }
    }
}
