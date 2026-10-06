// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

@MainActor
final class CueEngineTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearPersistedState()
    }

    override func tearDown() {
        clearPersistedState()
        super.tearDown()
    }

    private func clearPersistedState() {
        UserDefaults.standard.removeObject(forKey: "persistedFlow")
        UserDefaults.standard.removeObject(forKey: "persistedRoles")
        UserDefaults.standard.removeObject(forKey: "isPCOLiveSyncEnabled")
        UserDefaults.standard.removeObject(forKey: "recentMessages")
        UserDefaults.standard.removeObject(forKey: "waypoints")
        UserDefaults.standard.removeObject(forKey: "serviceTags")
        UserDefaults.standard.removeObject(forKey: "serviceSchedules")
    }

    func testMultiRoleSelectionAndCueTrigger() {
        let engine = CueEngine()
        engine.roles = [
            RoleCue(id: "host", name: "Host"),
            RoleCue(id: "keys", name: "Keys"),
            RoleCue(id: "speaker", name: "Speaker"),
        ]

        engine.selectedRoleIds = ["host", "keys"]

        engine.setCueForSelectedRoles(.standby)

        let hostRole = engine.roles.first(where: { $0.id == "host" })
        let keysRole = engine.roles.first(where: { $0.id == "keys" })
        let speakerRole = engine.roles.first(where: { $0.id == "speaker" })

        XCTAssertEqual(hostRole?.state, .standby)
        XCTAssertEqual(keysRole?.state, .standby)
        XCTAssertEqual(speakerRole?.state, .off)

        engine.setCueForSelectedRoles(.go)
        XCTAssertEqual(engine.roles.first(where: { $0.id == "host" })?.state, .go)
        XCTAssertEqual(engine.roles.first(where: { $0.id == "keys" })?.state, .go)

        engine.clearAllCues()
        XCTAssertTrue(engine.roles.allSatisfy { $0.state == .off })
    }

    func testCuePacketSerialization() {
        let roles = RoleCue.defaultRoles
        let timer = PCOTimerItem(title: "Worship Song", itemType: "Song", sequence: 1, lengthInSeconds: 300, elapsedSeconds: 60)

        let packet = CuePacket(type: .cueUpdate, senderId: "unit_test", roleCues: roles, timerItem: timer)
        guard let data = packet.encode() else {
            XCTFail("Failed to encode packet")
            return
        }

        guard let decoded = CuePacket.decode(from: data) else {
            XCTFail("Failed to decode packet")
            return
        }

        XCTAssertEqual(decoded.type, .cueUpdate)
        XCTAssertEqual(decoded.senderId, "unit_test")
        XCTAssertEqual(decoded.roleCues?.count, roles.count)
        XCTAssertEqual(decoded.timerItem?.remainingSeconds, 240)
    }

    private func makeFlow() -> [PCOTimerItem] {
        [
            PCOTimerItem(title: "Pre Gathering", itemType: "header", sequence: 1, lengthInSeconds: 0),
            PCOTimerItem(title: "Doors", itemType: "item", sequence: 2, lengthInSeconds: 300),
            PCOTimerItem(title: "Announcements", itemType: "header", sequence: 3, lengthInSeconds: 0),
            PCOTimerItem(title: "Sub-section", itemType: "header", sequence: 4, lengthInSeconds: 0),
            PCOTimerItem(title: "Worship", itemType: "song", sequence: 5, lengthInSeconds: 280),
        ]
    }

    func testImportFlowSkipsLeadingHeader() {
        let engine = CueEngine()
        engine.importFlow(title: "Test Plan", items: makeFlow())

        XCTAssertEqual(engine.activeTimerItem?.title, "Doors")
        XCTAssertFalse(engine.activeTimerItem?.isHeader ?? true)
    }

    func testNextPlanItemSkipsConsecutiveHeaders() {
        let engine = CueEngine()
        engine.importFlow(title: "Test Plan", items: makeFlow())
        XCTAssertEqual(engine.activeTimerItem?.title, "Doors")

        engine.nextPlanItem()

        XCTAssertEqual(engine.activeTimerItem?.title, "Worship")
        XCTAssertFalse(engine.activeTimerItem?.isHeader ?? true)
    }

    func testPreviousPlanItemSkipsConsecutiveHeaders() {
        let engine = CueEngine()
        engine.importFlow(title: "Test Plan", items: makeFlow())
        engine.setActivePlanItem(id: engine.planItems[4].id)

        engine.previousPlanItem()

        XCTAssertEqual(engine.activeTimerItem?.title, "Doors")
        XCTAssertFalse(engine.activeTimerItem?.isHeader ?? true)
    }

    func testTappingAHeaderResolvesToNearestRealItem() {
        let engine = CueEngine()
        let items = makeFlow()
        engine.importFlow(title: "Test Plan", items: items)

        let headerId = items[2].id
        engine.setActivePlanItem(id: headerId)

        XCTAssertFalse(engine.activeTimerItem?.isHeader ?? true)
    }

    func testHeaderCannotBeStartedRunning() {
        let engine = CueEngine()
        engine.importFlow(title: "Test Plan", items: makeFlow())
        engine.activeTimerItem = makeFlow()[0]

        engine.toggleTimerRunning()

        XCTAssertFalse(engine.activeTimerItem?.isRunning ?? true)
    }

    func testAddPlanItemDoesNotAutoActivateAHeader() {
        let engine = CueEngine()
        XCTAssertNil(engine.activeTimerItem)

        engine.addPlanItem(title: "Opening Header", itemType: "header", lengthInSeconds: 0)

        XCTAssertNil(engine.activeTimerItem)
    }

    func testFlowPersistsAcrossRelaunch() {
        let engineA = CueEngine()
        engineA.importFlow(title: "Test Plan", items: makeFlow())
        engineA.nextPlanItem()

        let engineB = CueEngine()

        XCTAssertEqual(engineB.planItems.count, engineA.planItems.count)
        XCTAssertEqual(engineB.activeItemIndex, engineA.activeItemIndex)
        XCTAssertEqual(engineB.activeTimerItem?.title, engineA.activeTimerItem?.title)
    }

    func testRestoredItemNeverResumesRunning() {
        let engineA = CueEngine()
        engineA.importFlow(title: "Test Plan", items: makeFlow())
        XCTAssertEqual(engineA.activeTimerItem?.isRunning, true)

        let engineB = CueEngine()

        XCTAssertEqual(engineB.activeTimerItem?.isRunning, false)
    }

    func testRoleAssignmentsPersistAcrossRelaunch() {
        let engineA = CueEngine()
        engineA.setNoteCategory(forRoleId: "default", category: "Host Notes", isOn: true)
        engineA.setCueForRole(id: "default", state: .standby)

        let engineB = CueEngine()

        let restoredHost = engineB.roles.first(where: { $0.id == "default" })
        XCTAssertEqual(restoredHost?.assignedNoteCategories, ["Host Notes"])
        XCTAssertEqual(restoredHost?.state, .standby)
    }

    func testPCOLiveSyncFlagPersistence() {
        let engine = CueEngine()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "isPCOLiveSyncEnabled"))

        engine.isPCOLiveSyncEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "isPCOLiveSyncEnabled"))

        engine.disablePCOLiveSync()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "isPCOLiveSyncEnabled"))
    }

    func testIsAtEndOfPlanOnlyOnTheLastPlayableItem() {
        let engine = CueEngine()
        engine.importFlow(title: "Test Plan", items: makeFlow())
        XCTAssertFalse(engine.isAtEndOfPlan)

        engine.setActivePlanItem(id: engine.planItems[4].id)
        XCTAssertTrue(engine.isAtEndOfPlan)
    }

    func testCanLoadNextServiceRequiresAPCOPlan() {
        let engine = CueEngine()
        engine.importFlow(title: "Manual Flow", items: makeFlow())
        XCTAssertFalse(engine.canLoadNextService)
    }

    func testSetTimerRemainingTimeComputesLengthFromLiveElapsed() {
        let engine = CueEngine()
        engine.importFlow(title: "Test Plan", items: [
            PCOTimerItem(title: "Sermon", itemType: "item", sequence: 1, lengthInSeconds: 45 * 60),
        ])
        engine.activeTimerItem?.elapsedSeconds = 25 * 60
        engine.activeTimerItem?.isRunning = true

        engine.setTimerRemainingTime(seconds: 30 * 60 + 23)

        XCTAssertEqual(engine.activeTimerItem?.lengthInSeconds, 25 * 60 + 30 * 60 + 23)
        XCTAssertEqual(engine.activeTimerItem?.remainingSeconds, 30 * 60 + 23)
    }

    func testSetTimerRemainingTimeSyncsThePlanItemsCopyToo() {
        let engine = CueEngine()
        engine.importFlow(title: "Test Plan", items: [
            PCOTimerItem(title: "Sermon", itemType: "item", sequence: 1, lengthInSeconds: 45 * 60),
        ])

        engine.setTimerRemainingTime(seconds: 30 * 60 + 23)

        XCTAssertEqual(engine.planItems.first?.lengthInSeconds, engine.activeTimerItem?.lengthInSeconds)
    }

    func testSetDurationIsActualSyncsBothCopiesWhileRunning() {
        let engine = CueEngine()
        engine.importFlow(title: "Test Plan", items: [
            PCOTimerItem(title: "Song", itemType: "item", sequence: 1, lengthInSeconds: 3 * 60),
        ])
        engine.activeTimerItem?.isRunning = true
        engine.activeTimerItem?.elapsedSeconds = 45
        let id = engine.activeTimerItem!.id

        engine.setDurationIsActual(id: id, isActual: true)

        XCTAssertEqual(engine.activeTimerItem?.isDurationActual, true)
        XCTAssertEqual(engine.planItems.first?.isDurationActual, true)
        XCTAssertEqual(engine.activeTimerItem?.isRunning, true)
        XCTAssertEqual(engine.activeTimerItem?.elapsedSeconds, 45)

        engine.setDurationIsActual(id: id, isActual: false)
        XCTAssertEqual(engine.activeTimerItem?.isDurationActual, false)
        XCTAssertEqual(engine.planItems.first?.isDurationActual, false)
    }

    func testActiveTimerActualOverrideNeverTouchesThePlanItem() {
        let engine = CueEngine()
        engine.importFlow(title: "Test Plan", items: [
            PCOTimerItem(title: "Song", itemType: "item", sequence: 1, lengthInSeconds: 3 * 60),
        ])
        let id = engine.activeTimerItem!.id

        engine.setActiveTimerActualOverride(true)

        XCTAssertEqual(engine.activeTimerActualForDisplay, true)
        XCTAssertEqual(engine.activeTimerItem?.isDurationActual, false)
        XCTAssertEqual(engine.planItems.first?.isDurationActual, false)

        engine.setActiveTimerActualOverride(false)
        XCTAssertEqual(engine.activeTimerActualForDisplay, false)
        XCTAssertEqual(engine.planItems.first(where: { $0.id == id })?.isDurationActual, false)
    }

    func testActiveTimerActualOverrideDoesNotCarryOverToADifferentItem() {
        let engine = CueEngine()
        engine.importFlow(title: "Test Plan", items: [
            PCOTimerItem(title: "Song", itemType: "item", sequence: 1, lengthInSeconds: 3 * 60),
            PCOTimerItem(title: "Sermon", itemType: "item", sequence: 2, lengthInSeconds: 20 * 60),
        ])
        engine.setActiveTimerActualOverride(true)
        XCTAssertEqual(engine.activeTimerActualForDisplay, true)

        engine.nextPlanItem()

        XCTAssertEqual(engine.activeTimerItem?.title, "Sermon")
        XCTAssertEqual(engine.activeTimerActualForDisplay, false)
    }

    func testPCOTimerItemDecodesOldDataMissingIsDurationActual() throws {
        let legacyJSON = """
        {"id":"abc","title":"Sermon","itemType":"item","sequence":1,
         "lengthInSeconds":300,"elapsedSeconds":0,"isRunning":false,
         "notes":{},"noteIds":{}}
        """
        let item = try JSONDecoder().decode(PCOTimerItem.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(item.isDurationActual, false)
        XCTAssertEqual(item.title, "Sermon")
    }
}

