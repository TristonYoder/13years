// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

@MainActor
final class PCODelegatedSignInTests: XCTestCase {
    private var savedTokens: OAuthTokens?
    private var hadClientID = false

    override func setUp() {
        super.setUp()
        savedTokens = KeychainStore.codable(OAuthTokens.self, forKey: "pcoOAuthTokens")
        hadClientID = !OAuthConfig.clientID.isEmpty
        setenv("THIRTEEN_PCO_CLIENT_ID", "test-client-id", 1)
    }

    override func tearDown() {
        unsetenv("THIRTEEN_PCO_CLIENT_ID")
        KeychainStore.setCodable(savedTokens, forKey: "pcoOAuthTokens")
        super.tearDown()
    }

    private func makeEngine(now: @escaping () -> Date = { Date() }) -> (CueEngine, Counter) {
        let engine = CueEngine()
        let counter = Counter()
        engine.pcoSignInClock = now
        engine.pcoTokenExchange = { code, verifier in
            await counter.record(code: code, verifier: verifier)
            return OAuthTokens(accessToken: "access", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600))
        }
        engine.pcoSignInFollowUp = { $0.pcoUserName = "Remote Person" }
        return (engine, counter)
    }

    private func post(_ engine: CueEngine, _ path: String, _ body: Data = Data()) -> HTTPResponse {
        ControlAPIRouter(engine: engine).handle(HTTPRequest(method: "POST", path: path, body: body))
    }

    func testBeginBuildsAuthorizeURLAndStoresPending() throws {
        let (engine, _) = makeEngine()
        let grant = try engine.beginDelegatedPCOSignIn()
        let items = URLComponents(url: grant.authorizeURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(value("client_id"), "test-client-id")
        XCTAssertEqual(value("redirect_uri"), OAuthConfig.redirectURI)
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("scope"), OAuthConfig.scope)
        XCTAssertEqual(value("state"), grant.state)
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertFalse((value("code_challenge") ?? "").isEmpty)
        XCTAssertEqual(engine.pendingPCOSignIn?.state, grant.state)
    }

    func testCompleteExchangesWithStoredVerifierAndConnects() async throws {
        let (engine, counter) = makeEngine()
        let grant = try engine.beginDelegatedPCOSignIn()
        let verifier = engine.pendingPCOSignIn?.verifier
        try await engine.completeDelegatedPCOSignIn(code: "abc", state: grant.state)
        let seen = await counter.last
        XCTAssertEqual(seen?.code, "abc")
        XCTAssertEqual(seen?.verifier, verifier)
        XCTAssertTrue(engine.isPCOConnected)
        XCTAssertNotNil(engine.pcoOAuthTokens)
        XCTAssertEqual(engine.pcoUserName, "Remote Person")
        XCTAssertNil(engine.pendingPCOSignIn)
    }

    func testCompleteRejectsWrongState() async throws {
        let (engine, counter) = makeEngine()
        _ = try engine.beginDelegatedPCOSignIn()
        do {
            try await engine.completeDelegatedPCOSignIn(code: "abc", state: "nope")
            XCTFail("expected failure")
        } catch {
            guard case OAuthError.stateMismatch = error else { return XCTFail("\(error)") }
        }
        let seen = await counter.last
        XCTAssertNil(seen)
        XCTAssertFalse(engine.isPCOConnected)
        XCTAssertNil(engine.pendingPCOSignIn)
    }

    func testCompleteRejectsWithoutPendingAndWhenExpired() async throws {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let (engine, _) = makeEngine(now: { clock })
        do {
            try await engine.completeDelegatedPCOSignIn(code: "c", state: "s")
            XCTFail("expected failure")
        } catch {
            guard case OAuthError.noPendingSignIn = error else { return XCTFail("\(error)") }
        }
        let grant = try engine.beginDelegatedPCOSignIn()
        clock.addTimeInterval(CueEngine.delegatedSignInLifetime + 1)
        do {
            try await engine.completeDelegatedPCOSignIn(code: "c", state: grant.state)
            XCTFail("expected failure")
        } catch {
            guard case OAuthError.signInExpired = error else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(engine.isPCOConnected)
    }

    func testAuthorizeRoute() throws {
        let (engine, _) = makeEngine()
        let response = post(engine, "/v1/pco/authorize")
        XCTAssertEqual(response.status, 200)
        let grant = try ControlAPIJSON.decoder.decode(ControlAPIRequests.PCOAuthorization.self, from: response.body)
        XCTAssertEqual(grant.redirectURI, OAuthConfig.redirectURI)
        XCTAssertTrue(grant.authorizeURL.contains("code_challenge="))
        XCTAssertEqual(engine.pendingPCOSignIn?.state, grant.state)
    }

    func testAuthorizeRouteIs409WithoutClientID() throws {
        try XCTSkipIf(hadClientID, "A client ID is bundled in this build.")
        unsetenv("THIRTEEN_PCO_CLIENT_ID")
        let (engine, _) = makeEngine()
        XCTAssertEqual(post(engine, "/v1/pco/authorize").status, 409)
    }

    func testCompleteRouteValidatesBodyAndCompletesAsynchronously() async throws {
        let (engine, _) = makeEngine()
        XCTAssertEqual(post(engine, "/v1/pco/authorize/complete", Data("{}".utf8)).status, 400)
        XCTAssertEqual(post(engine, "/v1/pco/authorize/complete", Data(#"{"code":"","state":"x"}"#.utf8)).status, 400)

        let grant = try engine.beginDelegatedPCOSignIn()
        let body = try ControlAPIJSON.encoder.encode(ControlAPIRequests.PCOAuthorizeCompleteBody(code: "abc", state: grant.state))
        XCTAssertEqual(post(engine, "/v1/pco/authorize/complete", body).status, 202)
        for _ in 0..<100 where !engine.isPCOConnected { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(engine.isPCOConnected)
    }

    func testCompleteRouteFailureLandsInLastError() async throws {
        let (engine, _) = makeEngine()
        let body = try ControlAPIJSON.encoder.encode(ControlAPIRequests.PCOAuthorizeCompleteBody(code: "abc", state: "x"))
        XCTAssertEqual(post(engine, "/v1/pco/authorize/complete", body).status, 202)
        for _ in 0..<100 where engine.pcoLastError == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(engine.pcoLastError, OAuthError.noPendingSignIn.localizedDescription)
    }

    func testMirrorAuthorizeCommandsTargetThePCORoutes() {
        XCTAssertEqual(RemoteCommand.pcoAuthorize.request.path, "/v1/pco/authorize")
        XCTAssertEqual(RemoteCommand.pcoSignOut.request.path, "/v1/pco/sign-out")
        let complete = RemoteCommand.pcoAuthorizeComplete(code: "c", state: "s").request
        XCTAssertEqual(complete.path, "/v1/pco/authorize/complete")
        let decoded = try? ControlAPIJSON.decoder.decode(ControlAPIRequests.PCOAuthorizeCompleteBody.self, from: complete.body ?? Data())
        XCTAssertEqual(decoded, .init(code: "c", state: "s"))
    }
}

actor Counter {
    var last: (code: String, verifier: String)?
    func record(code: String, verifier: String) { last = (code, verifier) }
}
