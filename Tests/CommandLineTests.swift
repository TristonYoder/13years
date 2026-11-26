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
        XCTAssertEqual(translation("sto it 3 "), "Store Item 3")
        XCTAssertEqual(translation("sto \"Offering\" ti 5m "), "Store \"Offering\" Time 5m")
        XCTAssertEqual(translation("it 4 thru 6 ty so "), "Item 4 Thru 6 Type Song")
    }

    func testAmbiguousWordBlocksTheCommand() {
        let result = analyze("it 4 t ")
        guard case .ambiguous = result.status else { return XCTFail("expected ambiguous, got \(result.status)") }
        XCTAssertNil(result.statement)
    }

    func testUnknownWordIsInvalid() {
        guard case .invalid = analyze("sto zzz ").status else { return XCTFail("expected invalid") }
    }

    func testStoreBuildsStatementWithTimeAndTrigger() throws {
        let result = analyze("store item 3 thru 5 \"Hymn\" time 4:30 trigger follow ")
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
        let result = analyze("item 2 time + 30 ")
        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.pieces.map(\.text), ["Item", "2", "Time", "+30"])
        XCTAssertEqual(result.statement?.length, TimerInputParser.parse("+30"))
    }

    func testBadTimeIsInvalid() {
        guard case .invalid = analyze("item 2 time zz ").status else { return XCTFail("expected invalid") }
    }

    func testRolesJoinWithPlus() throws {
        let result = analyze("item 4 role band + host ")
        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.statement?.roles, ["Band", "Host"])
    }

    func testUnknownRoleIsInvalid() {
        guard case .invalid = analyze("item 4 role zzz ").status else { return XCTFail("expected invalid") }
    }

    func testEditVerbsNeedATarget() {
        guard case .incomplete = analyze("delete ").status else { return XCTFail("expected incomplete") }
        XCTAssertEqual(analyze("delete ", selection: true).status, .ready)
        XCTAssertEqual(analyze("delete item 4 thru 6 ").status, .ready)
    }

    func testMoveAndCopyNeedAPosition() throws {
        guard case .incomplete = analyze("move item 5 ").status else { return XCTFail("expected incomplete") }
        let statement = try XCTUnwrap(analyze("move item 5 at 2 ").statement)
        XCTAssertEqual(statement.verb, .move)
        XCTAssertEqual(statement.target, 2)
        XCTAssertEqual(analyze("copy item 2 at 7 ").statement?.verb, .copy)
    }

    func testItemBeyondTheRunSheetIsInvalid() {
        guard case .invalid = analyze("delete item 12 ").status else { return XCTFail("expected invalid") }
        XCTAssertEqual(analyze("store item 12 ").status, .ready)
    }

    func testGoIsAVerbAtTheStartAndAValueAfterTrigger() {
        XCTAssertEqual(analyze("go item 3 ").statement?.verb, .go)
        XCTAssertEqual(analyze("item 3 trigger go ").statement?.trigger, .go)
    }

    func testSuggestionsFollowTheGrammar() {
        XCTAssertEqual(analyze("").suggestions.map(\.word).first, "Store")
        XCTAssertEqual(analyze("item 3 trigger ").suggestions.map(\.word), ["Follow", "Go"])
        XCTAssertEqual(analyze("item 3 type ").suggestions.map(\.word), ["Item", "Song", "Header", "Media"])
        XCTAssertEqual(analyze("item 3 role band + ").suggestions.map(\.word), ["Host", "Lighting"])
        XCTAssertTrue(analyze("item 3 time ").suggestions.isEmpty)
        XCTAssertFalse(analyze("item 3 time 5m ").suggestions.map(\.word).contains("Time"))
    }

    func testGhostAndCompletion() throws {
        let result = analyze("sto it")
        XCTAssertEqual(result.suggestions.map(\.word), ["Item"])
        XCTAssertEqual(result.ghost, "em")
        XCTAssertEqual(result.completed(with: try XCTUnwrap(result.suggestions.first)), "sto Item ")
        let fresh = analyze("sto ")
        XCTAssertEqual(fresh.completed(with: try XCTUnwrap(fresh.suggestions.first)), "sto Item ")
    }

    func testLeadingNumberDetection() {
        XCTAssertTrue(CommandLine.startsWithNumber("5"))
        XCTAssertTrue(CommandLine.startsWithNumber("  4:30"))
        XCTAssertFalse(CommandLine.startsWithNumber("item 4"))
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
        _ = run(engine, "store item 2 \"Offering\" time 5m type song")
        XCTAssertEqual(engine.planItems.map(\.title), ["Welcome", "Offering", "Song", "Message", "Close"])
        XCTAssertEqual(engine.planItems[1].lengthInSeconds, 300)
        XCTAssertEqual(engine.planItems[1].itemType, "Song")
    }

    func testEditAppliesToARangeAndRelativeTime() {
        let engine = makeEngine()
        _ = run(engine, "item 2 thru 3 time +60 trigger follow")
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
        _ = run(engine, "item 2 role band + host")
        XCTAssertEqual(engine.planItems[1].cueRoleIds, ["band", "host"])
    }

    func testMoveDownAndUp() {
        let engine = makeEngine()
        _ = run(engine, "move item 1 at 3")
        XCTAssertEqual(engine.planItems.map(\.id), ["b", "c", "a", "d"])
        _ = run(engine, "move item 4 at 1")
        XCTAssertEqual(engine.planItems.map(\.id), ["d", "b", "c", "a"])
    }

    func testCopyDuplicatesToPosition() {
        let engine = makeEngine()
        _ = run(engine, "copy item 2 at 4")
        XCTAssertEqual(engine.planItems.map(\.title), ["Welcome", "Song", "Message", "Song", "Close"])
        XCTAssertNotEqual(engine.planItems[1].id, engine.planItems[3].id)
    }

    func testDeleteRangeAndConfirmationPrompt() {
        let engine = makeEngine()
        let analysis = CommandLine.analyze("delete item 2 thru 3 ", context: engine.commandLineContext(selectedItemId: nil))
        let statement = analysis.statement!
        XCTAssertEqual(engine.commandConfirmationPrompt(statement, selectedItemId: nil), "Delete 2 items? Press Enter again.")
        engine.runCommand(statement, selectedItemId: nil)
        XCTAssertEqual(engine.planItems.map(\.id), ["a", "d"])
    }

    func testLabelRenames() {
        let engine = makeEngine()
        _ = run(engine, "label item 1 \"Greeting\"")
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
        XCTAssertEqual(analyze("pla ").statement?.action, .play)
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
        guard case .invalid = analyze("play item 3 ").status else { return XCTFail("expected invalid") }
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
        let result = CommandLine.analyze("delete item 4", context: context)
        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.statement?.position, 4)
    }

    func testAnAmbiguousPartialStaysBlocked() {
        XCTAssertNil(CommandLine.analyze("p", context: context).statement)
        XCTAssertNil(CommandLine.analyze("item 4 t", context: context).statement)
    }

    func testAnIncompleteLineStaysIncomplete() {
        XCTAssertNil(CommandLine.analyze("vi", context: context).statement)
    }
}
