// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

final class CommandLineTests: XCTestCase {
    private let context = CommandLineContext(itemTypes: ["Item", "Song", "Header", "Media"], roles: ["Band", "Host", "Lighting"], itemCount: 8, hasSelection: false)

    private func analyze(_ text: String, selection: Bool = false) -> CommandLineAnalysis {
        var ctx = context
        ctx.hasSelection = selection
        return CommandLine.analyze(text, context: ctx)
    }

    private func translation(_ text: String) -> String {
        analyze(text).pieces.map(\.text).joined(separator: " ")
    }

    func testAbbreviationsExpandToFullWords() {
        XCTAssertEqual(translation("sto cu 3 "), "Store Cue 3")
        XCTAssertEqual(translation("sto \"Offering\" ti 5m "), "Store \"Offering\" Time 5m")
        XCTAssertEqual(translation("cu 4 thru 6 ty so "), "Cue 4 Thru 6 Type Song")
    }

    func testAmbiguousWordBlocksTheCommand() {
        let result = analyze("cu 4 t ")
        guard case .ambiguous = result.status else { return XCTFail("expected ambiguous, got \(result.status)") }
        XCTAssertNil(result.statement)
    }

    func testUnknownWordIsInvalid() {
        guard case .invalid = analyze("sto zzz ").status else { return XCTFail("expected invalid") }
    }

    func testStoreBuildsStatementWithTimeAndTrigger() throws {
        let result = analyze("store cue 3 thru 5 insert \"Hymn\" time 4:30 trigger follow ")
        XCTAssertEqual(result.status, .ready)
        let statement = try XCTUnwrap(result.statement)
        XCTAssertEqual(statement.verb, .store)
        XCTAssertEqual(statement.position, 3)
        XCTAssertEqual(statement.count, 3)
        XCTAssertEqual(statement.title, "Hymn")
        XCTAssertEqual(statement.trigger, .follow)
        XCTAssertEqual(statement.length, TimerInputParser.parse("4:30"))
    }

    func testRelativeTimeWithSeparateSign() throws {
        let result = analyze("cue 2 time + 30 ")
        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.pieces.map(\.text), ["Cue", "2", "Time", "+30"])
        XCTAssertEqual(result.statement?.length, TimerInputParser.parse("+30"))
    }

    func testBadTimeIsInvalid() {
        guard case .invalid = analyze("cue 2 time zz ").status else { return XCTFail("expected invalid") }
    }

    func testRolesJoinWithPlus() throws {
        let result = analyze("cue 4 role band + host ")
        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.statement?.roles, ["Band", "Host"])
    }

    func testUnknownRoleIsInvalid() {
        guard case .invalid = analyze("cue 4 role zzz ").status else { return XCTFail("expected invalid") }
    }

    func testEditVerbsNeedATarget() {
        guard case .incomplete = analyze("delete ").status else { return XCTFail("expected incomplete") }
        XCTAssertEqual(analyze("delete ", selection: true).status, .ready)
        XCTAssertEqual(analyze("delete cue 4 thru 6 ").status, .ready)
    }

    func testMoveAndCopyNeedAPosition() throws {
        guard case .incomplete = analyze("move cue 5 ").status else { return XCTFail("expected incomplete") }
        let statement = try XCTUnwrap(analyze("move cue 5 at 2 ").statement)
        XCTAssertEqual(statement.verb, .move)
        XCTAssertEqual(statement.target, 2)
        XCTAssertEqual(analyze("copy cue 2 at 7 ").statement?.verb, .copy)
    }

    func testItemBeyondTheRunSheetIsInvalid() {
        guard case .invalid = analyze("delete cue 12 ").status else { return XCTFail("expected invalid") }
        XCTAssertEqual(analyze("store cue 12 ").status, .ready)
    }

    func testGoIsAVerbAtTheStartAndAValueAfterTrigger() {
        XCTAssertEqual(analyze("go cue 3 ").statement?.verb, .go)
        XCTAssertEqual(analyze("cue 3 trigger go ").statement?.trigger, .go)
    }

    func testSuggestionsFollowTheGrammar() {
        XCTAssertEqual(analyze("").suggestions.map(\.word).first, "Store")
        XCTAssertEqual(analyze("cue 3 trigger ").suggestions.map(\.word), ["Follow", "Go"])
        XCTAssertEqual(analyze("cue 3 type ").suggestions.map(\.word), ["Item", "Song", "Header", "Media"])
        XCTAssertEqual(analyze("cue 3 role band + ").suggestions.map(\.word), ["Host", "Lighting"])
        XCTAssertTrue(analyze("cue 3 time ").suggestions.isEmpty)
        XCTAssertFalse(analyze("cue 3 time 5m ").suggestions.map(\.word).contains("Time"))
    }

    func testGhostAndCompletion() throws {
        let result = analyze("sto cu")
        XCTAssertEqual(result.suggestions.map(\.word), ["Cue"])
        XCTAssertEqual(result.ghost, "e")
        XCTAssertEqual(result.completed(with: try XCTUnwrap(result.suggestions.first)), "sto Cue ")
        let fresh = analyze("sto ")
        XCTAssertEqual(fresh.completed(with: try XCTUnwrap(fresh.suggestions.first)), "sto Cue ")
    }

    func testLeadingNumberDetection() {
        XCTAssertTrue(CommandLine.startsWithNumber("5"))
        XCTAssertTrue(CommandLine.startsWithNumber("  4:30"))
        XCTAssertFalse(CommandLine.startsWithNumber("cue 4"))
        XCTAssertFalse(CommandLine.startsWithNumber(""))
    }
}

