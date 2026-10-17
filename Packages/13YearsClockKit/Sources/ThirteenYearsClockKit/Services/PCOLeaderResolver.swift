// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

struct PCOLeaderIdentity: Equatable, Sendable {
    var name: String
    var firstName: String
    var photoThumbnailURL: String?
}

actor PCOLeaderResolver {
    static let maxConcurrentFetches = 4

    private var people: [String: PCOLeaderIdentity] = [:]
    private var positions: [String: String] = [:]
    private var missingPeople = Set<String>()
    private var missingPositions = Set<String>()

    func learn(team: [PCOPlanPersonInfo]) {
        for member in team {
            guard let personId = member.personId, people[personId] == nil, !member.name.isEmpty else { continue }
            people[personId] = PCOLeaderIdentity(
                name: member.name,
                firstName: PCOItemLeader.firstName(of: member.name),
                photoThumbnailURL: member.photoThumbnailURL
            )
        }
    }

    func resolve(
        _ items: [PCOTimerItem],
        loadTeam: @Sendable () async throws -> [PCOPlanPersonInfo],
        fetchPerson: @escaping @Sendable (String) async throws -> PCOLeaderIdentity?,
        fetchPosition: @escaping @Sendable (String) async throws -> String?
    ) async -> [PCOTimerItem] {
        let wantedPeople = Set(items.flatMap { $0.details?.leaders ?? [] }.compactMap(\.personId))
        let wantedPositions = Set(items.flatMap { $0.details?.leaders ?? [] }.compactMap(\.teamPositionId))
        guard !wantedPeople.isEmpty || !wantedPositions.isEmpty else { return items }

        if !wantedPeople.isSubset(of: Set(people.keys).union(missingPeople)), let team = try? await loadTeam() {
            learn(team: team)
        }

        let unknownPeople = wantedPeople.subtracting(people.keys).subtracting(missingPeople).sorted()
        let fetchedPeople = await fetchAll(unknownPeople, fetchPerson)
        for (id, outcome) in fetchedPeople {
            switch outcome {
            case .found(let identity): people[id] = identity
            case .missing: missingPeople.insert(id)
            case .failed: break
            }
        }

        let unknownPositions = wantedPositions.subtracting(positions.keys).subtracting(missingPositions).sorted()
        let fetchedPositions = await fetchAll(unknownPositions, fetchPosition)
        for (id, outcome) in fetchedPositions {
            switch outcome {
            case .found(let name): positions[id] = name
            case .missing: missingPositions.insert(id)
            case .failed: break
            }
        }

        return items.map { item in
            guard var details = item.details, !details.leaders.isEmpty else { return item }
            details.leaders = details.leaders.compactMap(resolved)
            var copy = item
            copy.details = details
            return copy
        }
    }

    private func resolved(_ leader: PCOItemLeader) -> PCOItemLeader? {
        if !leader.name.isEmpty { return leader }
        if let personId = leader.personId {
            guard let identity = people[personId] else { return nil }
            return PCOItemLeader(personId: personId, name: identity.name, firstName: identity.firstName, photoThumbnailURL: identity.photoThumbnailURL)
        }
        if let positionId = leader.teamPositionId {
            guard let name = positions[positionId] else { return nil }
            return PCOItemLeader(teamPositionId: positionId, name: name, firstName: name)
        }
        return nil
    }

    private enum Outcome<Value: Sendable>: Sendable {
        case found(Value)
        case missing
        case failed
    }

    private func fetchAll<Value: Sendable>(
        _ ids: [String],
        _ fetch: @escaping @Sendable (String) async throws -> Value?
    ) async -> [String: Outcome<Value>] {
        var results: [String: Outcome<Value>] = [:]
        var index = 0
        while index < ids.count {
            let batch = Array(ids[index..<min(index + Self.maxConcurrentFetches, ids.count)])
            index += batch.count
            await withTaskGroup(of: (String, Outcome<Value>).self) { group in
                for id in batch {
                    group.addTask {
                        do {
                            if let value = try await fetch(id) { return (id, .found(value)) }
                            return (id, .missing)
                        } catch let error as NSError where error.domain == "PCOClient" && (error.code == 403 || error.code == 404) {
                            return (id, .missing)
                        } catch {
                            return (id, .failed)
                        }
                    }
                }
                for await (id, outcome) in group { results[id] = outcome }
            }
        }
        return results
    }
}
