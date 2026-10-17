// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class RoleTeamPositionTests: XCTestCase {
    private func person(_ id: String, _ name: String, team: String = "Band", position: String = "Keys", status: String = "C") -> PCOPlanPersonInfo {
        PCOPlanPersonInfo(id: id, name: name, teamName: team, positionName: position, status: status)
    }

    private func engine(team: [PCOPlanPersonInfo], roles: [RoleCue]) -> CueEngine {
        let engine = CueEngine(startsNetworking: false)
        engine.roles = roles
        engine.pcoPlanContext = PCOPlanContext(planId: "p", serviceTypeId: "st", team: team)
        return engine
    }

    func testLinkedRoleFillsWithConfirmedPersonOverUnconfirmed() {
        let engine = engine(
            team: [person("1", "Una Unsure", status: "U"), person("2", "Cora Confirmed")],
            roles: [RoleCue(id: "keys", name: "Keys", pcoTeamPosition: "Band \u{203A} Keys")]
        )
        engine.applyPCOTeamAssignments()
        XCTAssertEqual(engine.roles.first?.personName, "Cora")
    }

    func testFallsBackToUnconfirmedAndIgnoresDeclined() {
        let engine = engine(
            team: [person("1", "Dan Declined", status: "D"), person("2", "Una Unsure", status: "U")],
            roles: [RoleCue(id: "keys", name: "Keys", pcoTeamPosition: "Band \u{203A} Keys")]
        )
        engine.applyPCOTeamAssignments()
        XCTAssertEqual(engine.roles.first?.personName, "Una")
    }

    func testOnlyDeclinedLeavesNameEmpty() {
        let engine = engine(
            team: [person("1", "Dan Declined", status: "D")],
            roles: [RoleCue(id: "keys", name: "Keys", pcoTeamPosition: "Band \u{203A} Keys")]
        )
        engine.applyPCOTeamAssignments()
        XCTAssertNil(engine.roles.first?.personName)
    }

    func testSeveralConfirmedPeopleAreJoinedByFirstName() {
        let engine = engine(
            team: [person("1", "Ana Lee"), person("2", "Ben Ray"), person("3", "Cy Unsure", status: "U")],
            roles: [RoleCue(id: "keys", name: "Keys", pcoTeamPosition: "Band \u{203A} Keys")]
        )
        engine.applyPCOTeamAssignments()
        XCTAssertEqual(engine.roles.first?.personName, "Ana & Ben")
    }

    func testSharedFirstNamesUseFullNames() {
        let engine = engine(
            team: [person("1", "Sam Lee"), person("2", "Sam Ray")],
            roles: [RoleCue(id: "keys", name: "Keys", pcoTeamPosition: "Band \u{203A} Keys")]
        )
        engine.applyPCOTeamAssignments()
        XCTAssertEqual(engine.roles.first?.personName, "Sam Lee & Sam Ray")
    }

    func testManualNameIsKept() {
        let engine = engine(
            team: [person("1", "Cora Confirmed")],
            roles: [RoleCue(id: "keys", name: "Keys", personName: "Whoever Showed Up", pcoTeamPosition: "Band \u{203A} Keys")]
        )
        engine.applyPCOTeamAssignments()
        XCTAssertEqual(engine.roles.first?.personName, "Whoever Showed Up")
    }

    func testUnlinkedRoleIsLeftAlone() {
        let engine = engine(team: [person("1", "Cora Confirmed")], roles: [RoleCue(id: "keys", name: "Keys")])
        engine.applyPCOTeamAssignments()
        XCTAssertNil(engine.roles.first?.personName)
    }

    func testLinkingFillsImmediatelyAndUnlinkingStopsFurtherFills() {
        let engine = engine(team: [person("1", "Cora Confirmed")], roles: [RoleCue(id: "keys", name: "Keys")])
        engine.setPCOTeamPosition(forRoleId: "keys", "Band \u{203A} Keys")
        XCTAssertEqual(engine.roles.first?.pcoTeamPosition, "Band \u{203A} Keys")
        XCTAssertEqual(engine.roles.first?.personName, "Cora")

        engine.setPersonName(forRoleId: "keys", personName: nil)
        engine.setPCOTeamPosition(forRoleId: "keys", nil)
        XCTAssertNil(engine.roles.first?.pcoTeamPosition)
        engine.applyPCOTeamAssignments()
        XCTAssertNil(engine.roles.first?.personName)
    }

    func testContextRefreshFillsLinkedRoles() async {
        let engine = CueEngine(startsNetworking: false)
        engine.isPCOConnected = true
        let item = PCOTimerItem(id: "a", title: "A", lengthInSeconds: 60, pcoServiceTypeId: "st", pcoPlanId: "p")
        engine.importFlow(title: "Sunday", items: [item])
        engine.roles = [RoleCue(id: "keys", name: "Keys", pcoTeamPosition: "Band \u{203A} Keys")]
        let team = [person("1", "Cora Confirmed")]
        engine.pcoChangeTracking.fetchContext = { _, planId in PCOPlanContext(planId: planId, serviceTypeId: "st", team: team) }

        await engine.refreshPCOPlanContext()

        XCTAssertEqual(engine.roles.first?.personName, "Cora")
        XCTAssertNil(engine.pcoPlanContextError)
    }

    func testPositionReferencesListTeamAndNeededPositionsOnce() {
        let context = PCOPlanContext(
            planId: "p", serviceTypeId: "st",
            team: [person("1", "A"), person("2", "B", position: "Drums")],
            neededPositions: [PCONeededPositionInfo(teamName: "Band", positionName: "Keys", quantity: 1), PCONeededPositionInfo(teamName: "Tech", positionName: "Lyrics", quantity: 1)]
        )
        XCTAssertEqual(context.teamPositionReferences, ["Band \u{203A} Drums", "Band \u{203A} Keys", "Tech \u{203A} Lyrics"])
        let parsed = PCOTeamPositionLink.parse("Band \u{203A} Keys")
        XCTAssertEqual(parsed.team, "Band")
        XCTAssertEqual(parsed.position, "Keys")
    }

    func testLegacyRoleDecodesWithoutTeamPosition() throws {
        let json = #"{"id":"r","name":"Band","state":"OFF","lastUpdated":0,"assignedNoteCategories":[]}"#
        let role = try JSONDecoder().decode(RoleCue.self, from: Data(json.utf8))
        XCTAssertNil(role.pcoTeamPosition)
        var linked = role
        linked.pcoTeamPosition = "Band \u{203A} Keys"
        let decoded = try JSONDecoder().decode(RoleCue.self, from: JSONEncoder().encode(linked))
        XCTAssertEqual(decoded.pcoTeamPosition, "Band \u{203A} Keys")
    }

    func testPatchLinksAndUnlinksTeamPosition() throws {
        let engine = engine(team: [person("1", "Cora Confirmed")], roles: [RoleCue(id: "host", name: "Host")])
        let router = ControlAPIRouter(engine: engine)
        func patch(_ json: String) -> HTTPResponse {
            router.handle(HTTPRequest(method: "PATCH", path: "/v1/roles/host", body: Data(json.utf8)))
        }
        let linked = patch(#"{"pcoTeamPosition":"Band › Keys"}"#)
        XCTAssertEqual(linked.status, 200)
        XCTAssertEqual(engine.roles.first?.pcoTeamPosition, "Band \u{203A} Keys")
        XCTAssertEqual(engine.roles.first?.personName, "Cora")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: linked.body) as? [String: Any])
        XCTAssertEqual(object["pcoTeamPosition"] as? String, "Band \u{203A} Keys")

        XCTAssertEqual(patch(#"{"name":"Host"}"#).status, 200)
        XCTAssertEqual(engine.roles.first?.pcoTeamPosition, "Band \u{203A} Keys")
        XCTAssertEqual(patch(#"{"pcoTeamPosition":""}"#).status, 200)
        XCTAssertNil(engine.roles.first?.pcoTeamPosition)
        let tooLong = String(repeating: "x", count: 250)
        XCTAssertEqual(patch(#"{"pcoTeamPosition":"\#(tooLong)"}"#).status, 400)
    }

    func testRefreshRouteNeedsAPlanAndStateCarriesContext() throws {
        let engine = engine(team: [person("1", "Cora")], roles: [])
        engine.planItems = []
        engine.activeTimerItem = nil
        let router = ControlAPIRouter(engine: engine)
        let refresh = router.handle(HTTPRequest(method: "POST", path: "/v1/pco/plan-context/refresh", body: Data()))
        XCTAssertEqual(refresh.status, 409)
        XCTAssertEqual(RemoteCommand.pcoPlanContextRefresh.request.path, "/v1/pco/plan-context/refresh")

        let state = try ControlAPIJSON.decoder.decode(ControlAPIState.self, from: router.handle(HTTPRequest(method: "GET", path: "/v1/state", body: Data())).body)
        XCTAssertEqual(state.pco.planContext?.team.first?.name, "Cora")

        let mirror = CueEngine(mirroring: nil)
        mirror.apply(remoteState: state)
        XCTAssertEqual(mirror.pcoPlanContext?.planId, "p")
    }
}