@MainActor
final class CommandLineExecutionTests: XCTestCase {
    private func makeEngine() -> CueEngine {
        let engine = CueEngine()
        engine.roles = [RoleCue(id: "band", name: "Band"), RoleCue(id: "host", name: "Host")]
        engine.importFlow(title: "Sunday", items: [
            PCOTimerItem(id: "a", title: "Welcome", itemType: "Item", lengthInSeconds: 60),
            PCOTimerItem(id: "b", title: "Song", itemType: "Song", lengthInSeconds: 240),
            PCOTimerItem(id: "c", title: "Message", itemType: "Item", lengthInSeconds: 1200),
            PCOTimerItem(id: "d", title: "Close", itemType: "Item", lengthInSeconds: 60)
        ])
        return engine
    }

    private func run(_ engine: CueEngine, _ text: String, selected: String? = nil) -> CommandOutcome? {
        let analysis = CommandLine.analyze(text + " ", context: engine.commandLineContext(selectedItemId: selected))
        guard let statement = analysis.statement else {
            XCTFail("not ready: \(analysis.status)")
            return nil
        }
        return engine.runCommand(statement, selectedItemId: selected)
    }

    func testStoreInsertsAtPosition() {
        let engine = makeEngine()
        _ = run(engine, "store cue 2 insert \"Offering\" time 5m type song")
        XCTAssertEqual(engine.planItems.map(\.title), ["Welcome", "Offering", "Song", "Message", "Close"])
        XCTAssertEqual(engine.planItems[1].lengthInSeconds, 300)
        XCTAssertEqual(engine.planItems[1].itemType, "Song")
    }

    func testEditAppliesToARangeAndRelativeTime() {
        let engine = makeEngine()
        _ = run(engine, "cue 2 thru 3 time +60 trigger follow")
        XCTAssertEqual(engine.planItems[1].lengthInSeconds, 300)
        XCTAssertEqual(engine.planItems[2].lengthInSeconds, 1260)
        XCTAssertEqual(engine.planItems[1].trigger, .follow)
        XCTAssertNil(engine.planItems[0].trigger)
    }

    func testEditUsesTheSelectionWithoutAnItemClause() {
        let engine = makeEngine()
        _ = run(engine, "time 2m", selected: "c")
        XCTAssertEqual(engine.planItems[2].lengthInSeconds, 120)
    }

