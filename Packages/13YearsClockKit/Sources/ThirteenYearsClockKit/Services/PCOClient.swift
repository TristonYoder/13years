// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class PCOClient: @unchecked Sendable {
    public static let baseURL = URL(string: "https://api.planningcenteronline.com")!
    public static let upcomingPlanId = "next"

    public var tokens: OAuthTokens?
    let leaderResolver = PCOLeaderResolver()

    public init(tokens: OAuthTokens? = nil) {
        self.tokens = tokens
    }

    public struct PCOServiceType: Codable, Sendable, Identifiable, Hashable {
        public let id: String
        public let name: String
    }

    public struct PCOPlanInfo: Codable, Sendable, Identifiable, Equatable {
        public let id: String
        public let title: String
        public let dates: String?
    }

    public enum PCOPlanFilter: String, CaseIterable, Sendable {
        case future
        case past
        case noDates = "no_dates"
        case undated

        public var displayName: String {
            switch self {
            case .future: return "Upcoming"
            case .past: return "Past"
            case .noDates: return "No Dates"
            case .undated: return "Undated"
            }
        }
    }

    public struct PCOPersonInfo: Codable, Sendable {
        public let id: String
        public let name: String
    }

    public struct PCONoteCategory: Codable, Sendable, Identifiable, Hashable {
        public let id: String
        public let name: String
    }

    func applyAuthHeader(to request: inout URLRequest) {
        if let tokens, !tokens.accessToken.isEmpty {
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        }
    }

    public func fetchCurrentPerson() async throws -> PCOPersonInfo {
        var request = URLRequest(url: URL(string: "services/v2/me", relativeTo: Self.baseURL)!)
        applyAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "PCOClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated with Planning Center"])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dataObj = json?["data"] as? [String: Any]
        let attrs = dataObj?["attributes"] as? [String: Any]

        let firstLast = [attrs?["first_name"] as? String, attrs?["last_name"] as? String]
            .compactMap { $0 }
            .joined(separator: " ")
        let name = (attrs?["full_name"] as? String)
            ?? (firstLast.isEmpty ? nil : firstLast)
            ?? "PCO User"
        let id = dataObj?["id"] as? String ?? "me"

        return PCOPersonInfo(id: id, name: name)
    }

    public func fetchServiceTypes() async throws -> [PCOServiceType] {
        var request = URLRequest(url: URL(string: "services/v2/service_types", relativeTo: Self.baseURL)!)
        applyAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "PCOClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: "Couldn't reach Planning Center. Check your sign-in and try again."
            ])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dataArray = json?["data"] as? [[String: Any]] ?? []

        return dataArray.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let attrs = dict["attributes"] as? [String: Any],
                  let name = attrs["name"] as? String else { return nil }
            return PCOServiceType(id: id, name: name)
        }
    }

    public func fetchPlans(serviceTypeId: String, filter: PCOPlanFilter = .future) async throws -> [PCOPlanInfo] {
        var components = URLComponents(url: URL(string: "services/v2/service_types/\(serviceTypeId)/plans", relativeTo: Self.baseURL)!, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "filter", value: filter.rawValue)]

        var request = URLRequest(url: components.url!)
        applyAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "PCOClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: "Couldn't fetch plans from Planning Center. Check your sign-in and try again."
            ])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dataArray = json?["data"] as? [[String: Any]] ?? []

        return dataArray.compactMap { dict in
            guard let id = dict["id"] as? String, let attrs = dict["attributes"] as? [String: Any] else { return nil }
            let dates = attrs["dates"] as? String
            let title = (attrs["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? dates ?? "Untitled Plan"
            return PCOPlanInfo(id: id, title: title, dates: dates)
        }
    }

    public func fetchUpcomingPlanId(serviceTypeId: String) async throws -> String? {
        var components = URLComponents(url: URL(string: "services/v2/service_types/\(serviceTypeId)/plans", relativeTo: Self.baseURL)!, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "filter", value: PCOPlanFilter.future.rawValue),
            URLQueryItem(name: "order", value: "sort_date"),
            URLQueryItem(name: "per_page", value: "1"),
        ]

        var request = URLRequest(url: components.url!)
        applyAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "PCOClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: "Couldn't find the next upcoming plan in Planning Center. Check your sign-in and try again."
            ])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["data"] as? [[String: Any]])?.first?["id"] as? String
    }

    public static let planItemsInclude = "item_notes,item_notes.item_note_category,song,arrangement,key,media,item_times,item_assignments"

    public func fetchPlanItems(serviceTypeId: String, planId: String) async throws -> (planTitle: String, items: [PCOTimerItem]) {
        let path = "services/v2/service_types/\(serviceTypeId)/plans/\(planId)/items"
        var components = URLComponents(url: URL(string: path, relativeTo: Self.baseURL)!, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "include", value: Self.planItemsInclude),
            URLQueryItem(name: "per_page", value: "100"),
        ]

        let json = try await fetchAllPages(
            from: components.url!,
            failureMessage: "Couldn't fetch the plan from Planning Center. Check your sign-in and try again."
        )
        let parsed = Self.parsePlanItems(json, serviceTypeId: serviceTypeId, planId: planId)
        let items = await resolveLeaders(in: parsed, serviceTypeId: serviceTypeId, planId: planId)
        let planTitle = (try? await fetchPlanTitle(serviceTypeId: serviceTypeId, planId: planId)) ?? "PCO Plan #\(planId)"
        return (planTitle, items)
    }

    public func fetchPlanTitle(serviceTypeId: String, planId: String) async throws -> String {
        let url = URL(string: "services/v2/service_types/\(serviceTypeId)/plans/\(planId)", relativeTo: Self.baseURL)!
        let json = try await fetchJSON(from: url, failureMessage: "Couldn't fetch the plan from Planning Center.")
        return Self.parsePlanTitle(json, planId: planId)
    }

    public func fetchItemNoteCategories(serviceTypeId: String, planId: String) async throws -> [PCONoteCategory] {
        var components = URLComponents(url: URL(string: "services/v2/service_types/\(serviceTypeId)/plans/\(planId)/items", relativeTo: Self.baseURL)!, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "include", value: "item_notes.item_note_category")]

        var request = URLRequest(url: components.url!)
        applyAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "PCOClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: "Couldn't fetch note categories from Planning Center."
            ])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let included = json?["included"] as? [[String: Any]] ?? []

        var seen = Set<String>()
        var categories: [PCONoteCategory] = []
        for resource in included {
            guard resource["type"] as? String == "ItemNoteCategory",
                  let id = resource["id"] as? String,
                  let name = (resource["attributes"] as? [String: Any])?["name"] as? String,
                  !seen.contains(id) else { continue }
            seen.insert(id)
            categories.append(PCONoteCategory(id: id, name: name))
        }
        return categories
    }

    public func updateItemLength(serviceTypeId: String, planId: String, itemId: String, lengthInSeconds: Int) async throws {
        var request = URLRequest(url: URL(string: "services/v2/service_types/\(serviceTypeId)/plans/\(planId)/items/\(itemId)", relativeTo: Self.baseURL)!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeader(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "data": [
                "type": "Item",
                "id": itemId,
                "attributes": ["length": lengthInSeconds],
            ],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "PCOClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: "Couldn't save the new duration to Planning Center: \(String(data: data, encoding: .utf8) ?? "")"
            ])
        }
    }

    public func reorderItems(serviceTypeId: String, planId: String, itemIds: [String]) async throws {
        var request = URLRequest(url: URL(string: "services/v2/service_types/\(serviceTypeId)/plans/\(planId)/item_reorder", relativeTo: Self.baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeader(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "data": [
                "type": "PlanItemReorder",
                "attributes": ["sequence": itemIds],
            ],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "PCOClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: "Couldn't save the new order to Planning Center: \(String(data: data, encoding: .utf8) ?? "")"
            ])
        }
    }

    public func updateItemNoteContent(serviceTypeId: String, planId: String, itemId: String, noteId: String, content: String) async throws {
        var request = URLRequest(url: URL(string: "services/v2/service_types/\(serviceTypeId)/plans/\(planId)/items/\(itemId)/item_notes/\(noteId)", relativeTo: Self.baseURL)!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeader(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "data": [
                "type": "ItemNote",
                "id": noteId,
                "attributes": ["content": content],
            ],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "PCOClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: "Couldn't save the note to Planning Center: \(String(data: data, encoding: .utf8) ?? "")"
            ])
        }
    }

    @discardableResult
    public func createItemNote(serviceTypeId: String, planId: String, itemId: String, categoryId: String, content: String) async throws -> String {
        var request = URLRequest(url: URL(string: "services/v2/service_types/\(serviceTypeId)/plans/\(planId)/items/\(itemId)/item_notes", relativeTo: Self.baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeader(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "data": [
                "type": "ItemNote",
                "attributes": ["content": content],
                "relationships": [
                    "item_note_category": [
                        "data": ["type": "ItemNoteCategory", "id": categoryId],
                    ],
                ],
            ],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "PCOClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: "Couldn't create the note in Planning Center: \(String(data: data, encoding: .utf8) ?? "")"
            ])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let newId = (json?["data"] as? [String: Any])?["id"] as? String else {
            throw NSError(domain: "PCOClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Planning Center didn't return the new note's id."])
        }
        return newId
    }

    public func fetchNextPlanId(serviceTypeId: String, planId: String) async throws -> String? {
        var request = URLRequest(url: URL(string: "services/v2/service_types/\(serviceTypeId)/plans/\(planId)", relativeTo: Self.baseURL)!)
        applyAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "PCOClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: "Couldn't check Planning Center for the next service."
            ])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let relationships = (json?["data"] as? [String: Any])?["relationships"] as? [String: Any]
        let nextPlan = (relationships?["next_plan"] as? [String: Any])?["data"] as? [String: Any]
        return nextPlan?["id"] as? String
    }

    public enum PCOLiveDirection {
        case next
        case previous
    }

    public func toggleLiveControl(serviceTypeId: String, planId: String) async throws {
        try await postLiveAction(serviceTypeId: serviceTypeId, planId: planId, action: "toggle_control", failureMessage: "Couldn't take control of Planning Center Live")
    }

    public func stepLiveItem(serviceTypeId: String, planId: String, direction: PCOLiveDirection) async throws {
        let action = direction == .next ? "go_to_next_item" : "go_to_previous_item"
        try await postLiveAction(serviceTypeId: serviceTypeId, planId: planId, action: action, failureMessage: "Couldn't advance Planning Center Live")
    }

    public struct PCOCurrentItemTime: Sendable {
        public let itemId: String?
        public let planTimeId: String?
        public let liveStartAt: Date?
    }

    public struct PCOPlanTime: Codable, Sendable, Identifiable, Hashable {
        public let id: String
        public let name: String?
        public let startsAt: Date?
        public let timeType: String

        public init(id: String, name: String?, startsAt: Date?, timeType: String) {
            self.id = id
            self.name = name
            self.startsAt = startsAt
            self.timeType = timeType
        }

        public var isService: Bool { timeType == "service" }
    }

    public func fetchPlanTimes(serviceTypeId: String, planId: String) async throws -> [PCOPlanTime] {
        var request = URLRequest(url: URL(string: "services/v2/service_types/\(serviceTypeId)/plans/\(planId)/plan_times", relativeTo: Self.baseURL)!)
        applyAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "PCOClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: "Couldn't fetch the service times from Planning Center."
            ])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dataArray = json?["data"] as? [[String: Any]] ?? []
        let formatter = ISO8601DateFormatter()

        return dataArray.compactMap { dict -> PCOPlanTime? in
            guard let id = dict["id"] as? String else { return nil }
            let attrs = dict["attributes"] as? [String: Any]
            let name = (attrs?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let startsAt = (attrs?["starts_at"] as? String).flatMap { formatter.date(from: $0) }
            let timeType = attrs?["time_type"] as? String ?? "service"
            return PCOPlanTime(id: id, name: name, startsAt: startsAt, timeType: timeType)
        }
        .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
    }

    public func fetchCurrentItemTime(serviceTypeId: String, planId: String) async throws -> PCOCurrentItemTime? {
        var request = URLRequest(url: URL(string: "services/v2/service_types/\(serviceTypeId)/plans/\(planId)/live/current_item_time", relativeTo: Self.baseURL)!)
        applyAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            return nil
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "PCOClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: "Couldn't fetch Planning Center Live's current item time."
            ])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let dataObj = json?["data"] as? [String: Any] else { return nil }
        let attrs = dataObj["attributes"] as? [String: Any]
        let liveStartAt = (attrs?["live_start_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        let relationships = dataObj["relationships"] as? [String: Any]
        let itemId = ((relationships?["item"] as? [String: Any])?["data"] as? [String: Any])?["id"] as? String
        let planTimeId = ((relationships?["plan_time"] as? [String: Any])?["data"] as? [String: Any])?["id"] as? String

        return PCOCurrentItemTime(itemId: itemId, planTimeId: planTimeId, liveStartAt: liveStartAt)
    }

    private func postLiveAction(serviceTypeId: String, planId: String, action: String, failureMessage: String) async throws {
        var request = URLRequest(url: URL(string: "services/v2/service_types/\(serviceTypeId)/plans/\(planId)/live/\(action)", relativeTo: Self.baseURL)!)
        request.httpMethod = "POST"
        applyAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "PCOClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: "\(failureMessage): \(String(data: data, encoding: .utf8) ?? "")"
            ])
        }
    }
}
