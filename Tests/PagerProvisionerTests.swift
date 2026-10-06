// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

final class PagerProvisionerTests: XCTestCase {

    func testCommandJSONOmitsFieldsThatShouldBeLeftAlone() throws {
        let provisioning = PagerProvisioning(ssid: "Sanctuary", password: "hunter2")
        let json = try provisioning.commandJSON()
        XCTAssertEqual(json, #"{"pass":"hunter2","ssid":"Sanctuary"}"#)
    }

    func testCommandJSONIncludesRoleAndProducerWhenGiven() throws {
        let provisioning = PagerProvisioning(ssid: "Sanctuary", password: "hunter2",
                                             roleID: "host", producerHost: "10.0.1.7")
        let json = try provisioning.commandJSON()
        XCTAssertEqual(json, #"{"pass":"hunter2","producer":"10.0.1.7","role":"host","ssid":"Sanctuary"}"#)
    }

    func testCommandJSONEscapesAwkwardCredentials() throws {
        let provisioning = PagerProvisioning(ssid: #"Guest "Wi-Fi""#, password: #"a\b"c"#)
        let json = try provisioning.commandJSON()
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String]
        XCTAssertEqual(parsed?["ssid"], #"Guest "Wi-Fi""#)
        XCTAssertEqual(parsed?["pass"], #"a\b"c"#)
    }

    func testOpenNetworkSendsAnEmptyPassword() throws {
        let json = try PagerProvisioning(ssid: "Open", password: "").commandJSON()
        XCTAssertEqual(json, #"{"pass":"","ssid":"Open"}"#)
    }

    func testRotationIsOmittedWhenUnspecified() throws {
        let json = try PagerProvisioning(ssid: "n", password: "p").commandJSON()
        XCTAssertFalse(json.contains("rotate180"))
    }

    func testRotationIsSentAsAJSONBooleanNotAString() throws {
        let on = try PagerProvisioning(ssid: "n", password: "p", rotate180: true).commandJSON()
        XCTAssertTrue(on.contains("\"rotate180\":true"))
        let parsed = try JSONSerialization.jsonObject(with: Data(on.utf8)) as? [String: Any]
        XCTAssertEqual(parsed?["rotate180"] as? Bool, true)

        let off = try PagerProvisioning(ssid: "n", password: "p", rotate180: false).commandJSON()
        XCTAssertTrue(off.contains("\"rotate180\":false"))
    }

    func testRedactedDescriptionReportsRotation() {
        XCTAssertTrue(PagerProvisioning(ssid: "n", password: "p", rotate180: true)
            .redactedDescription.contains("rotation=180"))
        XCTAssertTrue(PagerProvisioning(ssid: "n", password: "p")
            .redactedDescription.contains("rotation=unchanged"))
    }

    func testValidationAcceptsATypicalNetwork() {
        XCTAssertNil(PagerProvisioning(ssid: "Church Guest", password: "hunter2").validationError)
    }

    func testValidationRejectsEmptySSID() {
        XCTAssertNotNil(PagerProvisioning(ssid: "", password: "x").validationError)
    }

    func testValidationEnforces802Dot11Limits() {
        XCTAssertNil(PagerProvisioning(ssid: String(repeating: "a", count: 32), password: "x").validationError)
        XCTAssertNotNil(PagerProvisioning(ssid: String(repeating: "a", count: 33), password: "x").validationError)
        XCTAssertNil(PagerProvisioning(ssid: "n", password: String(repeating: "p", count: 63)).validationError)
        XCTAssertNotNil(PagerProvisioning(ssid: "n", password: String(repeating: "p", count: 64)).validationError)
    }

    func testValidationCountsBytesNotCharacters() {
        let ssid = String(repeating: "🎛", count: 9)
        XCTAssertNotNil(PagerProvisioning(ssid: ssid, password: "x").validationError)
    }

    func testValidationChecksProducerAddress() {
        XCTAssertNil(PagerProvisioning(ssid: "n", password: "p", producerHost: "10.0.1.7").validationError)
        XCTAssertNil(PagerProvisioning(ssid: "n", password: "p", producerHost: "auto").validationError)
        XCTAssertNotNil(PagerProvisioning(ssid: "n", password: "p", producerHost: "10.0.1").validationError)
        XCTAssertNotNil(PagerProvisioning(ssid: "n", password: "p", producerHost: "10.0.1.999").validationError)
        XCTAssertNotNil(PagerProvisioning(ssid: "n", password: "p", producerHost: "producer.local").validationError)
    }

    func testRedactedDescriptionNeverCarriesThePassword() {
        let provisioning = PagerProvisioning(ssid: "Sanctuary", password: "correct horse battery")
        let described = provisioning.redactedDescription
        XCTAssertFalse(described.contains("correct horse battery"))
        XCTAssertTrue(described.contains("Sanctuary"))
        XCTAssertTrue(described.contains("21 characters"))
    }

    func testClassifySuccess() throws {
        let line = #"[ok] provision {"deviceId":"a4cf1290ab34","ssid":"Sanctuary","role":"host","producer":"auto"}"#
        guard case let .success(identity) = try PagerProvisioner.classify(line: line) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(identity.deviceID, "a4cf1290ab34")
        XCTAssertEqual(identity.roleID, "host")
        XCTAssertEqual(identity.producer, "auto")
    }

    func testClassifySuccessWithSpacesInTheSSID() throws {
        let line = #"[ok] provision {"deviceId":"ab","ssid":"Church Guest 2.4","role":"keys","producer":"10.0.1.7"}"#
        guard case let .success(identity) = try PagerProvisioner.classify(line: line) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(identity.ssid, "Church Guest 2.4")
        XCTAssertEqual(identity.producer, "10.0.1.7")
    }

    func testClassifyReadsTheConfirmedRotation() throws {
        let line = #"[ok] provision {"deviceId":"ab","ssid":"n","role":"host","producer":"auto","rotate180":true}"#
        guard case let .success(identity) = try PagerProvisioner.classify(line: line) else {
            return XCTFail("expected success")
        }
        XCTAssertTrue(identity.rotate180)
    }

    func testClassifyToleratesFirmwareWithoutRotationSupport() throws {
        let line = #"[ok] provision {"deviceId":"ab","ssid":"n","role":"host","producer":"auto"}"#
        guard case let .success(identity) = try PagerProvisioner.classify(line: line) else {
            return XCTFail("expected success")
        }
        XCTAssertFalse(identity.rotate180)
    }

    func testClassifyFailureCarriesTheReasonToken() throws {
        guard case let .failure(reason) = try PagerProvisioner.classify(line: "[err] provision bad-ssid-length")
        else { return XCTFail("expected failure") }
        XCTAssertEqual(reason, "bad-ssid-length")
    }

    func testClassifyPassesThroughUnknownReasons() throws {
        guard case let .failure(reason) = try PagerProvisioner.classify(line: "[err] provision radio-on-fire")
        else { return XCTFail("expected failure") }
        XCTAssertEqual(reason, "radio-on-fire")
        let described = PagerProvisioningError.rejected(reason: reason).errorDescription ?? ""
        XCTAssertTrue(described.contains("radio-on-fire"))
    }

    func testClassifyIgnoresEverythingElseTheDevicePrints() throws {
        let noise = [
            "=== 13years ESP32 Hardware Pager ===",
            "[boot] deviceId=a4cf1290ab34",
            #"[serial] > provision {"ssid":"Sanctuary","pass":"hunter2"}"#,
            "[wifi] connecting to \"Sanctuary\"",
            "",
        ]
        for line in noise {
            XCTAssertEqual(try PagerProvisioner.classify(line: line), .unrelated, "should ignore: \(line)")
        }
    }

    func testClassifyRejectsAMalformedOkPayload() {
        XCTAssertThrowsError(try PagerProvisioner.classify(line: "[ok] provision not-json")) { error in
            XCTAssertEqual(error as? PagerProvisioningError,
                           .malformedAcknowledgement(line: "[ok] provision not-json"))
        }
    }

    func testClassifyRejectsAnOkPayloadMissingFields() {
        let line = #"[ok] provision {"deviceId":"ab"}"#
        XCTAssertThrowsError(try PagerProvisioner.classify(line: line))
    }

    func testTakeLinesSplitsCRLFEndings() {
        var buffer = Data("first\r\nsecond\r\n".utf8)
        XCTAssertEqual(PagerProvisioner.takeLines(from: &buffer), ["first\r", "second\r"])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testTakeLinesHoldsBackAPartialLine() {
        var buffer = Data("complete\r\npartial".utf8)
        XCTAssertEqual(PagerProvisioner.takeLines(from: &buffer), ["complete\r"])
        XCTAssertEqual(String(decoding: buffer, as: UTF8.self), "partial")
        buffer.append(Data(" now done\r\n".utf8))
        XCTAssertEqual(PagerProvisioner.takeLines(from: &buffer), ["partial now done\r"])
    }

    func testTakeLinesFindsAnAckBuriedInRealDeviceChatter() throws {
        var buffer = Data("""
        [serial] > provision {"pass":"pw","ssid":"lab"}
        [led] -> OFF (Clear)
        [wifi] credentials saved for "13years lab 2.4" — connecting
        [wifi] connecting to "13years lab 2.4" (attempt 1)
        [ok] provision {"deviceId":"13years-70314f","ssid":"13years lab 2.4","role":"keys","producer":"auto"}
        """.replacingOccurrences(of: "\n", with: "\r\n").utf8)
        buffer.append(Data("\r\n".utf8))

        var found: PagerIdentity?
        for line in PagerProvisioner.takeLines(from: &buffer) {
            if case let .success(identity) = try PagerProvisioner.classify(line: line) {
                found = identity
            }
        }
        XCTAssertEqual(found?.deviceID, "13years-70314f")
        XCTAssertEqual(found?.ssid, "13years lab 2.4")
    }

    func testTakeLinesHandlesBareNewlines() {
        var buffer = Data("a\nb\n".utf8)
        XCTAssertEqual(PagerProvisioner.takeLines(from: &buffer), ["a", "b"])
    }

    func testTakeLinesReturnsNothingWithoutATerminator() {
        var buffer = Data("no newline yet".utf8)
        XCTAssertTrue(PagerProvisioner.takeLines(from: &buffer).isEmpty)
        XCTAssertEqual(buffer.count, 14)
    }

    func testClassifyToleratesTrailingCarriageReturn() throws {
        let line = "[err] provision missing-ssid\r"
        guard case let .failure(reason) = try PagerProvisioner.classify(line: line) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(reason, "missing-ssid")
    }
}