    func testRolesByName() {
        let engine = makeEngine()
        _ = run(engine, "cue 2 role band + host")
        XCTAssertEqual(engine.planItems[1].cueRoleIds, ["band", "host"])
    }

    func testMoveDownAndUp() {
        let engine = makeEngine()
        _ = run(engine, "move cue 1 at 3")
        XCTAssertEqual(engine.planItems.map(\.id), ["b", "c", "a", "d"])
        _ = run(engine, "move cue 4 at 1")
        XCTAssertEqual(engine.planItems.map(\.id), ["d", "b", "c", "a"])
    }

    func testCopyDuplicatesToPosition() {
        let engine = makeEngine()
        _ = run(engine, "copy cue 2 at 4")
        XCTAssertEqual(engine.planItems.map(\.title), ["Welcome", "Song", "Message", "Song", "Close"])
        XCTAssertNotEqual(engine.planItems[1].id, engine.planItems[3].id)
    }

    func testDeleteRangeAndConfirmationPrompt() {
        let engine = makeEngine()
        let analysis = CommandLine.analyze("delete cue 2 thru 3 ", context: engine.commandLineContext(selectedItemId: nil))
        let statement = analysis.statement!
        XCTAssertEqual(engine.commandConfirmationPrompt(statement, selectedItemId: nil), "Delete 2 cues? Press Enter again.")
        engine.runCommand(statement, selectedItemId: nil)
        XCTAssertEqual(engine.planItems.map(\.id), ["a", "d"])
    }

    func testLabelRenames() {
        let engine = makeEngine()
        _ = run(engine, "label cue 1 \"Greeting\"")
        XCTAssertEqual(engine.planItems[0].title, "Greeting")
    }
}

final class CommandLineActionTests: XCTestCase {
    private func analyze(_ text: String, documents: Bool = false) -> CommandLineAnalysis {
        CommandLine.analyze(text, context: CommandLineContext(itemCount: 4, documentActions: documents))
    }

    func testViewResolvesATabByPrefix() {
        let result = analyze("vi ru ")
        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.statement?.action, .view(.serviceFlow))
        XCTAssertEqual(result.pieces.map(\.text), ["View", "Run Sheet"])
    }

    func testViewNeedsATab() {
        guard case .incomplete = analyze("view ").status else { return XCTFail("expected incomplete") }
        XCTAssertEqual(analyze("view ").suggestions.map(\.word), ["Pagers", "Run Sheet", "Messages", "Settings"])
    }

    func testPlaybackWordsAreReadyAlone() {
        XCTAssertEqual(analyze("play ").statement?.action, .play)
        XCTAssertEqual(analyze("pau ").statement?.action, .pause)
        XCTAssertEqual(analyze("ne ").statement?.action, .next)
        XCTAssertEqual(analyze("reset ").statement?.action, .reset)
    }

    func testAmbiguousPrefixBlocks() {
        guard case .ambiguous = analyze("p ").status else { return XCTFail("expected ambiguous") }
    }

    func testDocumentWordsNeedAHandler() {
        guard case .invalid = analyze("save ").status else { return XCTFail("expected invalid") }
        XCTAssertEqual(analyze("save ", documents: true).statement?.action, .save)
        XCTAssertFalse(analyze("").suggestions.map(\.word).contains("Save"))
        XCTAssertTrue(analyze("", documents: true).suggestions.map(\.word).contains("Save"))
    }

    func testNothingFollowsAnAction() {
        guard case .invalid = analyze("play cue 3 ").status else { return XCTFail("expected invalid") }
    }
}

@MainActor
final class CommandLineActionExecutionTests: XCTestCase {
    func testViewSwitchesTheTab() {
        let engine = CueEngine()
        let statement = CommandLine.analyze("view mess ", context: engine.commandLineContext(selectedItemId: nil)).statement!
        engine.runCommand(statement, selectedItemId: nil)
        XCTAssertEqual(engine.appMode, .messages)
    }