final class TimerInputParserTests: XCTestCase {
    func testBareDigitsSplitPositionally() {
        XCTAssertEqual(TimerInputParser.parse("4350"), .setAbsolute(seconds: 43 * 60 + 50))
        XCTAssertEqual(TimerInputParser.parse("350"), .setAbsolute(seconds: 3 * 60 + 50))
        XCTAssertEqual(TimerInputParser.parse("50"), .setAbsolute(seconds: 50))
        XCTAssertEqual(TimerInputParser.parse("5"), .setAbsolute(seconds: 5))
    }

    func testExplicitSeparators() {
        XCTAssertEqual(TimerInputParser.parse("43:50"), .setAbsolute(seconds: 43 * 60 + 50))
        XCTAssertEqual(TimerInputParser.parse("43.50"), .setAbsolute(seconds: 43 * 60 + 50))
    }

    func testUnitSuffixesAreAPlainCountNotPositional() {
        XCTAssertEqual(TimerInputParser.parse("120s"), .setAbsolute(seconds: 120))
        XCTAssertEqual(TimerInputParser.parse("1m"), .setAbsolute(seconds: 60))
    }

    func testLeadingSignMakesItRelative() {
        XCTAssertEqual(TimerInputParser.parse("+120s"), .adjustRelative(bySeconds: 120))
        XCTAssertEqual(TimerInputParser.parse("+1m"), .adjustRelative(bySeconds: 60))
        XCTAssertEqual(TimerInputParser.parse("-30s"), .adjustRelative(bySeconds: -30))
        XCTAssertEqual(TimerInputParser.parse("-1m"), .adjustRelative(bySeconds: -60))
        XCTAssertEqual(TimerInputParser.parse("+43:50"), .adjustRelative(bySeconds: 43 * 60 + 50))
    }

