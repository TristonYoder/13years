// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

extension CueEngine {
    public func setPCOTeamPosition(forRoleId roleId: String, _ reference: String?) {
        let normalized = reference?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        if isRemoteMirror {
            remoteCommands?.send(.roleUpdate(id: roleId, body: RemoteCommand.body(["pcoTeamPosition": normalized ?? ""])))
            return
        }
        guard let index = roles.firstIndex(where: { $0.id == roleId }) else { return }
        roles[index].pcoTeamPosition = normalized
        applyPCOTeamAssignments()
        broadcastState()
    }

    func applyPCOTeamAssignments() {
        guard !isRemoteMirror, let context = pcoPlanContext else { return }
        var changed = false
        for index in roles.indices {
            guard let reference = roles[index].pcoTeamPosition,
                  roles[index].personName?.isEmpty ?? true,
                  let name = context.personName(forPosition: reference) else { continue }
            roles[index].personName = name
            changed = true
        }
        if changed { broadcastState() }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
