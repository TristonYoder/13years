// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

public enum PCOTeamPositionLink {
    public static let separator = " \u{203A} "

    public static func reference(team: String?, position: String?) -> String? {
        let team = clean(team)
        let position = clean(position)
        switch (team, position) {
        case let (team?, position?): return team + separator + position
        case let (nil, position?): return position
        case let (team?, nil): return team
        case (nil, nil): return nil
        }
    }

    public static func parse(_ reference: String) -> (team: String?, position: String?) {
        if let range = reference.range(of: separator) {
            return (clean(String(reference[..<range.lowerBound])), clean(String(reference[range.upperBound...])))
        }
        return (nil, clean(reference))
    }

    fileprivate static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

extension PCOPlanPersonInfo {
    public var teamPositionReference: String? {
        PCOTeamPositionLink.reference(team: teamName, position: positionName)
    }

    public var isDeclined: Bool { status.uppercased() == "D" }
    public var isConfirmed: Bool { status.uppercased() == "C" }
}

extension PCONeededPositionInfo {
    public var teamPositionReference: String? {
        PCOTeamPositionLink.reference(team: teamName, position: positionName)
    }
}

extension PCOPlanContext {
    public var teamPositionReferences: [String] {
        var seen = Set<String>()
        var result: [String] = []
        let all = team.compactMap(\.teamPositionReference) + neededPositions.compactMap(\.teamPositionReference)
        for reference in all where seen.insert(reference).inserted {
            result.append(reference)
        }
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public func assignedPeople(forPosition reference: String) -> [PCOPlanPersonInfo] {
        let candidates = team.filter { $0.teamPositionReference == reference && !$0.isDeclined }
        let confirmed = candidates.filter(\.isConfirmed)
        return confirmed.isEmpty ? candidates : confirmed
    }

    public func personName(forPosition reference: String) -> String? {
        let people = assignedPeople(forPosition: reference)
        guard !people.isEmpty else { return nil }
        let full = people.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let firstNames = full.map { $0.split(separator: " ").first.map(String.init) ?? $0 }
        let names = Set(firstNames).count == firstNames.count ? firstNames : full
        return names.isEmpty ? nil : names.joined(separator: " & ")
    }
}
