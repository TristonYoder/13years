// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation

@MainActor
final class PagerScreenshotTour: ScreenshotTourClient {
    struct Scene {
        var role = "Host"
        var state: CueState = .off
        var layout: PagerResolvedLayout = .portrait
        var cueDisplay: CueDisplayStyle = .outline
        var messages = false
    }

    let runner: ScreenshotTour
    let engine: CueEngine
    private var started = false
    private var roles: [RoleCue] = []
    private var activeItem: PCOTimerItem?
    private var nextItem: PCOTimerItem?
    private var clockFormat: ClockFormat?
    private var heartbeat: Task<Void, Never>?
    private let senderId = "screenshot-tour-producer"

    static var current: PagerScreenshotTour?

    static func start(engine: CueEngine) {
        guard let options = ScreenshotTourOptions.current else { return }
        if current == nil {
            current = PagerScreenshotTour(options: options, engine: engine)
        }
        current?.start()
    }

    init(options: ScreenshotTourOptions, engine: CueEngine) {
        self.runner = ScreenshotTour(options: options)
        self.engine = engine
    }

    func start() {
        guard !started else { return }
        started = true
        for key in [PagerLayoutChoice.storageKey, CueDisplayStyle.storageKey, PagerDetailsSplit.storageKey, "pagerSelectedRoleId"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        Task {
            await runner.run(setUp: { [unowned self] in
                loadDocument()
            }, steps: { [unowned self] in
                steps()
            })
        }
    }

    private func loadDocument() {
        guard let url = runner.options.documentURL, let document = try? ProducerDocument.read(from: url) else { return }
        clockFormat = document.settings.clockFormat
        let selectable = document.planItems.indices.filter { !document.planItems[$0].isHeader }
        func following(_ index: Int) -> Int? { selectable.first { $0 > index } }
        let featured = selectable.first { index in
            guard document.planItems[index].itemDetailsSource(includingDescription: false) != nil, let next = following(index) else { return false }
            return document.planItems[next].itemType != document.planItems[index].itemType
        } ?? selectable.first { $0 >= document.activeItemIndex } ?? selectable.first
        guard let featured else { return }
        var item = document.planItems[featured]
        item.elapsedSeconds = item.lengthInSeconds > 120 ? item.lengthInSeconds - 88 : item.lengthInSeconds / 2
        item.isRunning = false
        activeItem = item
        nextItem = following(featured).map { document.planItems[$0] }
        serveItemDetails(document.planItems)
        roles = document.roles.map { role in
            var role = role
            role.state = .off
            if role.assignedNoteCategories.isEmpty {
                let categories = item.notes.keys
                if categories.contains(role.name) {
                    role.assignedNoteCategories = [role.name]
                } else if let director = categories.first(where: { $0.localizedCaseInsensitiveContains("director") }) {
                    role.assignedNoteCategories = [director]
                }
            }
            return role
        }
    }

    private func serveItemDetails(_ items: [PCOTimerItem]) {
        var bodies: [String: Data] = [:]
        for item in items where !item.isHeader {
            bodies[item.id] = try? ControlAPIJSON.encoder.encode(item)
        }
        let served = bodies
        PagerItemDetailsTransport.standard = { url in
            guard let body = served[url.lastPathComponent] else { return (404, Data()) }
            return (200, body)
        }
        engine.connectedProducerHost = Self.producerHost
    }

    static let producerHost = "producer.local"

    func hasRole(named name: String) -> Bool {
        roles.contains { $0.name == name }
    }

    func roleId(named name: String) -> String? {
        roles.first { $0.name == name }?.id ?? roles.first?.id
    }

    var hasDetailsRole: Bool {
        roles.contains { $0.pagerFields?.contains(.itemDetails) == true } && activeItem?.itemDetailsSource(includingDescription: false) != nil
    }

    var detailsRoleName: String? {
        roles.first { $0.pagerFields?.contains(.itemDetails) == true }?.name
    }

    func apply(_ scene: Scene) throws {
        guard let selected = roleId(named: scene.role), activeItem != nil else {
            throw TourUIError.skipped("the screenshot document has no roles or run sheet items")
        }
        UserDefaults.standard.set(selected, forKey: "pagerSelectedRoleId")
        UserDefaults.standard.set(scene.cueDisplay.rawValue, forKey: CueDisplayStyle.storageKey)
        UserDefaults.standard.set(layoutChoice(for: scene.layout).rawValue, forKey: PagerLayoutChoice.storageKey)
        for index in roles.indices {
            roles[index].state = roles[index].id == selected ? scene.state : .off
        }
        engine.connectedMasterName = "13 Years Producer"
        send(cueUpdate())
        if scene.messages {
            var packet = cueUpdate()
            packet.messages = messages(for: selected)
            send(packet)
        } else if !engine.recentMessages.isEmpty {
            send(CuePacket(type: .clearMessages, senderId: senderId))
        }
        startHeartbeat()
    }

    private func layoutChoice(for layout: PagerResolvedLayout) -> PagerLayoutChoice {
        #if os(iOS) || os(tvOS)
        return layout == .lowerThird ? .lowerThird : .automatic
        #else
        return .automatic
        #endif
    }

    private func cueUpdate() -> CuePacket {
        let fields = Set(roles.flatMap { $0.pagerFields ?? [] })
        var packet = CuePacket(type: .cueUpdate, senderId: senderId, roleCues: roles, timerItem: activeItem?.broadcastTrimmed(fields: fields))
        packet.nextItem = nextItem.map { CueNextItem(item: $0, noteCategories: Set(roles.flatMap(\.assignedNoteCategories)), pagerFields: fields) }
        packet.utcOffsetSeconds = TimeZone.current.secondsFromGMT()
        packet.clockFormat = clockFormat?.rawValue
        return packet
    }

    private func send(_ packet: CuePacket) {
        engine.receiveLocalPacket(packet)
    }

    private func startHeartbeat() {
        guard heartbeat == nil else { return }
        heartbeat = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                send(cueUpdate())
            }
        }
    }

    private func messages(for roleId: String) -> [InterTeamMessage] {
        let now = Date()
        let name = roles.first { $0.id == roleId }?.name ?? "Host"
        return [
            InterTeamMessage(text: "Doors are open. Places in 10.", timestamp: now.addingTimeInterval(-900)),
            InterTeamMessage(targetRoleId: roleId, text: "Mic check when you're on stage.", timestamp: now.addingTimeInterval(-600)),
            InterTeamMessage(sender: name, targetRoleId: roleId, senderRoleId: roleId, text: "Copy, standing by stage left.", timestamp: now.addingTimeInterval(-540)),
            InterTeamMessage(text: "Walk-in loop is up on the screens.", timestamp: now.addingTimeInterval(-300)),
            InterTeamMessage(targetRoleId: roleId, text: "Band is going one more chorus, hold your walk-on.", timestamp: now.addingTimeInterval(-20), isHighPriority: true)
        ]
    }
}