    func testDocumentActionsGoToTheHandler() {
        let engine = CueEngine()
        var received: CommandAction?
        engine.documentCommandHandler = { received = $0 }
        let statement = CommandLine.analyze("save ", context: engine.commandLineContext(selectedItemId: nil)).statement!
        engine.runCommand(statement, selectedItemId: nil)
        XCTAssertEqual(received, .save)
    }
}

final class CommandLinePartialSubmitTests: XCTestCase {
    private let context = CommandLineContext(itemCount: 6)

    func testAUniquePartialWordCountsAsFinished() {
        let result = CommandLine.analyze("vi p", context: context)
        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.statement?.action, .view(.producerControl))
    }

    func testATrailingNumberCountsAsFinished() {
        let result = CommandLine.analyze("delete cue 4", context: context)
        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.statement?.position, 4)
    }

    func testAnAmbiguousPartialStaysBlocked() {
        XCTAssertNil(CommandLine.analyze("p", context: context).statement)
        XCTAssertNil(CommandLine.analyze("cue 4 t", context: context).statement)
    }

    func testAnIncompleteLineStaysIncomplete() {
        XCTAssertNil(CommandLine.analyze("vi", context: context).statement)
    }
}

@MainActor
final class CommandLineUndoTests: XCTestCase {
    private func makeEngine() -> CueEngine {
        let engine = CueEngine()
        engine.importFlow(title: "Sunday", items: [
            PCOTimerItem(id: "a", title: "Welcome", itemType: "Item", lengthInSeconds: 60),
            PCOTimerItem(id: "b", title: "Song", itemType: "Song", lengthInSeconds: 240),
            PCOTimerItem(id: "c", title: "Close", itemType: "Item", lengthInSeconds: 60)
        ])
        return engine
    }

    @discardableResult
    private func run(_ engine: CueEngine, _ text: String) -> CommandOutcome? {
        let analysis = CommandLine.analyze(text + " ", context: engine.commandLineContext(selectedItemId: nil))
        guard let statement = analysis.statement else {
            XCTFail("not ready: \(analysis.status)")
            return nil
        }
        return engine.runCommand(statement, selectedItemId: nil)
    }

    func testOopsAndUndoResolveToUndoAndStayOutOfTheList() {
        let context = CommandLineContext()
        XCTAssertEqual(CommandLine.analyze("oops ", context: context).statement?.action, .undo)
        XCTAssertEqual(CommandLine.analyze("und ", context: context).statement?.action, .undo)
        XCTAssertEqual(CommandLine.analyze("oops ", context: context).pieces.map(\.text), ["Undo"])
        XCTAssertFalse(CommandLine.analyze("", context: context).suggestions.map(\.word).contains("Undo"))
    }

