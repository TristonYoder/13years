// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest

final class HTTPMessageTests: XCTestCase {

    func testSimpleGetRequestParsing() {
        let request = "GET /v1/state HTTP/1.1\r\nHost: localhost\r\nUser-Agent: test\r\n\r\n"
        let buffer = Array(request.utf8)

        let result = HTTPMessageParser.parse(buffer)

        guard case .request(let req, let consumed) = result else {
            XCTFail("Expected .request, got \(result)")
            return
        }

        XCTAssertEqual(req.method, "GET")
        XCTAssertEqual(req.path, "/v1/state")
        XCTAssertEqual(req.query, [:])
        XCTAssertEqual(req.headers["host"], "localhost")
        XCTAssertEqual(req.headers["user-agent"], "test")
        XCTAssertEqual(req.body.count, 0)
        XCTAssertEqual(consumed, buffer.count)
    }

    func testHeadersAreLowercased() {
        let request = "GET / HTTP/1.1\r\nContent-Type: application/json\r\n\r\n"
        let buffer = Array(request.utf8)

        guard case .request(let req, _) = HTTPMessageParser.parse(buffer) else {
            XCTFail("Failed to parse")
            return
        }

        XCTAssertEqual(req.headers["content-type"], "application/json")
        XCTAssertNil(req.headers["Content-Type"])
    }

    func testCaseInsensitiveHeaderLookup() {
        let request = "GET / HTTP/1.1\r\nContent-Type: application/json\r\n\r\n"
        let buffer = Array(request.utf8)

        guard case .request(let req, _) = HTTPMessageParser.parse(buffer) else {
            XCTFail("Failed to parse")
            return
        }

        XCTAssertEqual(req.header("content-type"), "application/json")
        XCTAssertEqual(req.header("Content-Type"), "application/json")
        XCTAssertEqual(req.header("CONTENT-TYPE"), "application/json")
    }

    func testSimpleQueryString() {
        let request = "GET /api/users?id=123&name=john HTTP/1.1\r\n\r\n"
        let buffer = Array(request.utf8)

        guard case .request(let req, _) = HTTPMessageParser.parse(buffer) else {
            XCTFail("Failed to parse")
            return
        }

        XCTAssertEqual(req.path, "/api/users")
        XCTAssertEqual(req.query["id"], "123")
        XCTAssertEqual(req.query["name"], "john")
    }

    func testPercentEncodedQueryString() {
        let request = "GET /search?q=hello%20world HTTP/1.1\r\n\r\n"
        let buffer = Array(request.utf8)

        guard case .request(let req, _) = HTTPMessageParser.parse(buffer) else {
            XCTFail("Failed to parse")
            return
        }

        XCTAssertEqual(req.query["q"], "hello world")
    }

    func testPlusAsSpaceInQueryValue() {
        let request = "GET /search?q=hello+world HTTP/1.1\r\n\r\n"
        let buffer = Array(request.utf8)

        guard case .request(let req, _) = HTTPMessageParser.parse(buffer) else {
            XCTFail("Failed to parse")
            return
        }

        XCTAssertEqual(req.query["q"], "hello world")
    }

    func testPercentEncodedPath() {
        let request = "GET /api%2Fv1%2Fstate HTTP/1.1\r\n\r\n"
        let buffer = Array(request.utf8)

        guard case .request(let req, _) = HTTPMessageParser.parse(buffer) else {
            XCTFail("Failed to parse")
            return
        }

        XCTAssertEqual(req.path, "/api/v1/state")
    }

    func testPercentEncodedSpaceInPathDecodes() {
        let request = "GET /v1/waypoints/song%201 HTTP/1.1\r\n\r\n"
        let buffer = Array(request.utf8)

        guard case .request(let req, _) = HTTPMessageParser.parse(buffer) else {
            XCTFail("Failed to parse")
            return
        }

        XCTAssertEqual(req.path, "/v1/waypoints/song 1")
    }

    func testQueryStringWithoutValue() {
        let request = "GET /api?flag HTTP/1.1\r\n\r\n"
        let buffer = Array(request.utf8)

        guard case .request(let req, _) = HTTPMessageParser.parse(buffer) else {
            XCTFail("Failed to parse")
            return
        }

        XCTAssertEqual(req.query.count, 1)
        XCTAssertEqual(req.query["flag"], "")
    }

