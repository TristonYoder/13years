// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Combine
import Foundation

@MainActor
final class PagerRoleByName {
    static let nameKey = "pagerRoleName"
    static let selectedRoleKey = "pagerSelectedRoleId"

    private var cancellable: AnyCancellable?

    init(engine: CueEngine) {
        cancellable = engine.$roles
            .receive(on: DispatchQueue.main)
            .sink { roles in
                MainActor.assumeIsolated { Self.apply(roles: roles) }
            }
    }

    static func apply(roles: [RoleCue], defaults: UserDefaults = .standard) {
        guard let wanted = normalized(defaults.string(forKey: nameKey)), !wanted.isEmpty,
              let role = roles.first(where: { normalized($0.name) == wanted }),
              defaults.string(forKey: selectedRoleKey) != role.id else { return }
        defaults.set(role.id, forKey: selectedRoleKey)
    }

    private static func normalized(_ name: String?) -> String? {
        name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