    func testInvalidInputReturnsNil() {
        XCTAssertNil(TimerInputParser.parse(""))
        XCTAssertNil(TimerInputParser.parse("   "))
        XCTAssertNil(TimerInputParser.parse("abc"))
        XCTAssertNil(TimerInputParser.parse("+"))
        XCTAssertNil(TimerInputParser.parse(":"))
        XCTAssertNil(TimerInputParser.parse("2m3"))
        XCTAssertNil(TimerInputParser.parse("1m2m"))
    }

    func testCombinedUnitSuffixesSum() {
        XCTAssertEqual(TimerInputParser.parse("2m3s"), .setAbsolute(seconds: 2 * 60 + 3))
        XCTAssertEqual(TimerInputParser.parse("1h30m"), .setAbsolute(seconds: 90 * 60))
        XCTAssertEqual(TimerInputParser.parse("1h2m3s"), .setAbsolute(seconds: 3600 + 2 * 60 + 3))
        XCTAssertEqual(TimerInputParser.parse("+2m3s"), .adjustRelative(bySeconds: 2 * 60 + 3))
        XCTAssertEqual(TimerInputParser.parse("-2m3s"), .adjustRelative(bySeconds: -(2 * 60 + 3)))
    }
}

final class TimeFormattingTests: XCTestCase {
    func testStaysMMSSBelowThreshold() {
        XCTAssertEqual(TimeFormatting.string(forSeconds: 89 * 60 + 59, threshold: .over90Minutes), "89:59")
    }