    func testUndoRestoresADelete() {
        let engine = makeEngine()
        run(engine, "delete cue 2")
        XCTAssertEqual(engine.planItems.map(\.id), ["a", "c"])
        let outcome = run(engine, "oops")
        XCTAssertEqual(engine.planItems.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(outcome?.message, "Undid delete")
    }

    func testUndoRestoresATimeEditAndAMove() {
        let engine = makeEngine()
        run(engine, "cue 1 time 5m")
        run(engine, "move cue 3 at 1")
        XCTAssertEqual(engine.planItems.map(\.id), ["c", "a", "b"])
        run(engine, "undo")
        XCTAssertEqual(engine.planItems.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(engine.planItems[0].lengthInSeconds, 300)
        run(engine, "undo")
        XCTAssertEqual(engine.planItems[0].lengthInSeconds, 60)
    }

    func testUndoWithNothingToUndo() {
        let engine = makeEngine()
        XCTAssertEqual(run(engine, "undo")?.message, "Nothing to undo")
    }
}


final class CommandLineNounTests: XCTestCase {
    private let context = CommandLineContext(
        itemTypes: ["Item", "Song"], roles: ["Band", "Host", "Lighting"], itemCount: 6,
        waypoints: ["Offering", "Closing"], eventCount: 2, rehearsalCount: 1, scheduleCount: 1
    )

    private func analyze(_ text: String) -> CommandLineAnalysis { CommandLine.analyze(text, context: context) }

    func testItemStillWorksAsAHiddenAliasForCue() {
        XCTAssertEqual(analyze("delete item 3 ").pieces.map(\.text), ["Delete", "Cue", "3"])
        XCTAssertFalse(analyze("delete ").suggestions.map(\.word).contains("Item"))
        XCTAssertTrue(analyze("delete ").suggestions.map(\.word).contains("Cue"))
    }

    func testNewAndCreateAreAliasesForStore() {
        XCTAssertEqual(analyze("new role \"Cam 2\" ").pieces.map(\.text), ["Store", "Role", "\"Cam 2\""])
        XCTAssertEqual(analyze("create role \"Cam 2\" ").statement?.generic.key, "store.role")
        XCTAssertFalse(analyze("").suggestions.map(\.word).contains("New"))
    }

    func testStoringOnAnExistingCueAsksInsertOrReplace() throws {
        let asking = analyze("store cue 4 ")
        guard case .choice = asking.status else { return XCTFail("expected a choice, got \(asking.status)") }
        XCTAssertEqual(asking.suggestions.map(\.word).prefix(2), ["Insert", "Replace"])
        XCTAssertEqual(analyze("store cue 4 replace ").statement?.storeMode, .replace)
        XCTAssertEqual(analyze("store cue 4 insert ").statement?.storeMode, .insert)
        XCTAssertEqual(analyze("store cue 7 ").status, .ready)
        XCTAssertEqual(analyze("store ").status, .ready)
    }

    func testRoleNounWorksWithStandbyGoAndClear() {
        let standby = analyze("standby role band + host ")
        XCTAssertEqual(standby.status, .ready)
        XCTAssertEqual(standby.statement?.generic.key, "standby.role")
        XCTAssertEqual(standby.statement?.generic.names, ["Band", "Host"])
        XCTAssertEqual(analyze("go role light ").statement?.generic.names, ["Lighting"])
        XCTAssertEqual(analyze("clear role band ").statement?.generic.key, "clear.role")
        XCTAssertEqual(analyze("standby cue 3 ").statement?.verb, .standby)
    }

    func testClearAloneClearsEveryCue() {
        XCTAssertEqual(analyze("clear ").statement?.action, .clearCues)
    }

    func testRoleLabelAndStore() {
        XCTAssertEqual(analyze("label role band \"Praise\" ").statement?.generic.text, "Praise")
        XCTAssertEqual(analyze("store role \"Cam 2\" ").statement?.generic.text, "Cam 2")
        guard case .incomplete = analyze("store role ").status else { return XCTFail("expected incomplete") }
    }

    func testMessages() {
        let result = analyze("store message \"Wrap up\" role band ")
        XCTAssertEqual(result.statement?.generic.text, "Wrap up")
        XCTAssertEqual(result.statement?.generic.names, ["Band"])
        XCTAssertEqual(analyze("store message \"Hi\" ").status, .ready)
        XCTAssertEqual(analyze("delete message ").statement?.generic.key, "delete.message")
        XCTAssertEqual(analyze("clear message ").statement?.generic.key, "clear.message")
    }

    func testWaypoints() {
        XCTAssertEqual(analyze("go waypoint off ").statement?.generic.names, ["Offering"])
        XCTAssertEqual(analyze("store waypoint \"Prayer\" ").statement?.generic.key, "store.waypoint")
        XCTAssertEqual(analyze("delete waypoint clo ").statement?.generic.names, ["Closing"])
        guard case .invalid = analyze("go waypoint zzz ").status else { return XCTFail("expected invalid") }
    }

    func testEventsRehearsalsAndSchedules() {
        XCTAssertEqual(analyze("go event 2 ").statement?.generic.number, 2)
        guard case .invalid = analyze("go event 3 ").status else { return XCTFail("expected invalid") }
        XCTAssertEqual(analyze("next event ").statement?.generic.key, "next.event")
        XCTAssertEqual(analyze("go schedule 1 ").statement?.generic.key, "go.schedule")
        XCTAssertEqual(analyze("delete rehearsal 1 ").statement?.generic.key, "delete.rehearsal")
        let stored = analyze("store event label \"Early\" day sun time 9:00am ")
        XCTAssertEqual(stored.status, .ready)
        XCTAssertEqual(stored.statement?.generic.text, "Early")
        XCTAssertEqual(stored.statement?.generic.day, "sunday")
        XCTAssertEqual(stored.statement?.generic.timeOfDay, "09:00")
        XCTAssertEqual(analyze("store event time 6:30pm ").statement?.generic.timeOfDay, "18:30")
        XCTAssertEqual(analyze("store rehearsal ").status, .ready)
    }

    func testClockPlanAndSet() {
        XCTAssertEqual(analyze("clock + 30 ").statement?.generic.clock, TimerInputParser.parse("+30"))
        XCTAssertEqual(analyze("clock 5m ").statement?.generic.clock, TimerInputParser.parse("5m"))
        XCTAssertEqual(analyze("plan ti \"Sunday\" ").statement?.generic.key, "plan.title")
        XCTAssertEqual(analyze("set fol on ").statement?.generic.key, "set.follow")
        XCTAssertEqual(analyze("set form 24h ").statement?.generic.choices, ["Format", "24h"])
        XCTAssertEqual(analyze("set thr never ").statement?.generic.key, "set.threshold")
        XCTAssertEqual(analyze("set end off ").statement?.generic.key, "set.endtimes")
        guard case .incomplete = analyze("set format ").status else { return XCTFail("expected incomplete") }
    }

    func testPCOAndPager() {
        XCTAssertEqual(analyze("pco live on ").statement?.generic.key, "pco.live")
        XCTAssertEqual(analyze("pco changes accept ").statement?.generic.key, "pco.changes")
        XCTAssertEqual(analyze("pco unl ").statement?.generic.key, "pco.unlink")
        XCTAssertEqual(analyze("pager ping 10.0.0.5 ").statement?.generic.ip, "10.0.0.5")
        guard case .invalid = analyze("pager ping 10.0.0 ").status else { return XCTFail("expected invalid") }
        XCTAssertEqual(analyze("pager master on ").statement?.generic.key, "pager.master")
    }

    func testSkipAndUnskipTakeCues() {
        XCTAssertEqual(analyze("skip cue 3 ").statement?.verb, .skip)
        XCTAssertEqual(analyze("unskip cue 3 thru 4 ").statement?.count, 2)
    }

    func testNounsOnlyAcceptedWhereTheyMakeSense() {
        guard case .invalid = analyze("move role band ").status else { return XCTFail("expected invalid") }
        guard case .invalid = analyze("standby message ").status else { return XCTFail("expected invalid") }
    }

    func testSuggestionsListNounsAfterAVerb() {
        XCTAssertEqual(analyze("delete ").suggestions.map(\.word), ["Cue", "Role", "Message", "Waypoint", "Event", "Rehearsal", "Schedule"])
        XCTAssertEqual(analyze("go ").suggestions.map(\.word), ["Cue", "Role", "Waypoint", "Event", "Schedule"])
        XCTAssertEqual(analyze("set ").suggestions.map(\.word), ["Format", "Threshold", "Follow", "Endtimes"])
        XCTAssertEqual(analyze("go waypoint ").suggestions.map(\.word), ["Offering", "Closing"])
    }
}

@MainActor
final class CommandLineNounExecutionTests: XCTestCase {
    private func makeEngine() -> CueEngine {
        let engine = CueEngine()
        engine.roles = [RoleCue(id: "band", name: "Band"), RoleCue(id: "host", name: "Host")]
        engine.importFlow(title: "Sunday", items: [
            PCOTimerItem(id: "a", title: "Welcome", itemType: "Item", lengthInSeconds: 60),
            PCOTimerItem(id: "b", title: "Song", itemType: "Song", lengthInSeconds: 240),
            PCOTimerItem(id: "c", title: "Close", itemType: "Item", lengthInSeconds: 60)
        ])
        return engine
    }

    @discardableResult
    private func run(_ engine: CueEngine, _ text: String) -> CommandOutcome? {
        let analysis = CommandLine.analyze(text + " ", context: engine.commandLineContext(selectedItemId: nil))
        guard let statement = analysis.statement else {
            XCTFail("not ready: \(analysis.status) for \(text)")
            return nil
        }
        return engine.runCommand(statement, selectedItemId: nil)
    }

    func testStoreReplaceSwapsTheCueAndInsertPushesDown() {
        let engine = makeEngine()
        run(engine, "store cue 2 replace \"Offering\" time 5m")
        XCTAssertEqual(engine.planItems.map(\.title), ["Welcome", "Offering", "Close"])
        run(engine, "store cue 2 insert \"Prayer\"")
        XCTAssertEqual(engine.planItems.map(\.title), ["Welcome", "Prayer", "Offering", "Close"])
        run(engine, "undo")
        XCTAssertEqual(engine.planItems.map(\.title), ["Welcome", "Offering", "Close"])
    }

    func testRoleLifecycleAndCues() {
        let engine = makeEngine()
        run(engine, "store role \"Cam 2\"")
        XCTAssertTrue(engine.roles.contains { $0.name == "Cam 2" })
        run(engine, "standby role band + host")
        XCTAssertEqual(engine.roles.first { $0.id == "band" }?.state, .standby)
        XCTAssertEqual(engine.roles.first { $0.id == "host" }?.state, .standby)
        run(engine, "go role band")
        XCTAssertEqual(engine.roles.first { $0.id == "band" }?.state, .go)
        run(engine, "clear")
        XCTAssertEqual(engine.roles.first { $0.id == "band" }?.state, .off)
        run(engine, "label role cam \"Camera\"")
        XCTAssertTrue(engine.roles.contains { $0.name == "Camera" })
        run(engine, "delete role camera")
        XCTAssertFalse(engine.roles.contains { $0.name == "Camera" })
    }

    func testWaypointLifecycle() {
        let engine = makeEngine()
        run(engine, "store waypoint \"Offering\"")
        XCTAssertEqual(engine.waypoints.map(\.name), ["Offering"])
        run(engine, "label waypoint off \"Giving\"")
        XCTAssertEqual(engine.waypoints.map(\.name), ["Giving"])
        run(engine, "delete waypoint giv")
        XCTAssertTrue(engine.waypoints.isEmpty)
    }

    func testEventTimes() {
        let engine = makeEngine()
        run(engine, "store event label \"Early\" day sun time 9:00")
        run(engine, "store event label \"Late\" day sun time 11:00")
        XCTAssertEqual(engine.eventTimes.count, 2)
        run(engine, "go event 2")
        XCTAssertEqual(engine.liveEventTimeId, engine.eventTimes[1].id)
        run(engine, "delete event 1")
        XCTAssertEqual(engine.eventTimes.count, 1)
    }

    func testSkipAndUnskip() {
        let engine = makeEngine()
        run(engine, "skip cue 2")
        XCTAssertTrue(engine.skippedItemIds.values.contains { $0.contains("b") })
        run(engine, "unskip cue 2")
        XCTAssertFalse(engine.skippedItemIds.values.contains { $0.contains("b") })
    }

    func testSettingsAndPlanTitle() {
        let engine = makeEngine()
        run(engine, "set follow on")
        XCTAssertTrue(engine.followByDefault)
        run(engine, "set endtimes on")
        XCTAssertTrue(engine.runSheetLayout.displaysEndTimes)
        run(engine, "set threshold never")
        XCTAssertEqual(engine.hourFormatThreshold, .never)
        run(engine, "plan title \"New name\"")
        XCTAssertEqual(engine.planTitle, "New name")
    }

    func testDeleteGenericAsksForConfirmation() {
        let engine = makeEngine()
        let statement = CommandLine.analyze("delete role band ", context: engine.commandLineContext(selectedItemId: nil)).statement!
        XCTAssertEqual(engine.commandConfirmationPrompt(statement, selectedItemId: nil), "Delete role? Press Enter again.")
    }
}


final class CommandLineWaypointAssignTests: XCTestCase {
    private let context = CommandLineContext(itemCount: 6, waypoints: ["Offering", "Closing"])

    private func analyze(_ text: String) -> CommandLineAnalysis { CommandLine.analyze(text, context: context) }

    func testACueTakesWaypointsLikeRoles() {
        let result = analyze("cue 4 waypoint off + clo ")
        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.statement?.waypoints, ["Offering", "Closing"])
        XCTAssertEqual(result.pieces.map(\.text), ["Cue", "4", "Waypoint", "Offering", "+", "Closing"])
    }

    func testNoneClearsAndAQuotedNameCreates() {
        XCTAssertEqual(analyze("cue 4 waypoint none ").statement?.clearsWaypoints, true)
        XCTAssertEqual(analyze("cue 4 waypoint \"Prayer\" ").statement?.waypoints, ["Prayer"])
        guard case .invalid = analyze("cue 4 waypoint zzz ").status else { return XCTFail("expected invalid") }
    }

    func testStoreWaypointStillMeansTheNounRightAfterAVerb() {
        XCTAssertEqual(analyze("store waypoint \"Prayer\" ").statement?.generic.key, "store.waypoint")
        XCTAssertEqual(analyze("store cue 9 \"Hymn\" waypoint off ").statement?.waypoints, ["Offering"])
    }

    func testSuggestionsOfferNone() {
        XCTAssertEqual(analyze("cue 4 waypoint ").suggestions.map(\.word), ["Offering", "Closing", "None"])
    }
}

@MainActor
final class CommandLineWaypointAssignExecutionTests: XCTestCase {
    private func makeEngine() -> CueEngine {
        let engine = CueEngine()
        engine.importFlow(title: "Sunday", items: [
            PCOTimerItem(id: "a", title: "Welcome", itemType: "Item", lengthInSeconds: 60),
            PCOTimerItem(id: "b", title: "Song", itemType: "Song", lengthInSeconds: 240)
        ])
        return engine
    }

