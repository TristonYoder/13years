// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

@MainActor
final class SecurityHardeningTests: XCTestCase {
    private var savedToken: String?
    private var savedHost: Any?

    override func setUp() {
        super.setUp()
        savedToken = KeychainStore.string(forKey: "plotipharProxyToken")
        savedHost = UserDefaults.standard.object(forKey: "plotipharRelayHost")
        clearPersistedState()
    }

    override func tearDown() {
        KeychainStore.setString(savedToken, forKey: "plotipharProxyToken")
        if let savedHost {
            UserDefaults.standard.set(savedHost, forKey: "plotipharRelayHost")
        } else {
            UserDefaults.standard.removeObject(forKey: "plotipharRelayHost")
        }
        clearPersistedState()
        super.tearDown()
    }

    private func clearPersistedState() {
        for key in ["persistedFlow", "persistedRoles", "recentMessages", "notificationsClearedAt", "waypoints", "serviceSchedules", "isProxyEnabled"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func makeEngine(master: Bool = true) -> CueEngine {
        CueEngine(isMasterServer: master, hostsControlAPI: false, startsNetworking: false)
    }

    private func send(_ engine: CueEngine, _ method: String, _ path: String, _ json: String? = nil) -> HTTPResponse {
        let router = ControlAPIRouter(engine: engine)
        return router.handle(HTTPRequest(method: method, path: path, body: json.map { Data($0.utf8) } ?? Data()))
    }

    private func timerItem(length: Int = 300) -> PCOTimerItem {
        PCOTimerItem(id: "t1", title: "Item", lengthInSeconds: length)
    }

    func testProducerDropsPacketsThatMutateItsState() {
        let engine = makeEngine()
        engine.roles = [RoleCue(id: "keep", name: "Keep")]
        engine.activeTimerItem = timerItem()
        let hostile = RoleCue(id: "evil", name: "Evil")
        let types: [CuePacket.PacketType] = [.cueUpdate, .timerUpdate, .pong, .clearMessages, .cueDelta, .timerAnchor, .digest, .syncReply]
        for type in types {
            var packet = CuePacket(type: type, senderId: "attacker", roleCues: [hostile], timerItem: timerItem(length: 9), messages: [InterTeamMessage(text: "x")])
            packet.cueDeltas = [CueDelta(id: "keep", state: .go, lastUpdated: Date())]
            engine.handlePacket(packet, origin: .lanServer(LANConnectionID(raw: ObjectIdentifier(engine))))
        }
        XCTAssertEqual(engine.roles.map(\.id), ["keep"])
        XCTAssertEqual(engine.roles.first?.state, .off)
        XCTAssertEqual(engine.activeTimerItem?.lengthInSeconds, 300)
        XCTAssertTrue(engine.recentMessages.isEmpty)
    }

    func testProducerStillAcceptsPagerMessagesAndAnswersPings() {
        let engine = makeEngine()
        XCTAssertTrue(engine.acceptsInbound(CuePacket(type: .ping, senderId: "p")))
        XCTAssertTrue(engine.acceptsInbound(CuePacket(type: .sync, senderId: "p")))
        let message = InterTeamMessage(sender: "Pager", text: "hello")
        engine.handlePacket(CuePacket(type: .messageBroadcast, senderId: "pager", message: message), origin: .relay)
        XCTAssertEqual(engine.recentMessages.map(\.text), ["hello"])
    }

    func testClientModeStillAcceptsProducerPackets() {
        let engine = makeEngine(master: false)
        for type in CuePacket.PacketType.allCases {
            XCTAssertTrue(engine.acceptsInbound(CuePacket(type: type, senderId: "producer")), "\(type)")
        }
        engine.handlePacket(CuePacket(type: .cueUpdate, senderId: "producer", roleCues: [RoleCue(id: "r", name: "R")]))
        XCTAssertEqual(engine.roles.map(\.id), ["r"])
    }

    func testStoredMessagesAreClamped() {
        let engine = makeEngine()
        let long = String(repeating: "a", count: 10_000)
        engine.handlePacket(CuePacket(type: .messageBroadcast, senderId: "pager", message: InterTeamMessage(sender: long, text: long)))
        XCTAssertEqual(engine.recentMessages.first?.text.count, ContentLimits.messageText)
        XCTAssertEqual(engine.recentMessages.first?.sender.count, ContentLimits.name)
    }

    func testRelayHostPolicy() {
        XCTAssertEqual(RelayHostPolicy.normalized("relay.example.com"), "relay.example.com")
        XCTAssertEqual(RelayHostPolicy.normalized(" relay.example.com:8443 "), "relay.example.com:8443")
        XCTAssertEqual(RelayHostPolicy.normalized("wss://relay.example.com"), "wss://relay.example.com")
        XCTAssertEqual(RelayHostPolicy.normalized("https://relay.example.com/relay"), "https://relay.example.com/relay")
        XCTAssertNil(RelayHostPolicy.normalized("ws://relay.example.com"))
        XCTAssertNil(RelayHostPolicy.normalized("http://relay.example.com"))
        XCTAssertNil(RelayHostPolicy.normalized("ftp://relay.example.com"))
        XCTAssertNil(RelayHostPolicy.normalized(""))
        XCTAssertNil(RelayHostPolicy.normalized("evil host"))
        XCTAssertNil(RelayHostPolicy.normalized("wss://user:pw@relay.example.com"))
        XCTAssertEqual(RelayHostPolicy.websocketURL(for: "relay.example.com")?.absoluteString, "wss://relay.example.com/relay")
        XCTAssertEqual(RelayHostPolicy.websocketURL(for: "https://relay.example.com")?.scheme, "wss")
        XCTAssertNil(RelayHostPolicy.websocketURL(for: "ws://relay.example.com"))
    }

    func testDocumentCannotChangeRelayHost() {
        let engine = makeEngine()
        let before = engine.plotipharRelayHost
        var document = engine.makeDocument()
        document.settings.plotipharRelayHost = "attacker.example"
        engine.apply(document)
        XCTAssertEqual(engine.plotipharRelayHost, before)
    }

    func testDocumentRelayHostFieldStillRoundTrips() throws {
        let engine = makeEngine()
        var document = engine.makeDocument()
        document.settings.plotipharRelayHost = "relay.example"
        let decoded = try ProducerDocument.decoded(from: document.encoded())
        XCTAssertEqual(decoded.settings.plotipharRelayHost, "relay.example")
    }

    func testChangingRelayHostClearsTokenAndPairing() {
        let engine = makeEngine()
        XCTAssertTrue(engine.setRelayHost("relay.one.example"))
        engine.proxyToken = "secret-token"
        engine.isProxyEnabled = true
        XCTAssertTrue(engine.setRelayHost("relay.two.example"))
        XCTAssertEqual(engine.proxyToken, "")
        XCTAssertFalse(engine.isProxyEnabled)
        XCTAssertEqual(engine.plotipharRelayHost, "relay.two.example")
        XCTAssertNil(KeychainStore.string(forKey: "plotipharProxyToken"))
    }

    func testSameRelayHostKeepsToken() {
        let engine = makeEngine()
        XCTAssertTrue(engine.setRelayHost("relay.one.example"))
        engine.proxyToken = "secret-token"
        XCTAssertTrue(engine.setRelayHost("RELAY.one.example"))
        XCTAssertEqual(engine.proxyToken, "secret-token")
    }

    func testRelayEndpointRejectsPlaintextHosts() {
        let engine = makeEngine()
        let response = send(engine, "PUT", "/v1/relay", #"{"host":"ws://relay.example.com"}"#)
        XCTAssertEqual(response.status, 400)
        XCTAssertNotEqual(engine.plotipharRelayHost, "ws://relay.example.com")
        XCTAssertEqual(send(engine, "PUT", "/v1/relay", #"{"host":"https://relay.example.com"}"#).status, 200)
        XCTAssertEqual(engine.plotipharRelayHost, "https://relay.example.com")
    }

    func testGuardAllowsOwnOriginAndOriginlessClients() {
        let own = HTTPRequest(method: "GET", path: "/v1/state", headers: ["host": "192.168.1.5:13390", "origin": "http://192.168.1.5:13390"])
        XCTAssertEqual(ControlAPIGuard.evaluate(own, machineHostName: "studio"), .allow)
        let native = HTTPRequest(method: "GET", path: "/v1/state", headers: ["host": "192.168.1.5:13390"])
        XCTAssertEqual(ControlAPIGuard.evaluate(native, machineHostName: "studio"), .allow)
        let bare = HTTPRequest(method: "GET", path: "/v1/state")
        XCTAssertEqual(ControlAPIGuard.evaluate(bare, machineHostName: "studio"), .allow)
    }

    func testGuardRejectsForeignOrigins() {
        for origin in ["https://evil.example", "http://192.168.1.5:9999", "http://192.168.1.6:13390", "null", "file://"] {
            let request = HTTPRequest(method: "POST", path: "/v1/timer/start", headers: ["host": "192.168.1.5:13390", "origin": origin])
            XCTAssertEqual(ControlAPIGuard.evaluate(request, machineHostName: "studio"), .reject(status: 403, message: "Cross-origin requests are not allowed"), origin)
        }
    }

    func testGuardValidatesHostHeader() {
        let allowed = ["127.0.0.1:13390", "localhost:13390", "[::1]:13390", "10.0.0.4", "studio.local:13390", "Studio:13390", "studio.local"]
        for host in allowed {
            XCTAssertTrue(ControlAPIGuard.isAllowedHost(host, machineHostName: "studio"), host)
        }
        let denied = ["evil.example:13390", "attacker.com", "studio.evil.example", "", ".local", "a:b:c"]
        for host in denied {
            XCTAssertFalse(ControlAPIGuard.isAllowedHost(host, machineHostName: "studio"), host)
        }
        let rebinding = HTTPRequest(method: "GET", path: "/v1/state", headers: ["host": "rebind.attacker.com:13390"])
        XCTAssertEqual(ControlAPIGuard.evaluate(rebinding, machineHostName: "studio"), .reject(status: 403, message: "Host not allowed"))
    }

    func testGuardRequiresJSONContentTypeForBodies() {
        let body = Data("{}".utf8)
        for method in ["POST", "PUT", "PATCH"] {
            let missing = HTTPRequest(method: method, path: "/v1/x", headers: ["host": "127.0.0.1"], body: body)
            XCTAssertEqual(ControlAPIGuard.evaluate(missing, machineHostName: "studio"), .reject(status: 415, message: "Content-Type must be application/json"))
            let form = HTTPRequest(method: method, path: "/v1/x", headers: ["host": "127.0.0.1", "content-type": "text/plain"], body: body)
            XCTAssertEqual(ControlAPIGuard.evaluate(form, machineHostName: "studio"), .reject(status: 415, message: "Content-Type must be application/json"))
            let json = HTTPRequest(method: method, path: "/v1/x", headers: ["host": "127.0.0.1", "content-type": "Application/JSON; charset=utf-8"], body: body)
            XCTAssertEqual(ControlAPIGuard.evaluate(json, machineHostName: "studio"), .allow)
        }
        let bodiless = HTTPRequest(method: "POST", path: "/v1/timer/start", headers: ["host": "127.0.0.1"])
        XCTAssertEqual(ControlAPIGuard.evaluate(bodiless, machineHostName: "studio"), .allow)
    }

    func testWebSocketUpgradeOriginCheck() {
        let ok = HTTPRequest(method: "GET", path: "/v1/socket", headers: ["host": "10.0.0.2:13390", "origin": "http://10.0.0.2:13390"])
        XCTAssertTrue(ControlAPIGuard.isAllowedWebSocketUpgrade(ok, machineHostName: "studio"))
        let native = HTTPRequest(method: "GET", path: "/v1/socket", headers: ["host": "10.0.0.2:13390"])
        XCTAssertTrue(ControlAPIGuard.isAllowedWebSocketUpgrade(native, machineHostName: "studio"))
        let foreign = HTTPRequest(method: "GET", path: "/v1/socket", headers: ["host": "10.0.0.2:13390", "origin": "https://evil.example"])
        XCTAssertFalse(ControlAPIGuard.isAllowedWebSocketUpgrade(foreign, machineHostName: "studio"))
        let rebound = HTTPRequest(method: "GET", path: "/v1/socket", headers: ["host": "evil.example:13390"])
        XCTAssertFalse(ControlAPIGuard.isAllowedWebSocketUpgrade(rebound, machineHostName: "studio"))
    }

    func testResponsesCarryHardeningHeadersAndNoCORS() {
        let text = String(decoding: HTTPResponse.json(status: 200, body: Data("{}".utf8)).serialize(), as: UTF8.self)
        XCTAssertTrue(text.contains("X-Content-Type-Options: nosniff"))
        XCTAssertTrue(text.contains("X-Frame-Options: DENY"))
        XCTAssertFalse(text.lowercased().contains("access-control-allow-origin"))
    }

    func testConnectionAdmissionCapsTotalAndPerIP() {
        var admission = ConnectionAdmission(maxTotal: 32, maxPerIP: 8)
        for _ in 0..<8 { XCTAssertTrue(admission.admit(ip: "10.0.0.1")) }
        XCTAssertFalse(admission.admit(ip: "10.0.0.1"))
        for host in 2...4 {
            for _ in 0..<8 { XCTAssertTrue(admission.admit(ip: "10.0.0.\(host)")) }
        }
        XCTAssertEqual(admission.count, 32)
        XCTAssertFalse(admission.admit(ip: "10.0.0.99"))
        admission.release(ip: "10.0.0.1")
        XCTAssertTrue(admission.admit(ip: "10.0.0.99"))
        admission.release(ip: "unknown")
        XCTAssertEqual(admission.count, 32)
    }

    func testConnectionDeadlines() {
        let start = Date(timeIntervalSince1970: 1_000)
        var window = ConnectionDeadlines(acceptedAt: start)
        XCTAssertFalse(window.httpExpired(now: start.addingTimeInterval(100)))
        window.requestStartedAt = start
        XCTAssertFalse(window.httpExpired(now: start.addingTimeInterval(9.9)))
        XCTAssertTrue(window.httpExpired(now: start.addingTimeInterval(10.1)))
        XCTAssertFalse(window.unupgradedExpired(now: start.addingTimeInterval(29)))
        XCTAssertTrue(window.unupgradedExpired(now: start.addingTimeInterval(31)))
        window.isUpgraded = true
        XCTAssertFalse(window.unupgradedExpired(now: start.addingTimeInterval(3_000)))
        XCTAssertFalse(window.httpExpired(now: start.addingTimeInterval(3_000)))
    }

    func testLANDeadlinesDistinguishSilentFromQuietConnections() {
        let start = Date(timeIntervalSince1970: 1_000)
        var window = ConnectionDeadlines(acceptedAt: start)
        XCTAssertFalse(window.lanExpired(now: start.addingTimeInterval(59)))
        XCTAssertTrue(window.lanExpired(now: start.addingTimeInterval(61)))
        window.hasReceivedFrame = true
        window.lastReceivedAt = start
        XCTAssertFalse(window.lanExpired(now: start.addingTimeInterval(100)))
        XCTAssertTrue(window.lanExpired(now: start.addingTimeInterval(121)))
    }

    func testAssignedHostPolicy() {
        for host in ["192.168.1.20", "10.1.2.3", "172.16.0.1", "172.31.255.254", "169.254.10.10", "100.64.0.1", "100.127.255.254", "127.0.0.1", "producer.local", "My-Mac.local"] {
            XCTAssertTrue(AssignedHostPolicy.isAcceptable(host), host)
        }
        for host in ["8.8.8.8", "172.32.0.1", "172.15.0.1", "100.63.255.255", "100.128.0.1", "192.169.1.1", "evil.example.com", "producer.local.evil.com", "1.2.3", "256.1.1.1", "", " ", "::1", ".local", "a b.local", "010.1.1.1.5"] {
            XCTAssertFalse(AssignedHostPolicy.isAcceptable(host), host)
        }
    }

    func testTimerItemArithmeticIsOverflowSafe() {
        let extremes = [Int.max, Int.min, Int.max - 1, Int.min + 1, 200_000_000_000_000_000, -200_000_000_000_000_000, 0, -1, 1]
        for delta in extremes {
            var item = timerItem()
            item.adjustRemainingTime(bySeconds: delta)
            XCTAssertTrue(TimerLimits.isValidLength(item.lengthInSeconds))
            item.setRemainingTime(seconds: delta)
            XCTAssertTrue(TimerLimits.isValidLength(item.lengthInSeconds))
            _ = item.remainingSeconds
            _ = item.formattedRemainingTime
            _ = TimeFormatting.string(forSeconds: delta, threshold: .never)
        }
        var item = timerItem()
        item.elapsedSeconds = Int.max
        item.lengthInSeconds = Int.min
        _ = item.remainingSeconds
        _ = item.formattedRemainingTime
        item.setRemainingTime(seconds: Int.max)
        XCTAssertEqual(item.lengthInSeconds, TimerLimits.maxSeconds)
    }

    func testDecodedTimerItemsAreClamped() throws {
        let json = #"{"id":"a","title":"t","itemType":"Item","sequence":1,"lengthInSeconds":9223372036854775807,"elapsedSeconds":-9223372036854775808,"isRunning":false}"#
        let item = try JSONDecoder().decode(PCOTimerItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.lengthInSeconds, TimerLimits.maxSeconds)
        XCTAssertEqual(item.elapsedSeconds, 0)
        let huge = #"{"id":"a","title":"t","itemType":"Item","sequence":1,"lengthInSeconds":5,"elapsedSeconds":9223372036854775807,"isRunning":false}"#
        let decoded = try JSONDecoder().decode(PCOTimerItem.self, from: Data(huge.utf8))
        XCTAssertEqual(decoded.elapsedSeconds, TimerLimits.maxElapsedSeconds)
        _ = decoded.formattedRemainingTime
    }

    func testTimerInputParserRejectsOverflowAndOutOfRange() {
        let inputs = [
            "99999999999999999999", "9223372036854775807", "+9223372036854775807", "-9223372036854775807",
            "9223372036854775807:59", "99999999999999999999h", "9999999999999999h9999999999999999m", "999999999999999999h",
            "300000000000000000m", "999999999999999:00", "200000000000000000", "1000h", "200h", "169h"
        ]
        for input in inputs {
            XCTAssertNil(TimerInputParser.parse(input), input)
        }
        XCTAssertEqual(TimerInputParser.parse("168h"), .setAbsolute(seconds: 604_800))
        XCTAssertEqual(TimerInputParser.parse("5:30"), .setAbsolute(seconds: 330))
        XCTAssertEqual(TimerInputParser.parse("+90"), .adjustRelative(bySeconds: 90))
        XCTAssertEqual(TimerInputParser.parse("1h2m3s"), .setAbsolute(seconds: 3723))
    }

    func testFlowImporterDurationsAreClamped() {
        XCTAssertEqual(ServiceFlowImporter.parseDuration("9223372036854775807"), TimerLimits.maxSeconds)
        XCTAssertEqual(ServiceFlowImporter.parseDuration("9223372036854775807:99999999999999"), TimerLimits.maxSeconds)
        XCTAssertEqual(ServiceFlowImporter.parseDuration("99999999999:99999999999:99999999999"), TimerLimits.maxSeconds)
        XCTAssertEqual(ServiceFlowImporter.parseDuration("5:00"), 300)
        XCTAssertEqual(ServiceFlowImporter.parseDuration("1:00:00"), 3600)
        XCTAssertEqual(ServiceFlowImporter.parseDuration("-5:00"), 0)
    }

    func testTimerEndpointsRejectOutOfRangeValues() {
        let engine = makeEngine()
        engine.activeTimerItem = timerItem()
        for value in ["9223372036854775807", "-9223372036854775808", "200000000000000000", "604801", "-604801"] {
            XCTAssertEqual(send(engine, "POST", "/v1/timer/adjust", #"{"seconds":\#(value)}"#).status, 400, value)
        }
        for value in ["9223372036854775807", "-9223372036854775808", "200000000000000000", "604801", "-1"] {
            XCTAssertEqual(send(engine, "PUT", "/v1/timer/remaining", #"{"seconds":\#(value)}"#).status, 400, value)
        }
        XCTAssertEqual(send(engine, "PUT", "/v1/timer/remaining", #"{"input":"99999999999999999999"}"#).status, 400)
        XCTAssertEqual(send(engine, "POST", "/v1/timer/adjust", #"{"seconds":604800}"#).status, 200)
        XCTAssertEqual(send(engine, "PUT", "/v1/timer/remaining", #"{"seconds":604800}"#).status, 200)
        XCTAssertEqual(engine.activeTimerItem?.lengthInSeconds, TimerLimits.maxSeconds)
    }

    func testScheduleOffsetsAreOverflowSafe() {
        let engine = makeEngine()
        for value in ["\"goLiveOffsetMinutes\":9223372036854775807", "\"goLiveOffsetMinutes\":200000000000000000", "\"goLiveOffsetMinutes\":-9223372036854775808", "\"goLiveOffsetSeconds\":9223372036854775807", "\"goLiveOffsetSeconds\":-1", "\"goLiveOffsetMinutes\":20000"] {
            let body = "{\"title\":\"Sun\",\"startsAt\":\"2030-01-01T10:00:00Z\",\(value)}"
            XCTAssertEqual(send(engine, "POST", "/v1/schedules", body).status, 400, value)
        }
        XCTAssertEqual(send(engine, "POST", "/v1/schedules", #"{"title":"Sun","startsAt":"2030-01-01T10:00:00Z","goLiveOffsetMinutes":30}"#).status, 201)
        let id = engine.serviceSchedules[0].id
        XCTAssertEqual(send(engine, "PATCH", "/v1/schedules/\(id)", #"{"goLiveOffsetMinutes":9223372036854775807}"#).status, 400)
        var schedule = engine.serviceSchedules[0]
        schedule.goLiveOffsetMinutes = Int.max
        XCTAssertTrue(TimerLimits.isValidDelta(schedule.goLiveOffsetSeconds))
        schedule.goLiveOffsetMinutes = Int.min
        XCTAssertTrue(TimerLimits.isValidDelta(schedule.goLiveOffsetSeconds))
    }

    func testPlanItemLengthsAreRangeChecked() {
        let engine = makeEngine()
        XCTAssertEqual(send(engine, "POST", "/v1/plan/items", #"{"title":"A","lengthInSeconds":9223372036854775807}"#).status, 400)
        XCTAssertEqual(send(engine, "POST", "/v1/plan/items", #"{"title":"A","lengthInSeconds":-5}"#).status, 400)
        XCTAssertEqual(send(engine, "POST", "/v1/plan/items", #"{"title":"A","lengthInSeconds":60}"#).status, 201)
        let id = engine.planItems[0].id
        XCTAssertEqual(send(engine, "PATCH", "/v1/plan/items/\(id)", #"{"lengthInSeconds":200000000000000000}"#).status, 400)
    }

    func testTextLengthLimits() {
        let engine = makeEngine()
        let longName = String(repeating: "n", count: ContentLimits.name + 1)
        let longTitle = String(repeating: "t", count: ContentLimits.title + 1)
        let longMessage = String(repeating: "m", count: ContentLimits.messageText + 1)
        let longNote = String(repeating: "x", count: ContentLimits.noteValue + 1)
        XCTAssertEqual(send(engine, "POST", "/v1/roles", #"{"name":"\#(longName)"}"#).status, 400)
        XCTAssertEqual(send(engine, "POST", "/v1/waypoints", #"{"name":"\#(longName)"}"#).status, 400)
        XCTAssertEqual(send(engine, "POST", "/v1/messages", #"{"text":"\#(longMessage)"}"#).status, 400)
        XCTAssertEqual(send(engine, "POST", "/v1/plan/items", #"{"title":"\#(longTitle)"}"#).status, 400)
        XCTAssertEqual(send(engine, "POST", "/v1/schedules", #"{"title":"\#(longTitle)","startsAt":"2030-01-01T10:00:00Z"}"#).status, 400)
        XCTAssertEqual(send(engine, "POST", "/v1/plan/import", #"{"text":"\#(longTitle) | Item | 1:00"}"#).status, 400)
        XCTAssertEqual(send(engine, "POST", "/v1/plan/items", #"{"title":"ok"}"#).status, 201)
        let id = engine.planItems[0].id
        XCTAssertEqual(send(engine, "PATCH", "/v1/plan/items/\(id)", #"{"notes":{"Cat":"\#(longNote)"}}"#).status, 400)
        XCTAssertEqual(send(engine, "PATCH", "/v1/plan/items/\(id)", #"{"notes":{"Cat":"fine"}}"#).status, 200)
        XCTAssertEqual(send(engine, "POST", "/v1/messages", #"{"text":"\#(String(repeating: "m", count: ContentLimits.messageText))"}"#).status, 201)
    }

    func testCountLimits() {
        let engine = makeEngine()
        engine.roles = (0..<ContentLimits.maxRoles).map { RoleCue(id: "r\($0)", name: "R\($0)") }
        XCTAssertEqual(send(engine, "POST", "/v1/roles", #"{"name":"one more"}"#).status, 409)

        engine.planItems = (0..<ContentLimits.maxPlanItems).map { PCOTimerItem(id: "i\($0)", title: "I\($0)") }
        XCTAssertEqual(send(engine, "POST", "/v1/plan/items", #"{"title":"one more"}"#).status, 409)

        engine.waypoints = (0..<ContentLimits.maxWaypoints).map { Waypoint(name: "W\($0)") }
        XCTAssertEqual(send(engine, "POST", "/v1/waypoints", #"{"name":"one more"}"#).status, 409)

        engine.serviceSchedules = (0..<ContentLimits.maxSchedules).map {
            ServiceSchedule(title: "S\($0)", startsAt: Date(timeIntervalSince1970: 2_000_000_000 + Double($0)))
        }
        XCTAssertEqual(send(engine, "POST", "/v1/schedules", #"{"title":"one more","startsAt":"2030-01-01T10:00:00Z"}"#).status, 409)

        let lines = (0...ContentLimits.maxPlanItems).map { "Item \($0) | Item | 1:00" }.joined(separator: "\\n")
        XCTAssertEqual(send(engine, "POST", "/v1/plan/import", #"{"text":"\#(lines)"}"#).status, 409)
    }
}

extension CuePacket.PacketType: CaseIterable {
    public static var allCases: [CuePacket.PacketType] {
        [.cueUpdate, .timerUpdate, .messageBroadcast, .ping, .pong, .clearMessages, .sync, .syncReply, .timerAnchor, .cueDelta, .digest]
    }
}
