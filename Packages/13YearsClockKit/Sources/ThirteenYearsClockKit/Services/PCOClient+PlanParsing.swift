// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension PCOClient {
    static let maxPages = 200

    func fetchJSON(from url: URL, failureMessage: String) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        applyAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "PCOClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: failureMessage
            ])
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    func fetchAllPages(from url: URL, failureMessage: String) async throws -> [String: Any] {
        try await Self.collectPages(from: url) { [self] pageURL in
            try await fetchJSON(from: pageURL, failureMessage: failureMessage)
        }
    }

    static func collectPages(from url: URL, fetch: (URL) async throws -> [String: Any]) async throws -> [String: Any] {
        var pages: [[String: Any]] = []
        var visited = Set<URL>()
        var current: URL? = url
        while let pageURL = current, pages.count < maxPages, visited.insert(pageURL).inserted {
            let page = try await fetch(pageURL)
            pages.append(page)
            current = nextPageURL(in: page, after: pageURL)
        }
        return mergePages(pages)
    }

    static func nextPageURL(in page: [String: Any], after current: URL) -> URL? {
        if let next = (page["links"] as? [String: Any])?["next"] as? String, let url = URL(string: next) {
            guard url.scheme == "https", url.host == current.host else { return nil }
            return url
        }
        guard let offset = ((page["meta"] as? [String: Any])?["next"] as? [String: Any])?["offset"],
              let value = (offset as? Int) ?? Int("\(offset)"),
              var components = URLComponents(url: current, resolvingAgainstBaseURL: true) else { return nil }
        var items = (components.queryItems ?? []).filter { $0.name != "offset" }
        items.append(URLQueryItem(name: "offset", value: String(value)))
        components.queryItems = items
        return components.url
    }

    static func mergePages(_ pages: [[String: Any]]) -> [String: Any] {
        guard var merged = pages.first else { return [:] }
        guard pages.count > 1 else { return merged }
        var data = merged["data"] as? [[String: Any]] ?? []
        var included = merged["included"] as? [[String: Any]] ?? []
        var seen = Set(included.compactMap(resourceKey))
        for page in pages.dropFirst() {
            data.append(contentsOf: page["data"] as? [[String: Any]] ?? [])
            for resource in page["included"] as? [[String: Any]] ?? [] {
                guard let key = resourceKey(resource), seen.insert(key).inserted else { continue }
                included.append(resource)
            }
        }
        merged["data"] = data
        merged["included"] = included
        return merged
    }

    static func resourceKey(_ resource: [String: Any]) -> String? {
        guard let type = resource["type"] as? String, let id = resource["id"] as? String else { return nil }
        return "\(type)|\(id)"
    }

    static func includedLookup(_ json: [String: Any]) -> [String: [String: Any]] {
        var lookup: [String: [String: Any]] = [:]
        for resource in json["included"] as? [[String: Any]] ?? [] {
            if let key = resourceKey(resource) { lookup[key] = resource }
        }
        return lookup
    }

    static func attributes(_ resource: [String: Any]?) -> [String: Any] {
        resource?["attributes"] as? [String: Any] ?? [:]
    }

    static func relationshipRefs(_ resource: [String: Any]?, _ name: String) -> [(type: String, id: String)] {
        let data = ((resource?["relationships"] as? [String: Any])?[name] as? [String: Any])?["data"]
        let refs: [[String: Any]]
        if let list = data as? [[String: Any]] {
            refs = list
        } else if let single = data as? [String: Any] {
            refs = [single]
        } else {
            refs = []
        }
        return refs.compactMap { ref in
            guard let type = ref["type"] as? String, let id = ref["id"] as? String else { return nil }
            return (type, id)
        }
    }

    static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    static func int(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? Double { return Int(number) }
        if let text = value as? String { return Int(text) }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let text = value as? String { return Double(text) }
        return nil
    }

    static func stringArray(_ value: Any?) -> [String] {
        (value as? [Any])?.compactMap { element in
            if let text = element as? String { return text }
            if let number = element as? Int { return String(number) }
            return nil
        } ?? []
    }

    static func themes(_ value: Any?) -> [String] {
        guard let text = value as? String else { return [] }
        return text.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        if let date = ISO8601DateFormatter().date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    static func alternateKeys(_ value: Any?) -> [String] {
        var entries: [Any] = []
        if let list = value as? [Any] {
            entries = list
        } else if let text = value as? String, let data = text.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            entries = parsed
        }
        return entries.compactMap { entry in
            if let text = entry as? String { return text.isEmpty ? nil : text }
            guard let dict = entry as? [String: Any] else { return nil }
            return string(dict["key"]) ?? string(dict["name"])
        }
    }

    static func parsePlanItems(_ json: [String: Any], serviceTypeId: String, planId: String) -> [PCOTimerItem] {
        let dataArray = json["data"] as? [[String: Any]] ?? []
        let lookup = includedLookup(json)

        var items: [PCOTimerItem] = []
        for (index, dict) in dataArray.enumerated() {
            guard let attrs = dict["attributes"] as? [String: Any] else { continue }
            let title = attrs["title"] as? String ?? "Item \(index + 1)"
            let length = attrs["length"] as? Int ?? 300
            let itemType = attrs["item_type"] as? String ?? "Item"
            let itemId = dict["id"] as? String ?? UUID().uuidString

            var notes: [String: String] = [:]
            var noteIds: [String: String] = [:]
            for ref in relationshipRefs(dict, "item_notes") {
                guard let note = lookup["\(ref.type)|\(ref.id)"] else { continue }
                let categoryRef = relationshipRefs(note, "item_note_category").first
                let categoryName = categoryRef.flatMap { string(attributes(lookup["\($0.type)|\($0.id)"])["name"]) } ?? "Notes"
                notes[categoryName] = (attributes(note)["content"] as? String) ?? ""
                noteIds[categoryName] = ref.id
            }

            items.append(PCOTimerItem(
                id: itemId,
                title: title,
                itemType: itemType,
                sequence: index + 1,
                lengthInSeconds: length,
                notes: notes,
                noteIds: noteIds,
                pcoServiceTypeId: serviceTypeId,
                pcoPlanId: planId,
                details: parseItemDetails(dict, lookup: lookup)
            ))
        }
        return items
    }

    static func parseItemDetails(_ item: [String: Any], lookup: [String: [String: Any]]) -> PCOItemDetails {
        let attrs = attributes(item)
        func related(_ name: String) -> [String: Any]? {
            relationshipRefs(item, name).first.flatMap { lookup["\($0.type)|\($0.id)"] }
        }

        var details = PCOItemDetails()
        details.description = string(attrs["description"])
        details.htmlDetails = string(attrs["html_details"])
        details.servicePosition = (attrs["service_position"] as? String).flatMap(PCOServicePosition.init(rawValue:)) ?? .during
        details.keyName = string(attrs["key_name"])
        details.customSequence = stringArray(attrs["custom_arrangement_sequence"])
        details.customSequenceShort = stringArray(attrs["custom_arrangement_sequence_short"])

        if let song = related("song"), let id = song["id"] as? String {
            let songAttrs = attributes(song)
            details.song = PCOSongInfo(
                id: id,
                title: string(songAttrs["title"]),
                author: string(songAttrs["author"]),
                copyright: string(songAttrs["copyright"]),
                ccliNumber: int(songAttrs["ccli_number"]),
                themes: themes(songAttrs["themes"])
            )
        }

        if let arrangement = related("arrangement"), let id = arrangement["id"] as? String {
            let arrAttrs = attributes(arrangement)
            details.arrangement = PCOArrangementInfo(
                id: id,
                name: string(arrAttrs["name"]),
                bpm: double(arrAttrs["bpm"]),
                meter: string(arrAttrs["meter"]),
                length: int(arrAttrs["length"]),
                sequence: stringArray(arrAttrs["sequence"]),
                sequenceShort: stringArray(arrAttrs["sequence_short"]),
                hasChordChart: arrAttrs["has_chord_chart"] as? Bool ?? false,
                hasChords: arrAttrs["has_chords"] as? Bool ?? false,
                notes: string(arrAttrs["notes"])
            )
        }

        if let key = related("key"), let id = key["id"] as? String {
            let keyAttrs = attributes(key)
            details.key = PCOKeyInfo(
                id: id,
                name: string(keyAttrs["name"]),
                startingKey: string(keyAttrs["starting_key"]),
                endingKey: string(keyAttrs["ending_key"]),
                alternateKeys: alternateKeys(keyAttrs["alternate_keys"])
            )
        }

        if let media = related("media"), let id = media["id"] as? String {
            let mediaAttrs = attributes(media)
            details.media = PCOMediaInfo(
                id: id,
                title: string(mediaAttrs["title"]),
                mediaType: string(mediaAttrs["media_type"]),
                themes: themes(mediaAttrs["themes"]),
                length: int(mediaAttrs["length"]),
                thumbnailURL: string(mediaAttrs["thumbnail_url"])
            )
        }

        details.leaders = parseItemLeaders(item, lookup: lookup)

        details.itemTimes = relationshipRefs(item, "item_times").compactMap { ref in
            guard let resource = lookup["\(ref.type)|\(ref.id)"] else { return nil }
            let timeAttrs = attributes(resource)
            return PCOItemTimeInfo(
                id: ref.id,
                planTimeId: relationshipRefs(resource, "plan_time").first?.id,
                length: int(timeAttrs["length"]),
                lengthOffset: int(timeAttrs["length_offset"]),
                exclude: timeAttrs["exclude"] as? Bool ?? false,
                liveStartAt: date(timeAttrs["live_start_at"]),
                liveEndAt: date(timeAttrs["live_end_at"])
            )
        }
        return details
    }

    static func parseItemLeaders(_ item: [String: Any], lookup: [String: [String: Any]]) -> [PCOItemLeader] {
        var seen = Set<String>()
        var leaders: [PCOItemLeader] = []
        for ref in relationshipRefs(item, "item_assignments") {
            guard let assignment = lookup["\(ref.type)|\(ref.id)"],
                  let target = relationshipRefs(assignment, "assignable").first else { continue }
            let kind = (string(attributes(assignment)["assignable_type"]) ?? target.type).lowercased()
            let leader: PCOItemLeader
            if kind == "person" {
                leader = PCOItemLeader(personId: target.id, name: "")
            } else if kind == "teamposition" {
                leader = PCOItemLeader(teamPositionId: target.id, name: "")
            } else {
                continue
            }
            if seen.insert(leader.id).inserted { leaders.append(leader) }
        }
        return leaders
    }

    static func httpsURLString(_ value: Any?) -> String? {
        guard let text = string(value), let url = URL(string: text), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return text
    }

    static func parsePersonIdentity(_ json: [String: Any]) -> PCOLeaderIdentity? {
        let attrs = attributes(json["data"] as? [String: Any])
        guard let name = string(attrs["full_name"]) ?? string(attrs["first_name"]) else { return nil }
        return PCOLeaderIdentity(
            name: name,
            firstName: string(attrs["first_name"]) ?? PCOItemLeader.firstName(of: name),
            photoThumbnailURL: httpsURLString(attrs["photo_thumbnail_url"]) ?? httpsURLString(attrs["photo_url"])
        )
    }

    static func parsePlanTitle(_ json: [String: Any], planId: String) -> String {
        let attrs = attributes(json["data"] as? [String: Any])
        return string(attrs["title"]) ?? string(attrs["series_title"]) ?? string(attrs["dates"]) ?? "PCO Plan #\(planId)"
    }

    public func fetchPlanContext(serviceTypeId: String, planId: String) async throws -> PCOPlanContext {
        let base = "services/v2/service_types/\(serviceTypeId)/plans/\(planId)"
        func url(_ suffix: String, include: String?) -> URL {
            var components = URLComponents(url: URL(string: base + suffix, relativeTo: Self.baseURL)!, resolvingAgainstBaseURL: true)!
            var queryItems = [URLQueryItem(name: "per_page", value: "100")]
            if let include { queryItems.append(URLQueryItem(name: "include", value: include)) }
            components.queryItems = queryItems
            return components.url!
        }

        let plan = try await fetchJSON(from: url("", include: "series,plan_times"), failureMessage: "Couldn't fetch the plan from Planning Center.")
        let notes = try await fetchOptionalPages(url("/notes", include: "plan_note_category"), "Couldn't fetch the plan notes from Planning Center.")
        let team = try await fetchOptionalPages(url("/team_members", include: "team,declined_plan_times"), "Couldn't fetch the team from Planning Center.")
        let needed = try await fetchOptionalPages(url("/needed_positions", include: "team"), "Couldn't fetch the needed positions from Planning Center.")

        let context = Self.parsePlanContext(
            plan: plan,
            notes: notes,
            team: team,
            neededPositions: needed,
            serviceTypeId: serviceTypeId,
            planId: planId
        )
        await leaderResolver.learn(team: context.team)
        return context
    }

    func resolveLeaders(in items: [PCOTimerItem], serviceTypeId: String, planId: String) async -> [PCOTimerItem] {
        await leaderResolver.resolve(
            items,
            loadTeam: { [self] in
                let url = URL(string: "services/v2/service_types/\(serviceTypeId)/plans/\(planId)/team_members?per_page=100&include=team", relativeTo: Self.baseURL)!
                let team = try await fetchAllPages(from: url, failureMessage: "Couldn't fetch the team from Planning Center.")
                return Self.parseTeam(team)
            },
            fetchPerson: { [self] id in
                let url = URL(string: "services/v2/people/\(id)", relativeTo: Self.baseURL)!
                return Self.parsePersonIdentity(try await fetchJSON(from: url, failureMessage: "Couldn't fetch a person from Planning Center."))
            },
            fetchPosition: { [self] id in
                let url = URL(string: "services/v2/service_types/\(serviceTypeId)/team_positions/\(id)", relativeTo: Self.baseURL)!
                let json = try await fetchJSON(from: url, failureMessage: "Couldn't fetch a team position from Planning Center.")
                return Self.string(Self.attributes(json["data"] as? [String: Any])["name"])
            }
        )
    }

    private func fetchOptionalPages(_ url: URL, _ failureMessage: String) async throws -> [String: Any] {
        do {
            return try await fetchAllPages(from: url, failureMessage: failureMessage)
        } catch let error as NSError where error.domain == "PCOClient" && (error.code == 403 || error.code == 404) {
            return [:]
        }
    }

    static func parsePlanContext(
        plan: [String: Any],
        notes: [String: Any],
        team: [String: Any],
        neededPositions: [String: Any],
        serviceTypeId: String,
        planId: String,
        fetchedAt: Date = Date()
    ) -> PCOPlanContext {
        let planResource = plan["data"] as? [String: Any]
        let attrs = attributes(planResource)
        let planLookup = includedLookup(plan)

        var times: [PCOPlanTimeInfo] = []
        let timeRefs = relationshipRefs(planResource, "plan_times")
        let timeResources: [[String: Any]] = timeRefs.isEmpty
            ? (plan["included"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "PlanTime" }
            : timeRefs.compactMap { planLookup["\($0.type)|\($0.id)"] }
        for resource in timeResources {
            guard let id = resource["id"] as? String else { continue }
            let timeAttrs = attributes(resource)
            times.append(PCOPlanTimeInfo(
                id: id,
                name: string(timeAttrs["name"]),
                timeType: string(timeAttrs["time_type"]) ?? "service",
                startsAt: date(timeAttrs["starts_at"]),
                endsAt: date(timeAttrs["ends_at"])
            ))
        }
        times.sort { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }

        let noteInfos: [PCOPlanNoteInfo] = (notes["data"] as? [[String: Any]] ?? []).compactMap { resource in
            guard let id = resource["id"] as? String else { return nil }
            let noteAttrs = attributes(resource)
            let content = (noteAttrs["content"] as? String) ?? ""
            guard !content.isEmpty else { return nil }
            return PCOPlanNoteInfo(id: id, category: string(noteAttrs["category_name"]), content: content)
        }

        let people = parseTeam(team)

        let neededLookup = includedLookup(neededPositions)
        let needed: [PCONeededPositionInfo] = (neededPositions["data"] as? [[String: Any]] ?? []).map { resource in
            let neededAttrs = attributes(resource)
            let teamName = relationshipRefs(resource, "team").first.flatMap { string(attributes(neededLookup["\($0.type)|\($0.id)"])["name"]) }
            return PCONeededPositionInfo(
                teamName: teamName,
                positionName: string(neededAttrs["team_position_name"]),
                quantity: int(neededAttrs["quantity"]) ?? 1,
                planTimeIds: relationshipRefs(resource, "time").map(\.id)
            )
        }

        return PCOPlanContext(
            planId: planId,
            serviceTypeId: serviceTypeId,
            title: string(attrs["title"]) ?? string(attrs["series_title"]) ?? string(attrs["dates"]),
            seriesTitle: string(attrs["series_title"]),
            dates: string(attrs["dates"]),
            totalLength: int(attrs["total_length"]),
            planningCenterURL: string(attrs["planning_center_url"]),
            notes: noteInfos,
            times: times,
            team: people,
            neededPositions: needed,
            fetchedAt: fetchedAt
        )
    }

    static func parseTeam(_ team: [String: Any]) -> [PCOPlanPersonInfo] {
        let teamLookup = includedLookup(team)
        return (team["data"] as? [[String: Any]] ?? []).compactMap { resource in
            guard let id = resource["id"] as? String else { return nil }
            let personAttrs = attributes(resource)
            let teamName = relationshipRefs(resource, "team").first.flatMap { string(attributes(teamLookup["\($0.type)|\($0.id)"])["name"]) }
            return PCOPlanPersonInfo(
                id: id,
                personId: relationshipRefs(resource, "person").first?.id,
                name: string(personAttrs["name"]) ?? "Unknown",
                teamName: teamName,
                positionName: string(personAttrs["team_position_name"]),
                status: normalizedStatus(personAttrs["status"]),
                declinedPlanTimeIds: relationshipRefs(resource, "declined_plan_times").map(\.id),
                photoThumbnailURL: httpsURLString(personAttrs["photo_thumbnail"])
            )
        }
    }

    static func normalizedStatus(_ value: Any?) -> String {
        switch (value as? String)?.uppercased() {
        case "C", "CONFIRMED": return "C"
        case "D", "DECLINED": return "D"
        default: return "U"
        }
    }
}