    func testSwitchesToHMMSSAtThreshold() {
        XCTAssertEqual(TimeFormatting.string(forSeconds: 90 * 60, threshold: .over90Minutes), "1:30:00")
        XCTAssertEqual(TimeFormatting.string(forSeconds: 61 * 60, threshold: .over60Minutes), "1:01:00")
        XCTAssertEqual(TimeFormatting.string(forSeconds: 59 * 60, threshold: .over60Minutes), "59:00")
    }

    func testNeverSwitchesRegardlessOfLength() {
        XCTAssertEqual(TimeFormatting.string(forSeconds: 5 * 3600, threshold: .never), "300:00")
    }

    func testOvertimeKeepsThePlusPrefixRegardlessOfFormat() {
        XCTAssertEqual(TimeFormatting.string(forSeconds: -30, threshold: .over90Minutes), "+00:30")
        XCTAssertEqual(TimeFormatting.string(forSeconds: -91 * 60, threshold: .over90Minutes), "+1:31:00")
    }
}

final class PlotipharPairingClientTests: XCTestCase {
    func testParsesFractionalSecondsExpiresAt() {
        XCTAssertNotNil(PlotipharPairingClient.parseISO8601("2026-08-26T13:59:52.101Z"))
    }

    func testStillParsesWithoutFractionalSeconds() {
        XCTAssertNotNil(PlotipharPairingClient.parseISO8601("2026-08-26T13:59:52Z"))
    }

    func testRejectsGarbage() {
        XCTAssertNil(PlotipharPairingClient.parseISO8601("not a date"))
    }
}