    @discardableResult
    private func run(_ engine: CueEngine, _ text: String) -> CommandOutcome? {
        let analysis = CommandLine.analyze(text + " ", context: engine.commandLineContext(selectedItemId: nil))
        guard let statement = analysis.statement else {
            XCTFail("not ready: \(analysis.status)")
            return nil
        }
        return engine.runCommand(statement, selectedItemId: nil)
    }

    func testAssignCreateMoveAndClear() {
        let engine = makeEngine()
        run(engine, "store waypoint \"Offering\"")
        run(engine, "cue 2 waypoint off")
        XCTAssertEqual(engine.waypoints(forItemId: "b").map(\.name), ["Offering"])
        run(engine, "cue 1 waypoint off")
        XCTAssertEqual(engine.waypoints(forItemId: "a").map(\.name), ["Offering"])
        XCTAssertTrue(engine.waypoints(forItemId: "b").isEmpty)
        run(engine, "cue 1 waypoint \"Prayer\"")
        XCTAssertEqual(engine.waypoints(forItemId: "a").map(\.name), ["Prayer"])
        run(engine, "cue 1 waypoint none")
        XCTAssertTrue(engine.waypoints(forItemId: "a").isEmpty)
    }

    func testStoringACueWithAWaypointAndUndo() {
        let engine = makeEngine()
        run(engine, "store waypoint \"Offering\"")
        run(engine, "store cue 3 \"Giving\" waypoint off")
        XCTAssertEqual(engine.planItems.last?.title, "Giving")
        XCTAssertEqual(engine.waypoints(forItemId: engine.planItems.last!.id).map(\.name), ["Offering"])
        run(engine, "undo")
        XCTAssertEqual(engine.planItems.count, 2)
    }
}