    func testPostWithJsonBody() {
        let bodyString = #"{"name":"Alice","age":30}"#
        let requestString = "POST /api/users HTTP/1.1\r\nContent-Length: \(bodyString.count)\r\n\r\n" + bodyString
        let buffer = Array(requestString.utf8)

        guard case .request(let req, let consumed) = HTTPMessageParser.parse(buffer) else {
            XCTFail("Failed to parse")
            return
        }

        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.path, "/api/users")
        XCTAssertEqual(req.body, Data(bodyString.utf8))
        XCTAssertEqual(consumed, buffer.count)
    }

    func testPostWithNoBody() {
        let request = "POST /api/trigger HTTP/1.1\r\n\r\n"
        let buffer = Array(request.utf8)

        guard case .request(let req, _) = HTTPMessageParser.parse(buffer) else {
            XCTFail("Failed to parse")
            return
        }

        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.body.count, 0)
    }

    func testIncompleteHeadReturnsIncomplete() {
        let request = "GET /api HTTP/1.1\r\nHost: localhost"
        let buffer = Array(request.utf8)

        let result = HTTPMessageParser.parse(buffer)

        guard case .incomplete = result else {
            XCTFail("Expected .incomplete, got \(result)")
            return
        }
    }

    func testHeadWithoutCrlfCrlfReturnsIncomplete() {
        let request = "GET /api HTTP/1.1\r\nHost: localhost\r\n"
        let buffer = Array(request.utf8)

        let result = HTTPMessageParser.parse(buffer)

        guard case .incomplete = result else {
            XCTFail("Expected .incomplete, got \(result)")
            return
        }
    }

    func testSplitAcrossReads_HeadThenBody() {
        let headString = "POST /api HTTP/1.1\r\nContent-Length: 5\r\n\r\n"
        let bodyString = "hello"
        let fullRequest = headString + bodyString

        let headBuffer = Array(headString.utf8)
        let result1 = HTTPMessageParser.parse(headBuffer)

        guard case .incomplete = result1 else {
            XCTFail("Expected incomplete for head-only, got \(result1)")
            return
        }

        let partialBuffer = Array((headString + "hel").utf8)
        let result2 = HTTPMessageParser.parse(partialBuffer)

        guard case .incomplete = result2 else {
            XCTFail("Expected incomplete for partial body, got \(result2)")
            return
        }

        let fullBuffer = Array(fullRequest.utf8)
        guard case .request(let req, let consumed) = HTTPMessageParser.parse(fullBuffer) else {
            XCTFail("Expected .request for complete message")
            return
        }

        XCTAssertEqual(req.body, Data(bodyString.utf8))
        XCTAssertEqual(consumed, fullBuffer.count)
    }

    func testTwoRequestsInOneBuffer() {
        let request1 = "GET /first HTTP/1.1\r\n\r\n"
        let request2 = "GET /second HTTP/1.1\r\n\r\n"
        let combined = request1 + request2

        let buffer = Array(combined.utf8)
        guard case .request(let req1, let consumed1) = HTTPMessageParser.parse(buffer) else {
            XCTFail("Failed to parse first request")
            return
        }

        XCTAssertEqual(req1.path, "/first")

        let remaining = Array(buffer.dropFirst(consumed1))
        guard case .request(let req2, let consumed2) = HTTPMessageParser.parse(remaining) else {
            XCTFail("Failed to parse second request")
            return
        }

        XCTAssertEqual(req2.path, "/second")
        XCTAssertEqual(consumed2, remaining.count)
    }

    func testMalformedRequestLineMissingMethod() {
        let request = "GET HTTP/1.1\r\n\r\n"
        let buffer = Array(request.utf8)

        let result = HTTPMessageParser.parse(buffer)

        guard case .failure = result else {
            XCTFail("Expected .failure, got \(result)")
            return
        }
    }

    func testMalformedRequestLineMissingHttpVersion() {
        let request = "GET /api\r\n\r\n"
        let buffer = Array(request.utf8)

        let result = HTTPMessageParser.parse(buffer)

        guard case .failure = result else {
            XCTFail("Expected .failure, got \(result)")
            return
        }
    }

    func testMalformedHeaderMissingColon() {
        let request = "GET / HTTP/1.1\r\nContentType application/json\r\n\r\n"
        let buffer = Array(request.utf8)

        let result = HTTPMessageParser.parse(buffer)

        guard case .failure = result else {
            XCTFail("Expected .failure for header without colon, got \(result)")
            return
        }
    }

    func testContentLengthExceedsMaxBodyBytes() {
        let largeLength = HTTPMessageParser.maxBodyBytes + 1
        let request = "POST /api HTTP/1.1\r\nContent-Length: \(largeLength)\r\n\r\n"
        let buffer = Array(request.utf8)

        let result = HTTPMessageParser.parse(buffer)

        guard case .failure(let reason) = result else {
            XCTFail("Expected .failure, got \(result)")
            return
        }

        XCTAssertTrue(reason.contains("exceeds"))
    }

    func testInvalidContentLengthNonNumeric() {
        let request = "POST /api HTTP/1.1\r\nContent-Length: abc\r\n\r\n"
        let buffer = Array(request.utf8)

        let result = HTTPMessageParser.parse(buffer)

        guard case .failure = result else {
            XCTFail("Expected .failure for non-numeric Content-Length, got \(result)")
            return
        }
    }

    func testNegativeContentLength() {
        let request = "POST /api HTTP/1.1\r\nContent-Length: -10\r\n\r\n"
        let buffer = Array(request.utf8)

        let result = HTTPMessageParser.parse(buffer)

        guard case .failure = result else {
            XCTFail("Expected .failure for negative Content-Length, got \(result)")
            return
        }
    }

    func testRequestHeadExceedsMaxBytes() {
        var request = "GET / HTTP/1.1\r\n"
        while request.count < HTTPMessageParser.maxHeadBytes {
            request += "X-Custom-Header: " + String(repeating: "a", count: 100) + "\r\n"
        }

        let buffer = Array(request.utf8)
        let result = HTTPMessageParser.parse(buffer)

        guard case .failure = result else {
            XCTFail("Expected .failure for over-sized head, got \(result)")
            return
        }
    }

    func testChunkedTransferEncodingRejected() {
        let request = "POST /api HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
        let buffer = Array(request.utf8)

        let result = HTTPMessageParser.parse(buffer)

        guard case .failure(let reason) = result else {
            XCTFail("Expected .failure, got \(result)")
            return
        }

        XCTAssertTrue(reason.lowercased().contains("chunked"))
    }

    func testResponseSerializationBasic() {
        let response = HTTPResponse(status: 200)
        let serialized = response.serialize()
        let serializedStr = String(data: serialized, encoding: .utf8) ?? ""

        XCTAssertTrue(serializedStr.contains("HTTP/1.1 200 OK"))
        XCTAssertTrue(serializedStr.contains("Content-Length: 0"))
        XCTAssertTrue(serializedStr.contains("Connection: keep-alive"))
    }

    func testResponseSerializationWithBody() {
        let bodyStr = "Hello, World!"
        let response = HTTPResponse(status: 200, body: Data(bodyStr.utf8))
        let serialized = response.serialize()
        let serializedStr = String(data: serialized, encoding: .utf8) ?? ""

        XCTAssertTrue(serializedStr.contains("HTTP/1.1 200 OK"))
        XCTAssertTrue(serializedStr.contains("Content-Length: \(bodyStr.count)"))
        XCTAssertTrue(serializedStr.contains(bodyStr))
    }

    func testResponseSerializationStatusLine() {
        let testCases: [(Int, String)] = [
            (200, "OK"),
            (201, "Created"),
            (204, "No Content"),
            (400, "Bad Request"),
            (404, "Not Found"),
            (405, "Method Not Allowed"),
            (500, "Internal Server Error"),
        ]

        for (status, phrase) in testCases {
            let response = HTTPResponse(status: status)
            let serialized = response.serialize()
            let serializedStr = String(data: serialized, encoding: .utf8) ?? ""

            XCTAssertTrue(
                serializedStr.contains("HTTP/1.1 \(status) \(phrase)"),
                "Expected '\(status) \(phrase)' in response"
            )
        }
    }

    func testResponseSerializationCustomHeaders() {
        let headers = ["X-Custom": "value", "Cache-Control": "no-cache"]
        let response = HTTPResponse(status: 200, headers: headers)
        let serialized = response.serialize()
        let serializedStr = String(data: serialized, encoding: .utf8) ?? ""

        XCTAssertTrue(serializedStr.contains("X-Custom: value"))
        XCTAssertTrue(serializedStr.contains("Cache-Control: no-cache"))
    }

    func testResponseSerializationExistingContentLength() {
        let response = HTTPResponse(
            status: 200,
            headers: ["content-length": "999"],
            body: Data("short".utf8)
        )
        let serialized = response.serialize()
        let serializedStr = String(data: serialized, encoding: .utf8) ?? ""

        XCTAssertTrue(serializedStr.contains("Content-Length: 999"))
    }

    func testResponseSerializationExistingConnection() {
        let response = HTTPResponse(
            status: 200,
            headers: ["connection": "close"]
        )
        let serialized = response.serialize()
        let serializedStr = String(data: serialized, encoding: .utf8) ?? ""

        XCTAssertTrue(serializedStr.contains("Connection: close"))
        XCTAssertFalse(serializedStr.contains("Connection: keep-alive"))
    }

    func testResponseJsonFactory() {
        let bodyStr = #"{"status":"ok"}"#
        let response = HTTPResponse.json(status: 200, body: Data(bodyStr.utf8))

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.body, Data(bodyStr.utf8))
        XCTAssertEqual(response.headers["content-type"], "application/json")
    }

    func testResponseEmptyFactory() {
        let response = HTTPResponse.empty(status: 204)

        XCTAssertEqual(response.status, 204)
        XCTAssertEqual(response.body.count, 0)
        XCTAssertEqual(response.headers.count, 0)
    }

    func testHttpRequestInit() {
        let request = HTTPRequest(
            method: "POST",
            path: "/api",
            query: ["key": "value"],
            headers: ["host": "localhost"],
            body: Data("body".utf8)
        )

        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/api")
        XCTAssertEqual(request.query["key"], "value")
        XCTAssertEqual(request.headers["host"], "localhost")
        XCTAssertEqual(request.body, Data("body".utf8))
    }

    func testHttpRequestInitDefaults() {
        let request = HTTPRequest(method: "GET", path: "/")

        XCTAssertEqual(request.query, [:])
        XCTAssertEqual(request.headers, [:])
        XCTAssertEqual(request.body.count, 0)
    }
}