@MainActor
final class PlotipharAssignmentTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "persistedRoles")
        super.tearDown()
    }

    func testFillsUnsetPersonNameForALinkedRole() {
        let engine = CueEngine()
        engine.roles = [RoleCue(id: "host", name: "Service Host", plotipharRoleId: "abc123")]

        engine.applyPlotipharAssignments([
            .init(roleId: "abc123", personName: "Jordan"),
        ])

        XCTAssertEqual(engine.roles.first?.personName, "Jordan")
    }

    func testDoesNotClobberAManuallySetPersonName() {
        let engine = CueEngine()
        engine.roles = [RoleCue(id: "host", name: "Service Host", personName: "Whoever's Actually Here", plotipharRoleId: "abc123")]

        engine.applyPlotipharAssignments([
            .init(roleId: "abc123", personName: "Jordan"),
        ])

        XCTAssertEqual(engine.roles.first?.personName, "Whoever's Actually Here")
    }

    func testIgnoresAssignmentsForUnlinkedRoles() {
        let engine = CueEngine()
        engine.roles = [RoleCue(id: "host", name: "Service Host", plotipharRoleId: nil)]

        engine.applyPlotipharAssignments([
            .init(roleId: "abc123", personName: "Jordan"),
        ])

        XCTAssertNil(engine.roles.first?.personName)
    }

    func testDecodesEventIgnoringFieldsItDoesNotDeclare() throws {
        let json = """
        {
            "id": "evt_1", "date": "2026-08-30", "title": "Sunday Service",
            "layoutId": "layout_1", "pcoPlanId": "89572772",
            "roleAssignments": [{"roleId": "abc123", "personName": "Jordan"}],
            "positionOverrides": [], "tables": [],
            "createdAt": "2026-08-01T00:00:00.000Z", "updatedAt": "2026-08-01T00:00:00.000Z"
        }
        """
        let event = try JSONDecoder().decode(PlotipharClient.PlotipharEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.pcoPlanId, "89572772")
        XCTAssertEqual(event.roleAssignments.first?.personName, "Jordan")
    }
}

@MainActor
final class MessagingTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "recentMessages")
        UserDefaults.standard.removeObject(forKey: "persistedRoles")
        super.tearDown()
    }

    func testBroadcastMessageHasNoTarget() {
        let engine = CueEngine()
        engine.sendMessage("Two minutes to Go")

        XCTAssertEqual(engine.recentMessages.first?.targetRoleId, nil)
        XCTAssertEqual(engine.recentMessages.first?.text, "Two minutes to Go")
    }

    func testTargetedMessageCarriesTheExplicitRoleIdNotWhateverIsCueSelected() {
        let engine = CueEngine()
        engine.selectedRoleIds = ["keys"]

        engine.sendMessage("Standby for cue", targetRoleId: "host")

        XCTAssertEqual(engine.recentMessages.first?.targetRoleId, "host")
    }

    func testHighPriorityFlagIsCarriedThrough() {
        let engine = CueEngine()
        engine.sendMessage("Mic is hot", isHighPriority: true)
        XCTAssertEqual(engine.recentMessages.first?.isHighPriority, true)
    }

    func testReplyFromARoleDerivesTheSenderNameFromThatRole() {
        let engine = CueEngine()
        engine.roles = [RoleCue(id: "host", name: "Service Host")]

        engine.sendMessage("On my way", targetRoleId: "host", senderRoleId: "host")

        let sent = engine.recentMessages.first
        XCTAssertEqual(sent?.sender, "Service Host")
        XCTAssertEqual(sent?.senderRoleId, "host")
        XCTAssertEqual(sent?.targetRoleId, "host")
    }

    func testAddMessagesDedupesByIdInsteadOfDoubleInserting() {
        let engine = CueEngine()
        let msg = InterTeamMessage(sender: "Producer", text: "Two minutes")

        engine.addMessages([msg])
        engine.addMessages([msg])

        XCTAssertEqual(engine.recentMessages.count, 1)
    }

    func testAddMessagesSortsNewestFirstAndCapsHistory() {
        let engine = CueEngine()
        let old = InterTeamMessage(text: "old", timestamp: Date(timeIntervalSince1970: 0))
        let new = InterTeamMessage(text: "new", timestamp: Date(timeIntervalSince1970: 1000))

        engine.addMessages([old])
        engine.addMessages([new])

        XCTAssertEqual(engine.recentMessages.first?.text, "new")
        XCTAssertEqual(engine.recentMessages.last?.text, "old")
    }
}
