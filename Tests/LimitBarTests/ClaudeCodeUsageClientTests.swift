import XCTest
@testable import LimitBar

final class ClaudeCodeUsageClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchUsageSendsBearerOAuthHeadersAndParsesRateLimitHeaders() async throws {
        let client = ClaudeCodeUsageClient(session: makeMockSession())
        let resetTimestamp = Date().addingTimeInterval(3600).timeIntervalSince1970

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-abc")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("claude-code/") ?? false)

            return Self.response(
                statusCode: 200,
                headers: [
                    "anthropic-ratelimit-unified-5h-utilization": "0.42",
                    "anthropic-ratelimit-unified-5h-reset": String(resetTimestamp),
                    "anthropic-ratelimit-unified-7d-utilization": "0.81",
                    "anthropic-ratelimit-unified-7d-reset": String(resetTimestamp + 7 * 86400)
                ]
            )
        }

        let usage = try await client.fetchUsage(accessToken: "token-abc")

        XCTAssertEqual(usage.fiveHour?.usedPercent, 42)
        XCTAssertEqual(usage.weekly?.usedPercent, 81)
        XCTAssertEqual(usage.fiveHour?.windowMinutes, 300)
        XCTAssertEqual(usage.weekly?.windowMinutes, 7 * 24 * 60)
        XCTAssertNotNil(usage.fiveHour?.resetsAt)
        XCTAssertNotNil(usage.weekly?.resetsAt)
    }

    func testFetchUsageReturnsZeroPercentWhenWindowAlreadyReset() async throws {
        let client = ClaudeCodeUsageClient(session: makeMockSession())
        let pastReset = Date().addingTimeInterval(-60).timeIntervalSince1970

        MockURLProtocol.handler = { _ in
            Self.response(
                statusCode: 200,
                headers: [
                    "anthropic-ratelimit-unified-5h-utilization": "0.95",
                    "anthropic-ratelimit-unified-5h-reset": String(pastReset)
                ]
            )
        }

        let usage = try await client.fetchUsage(accessToken: "tok")

        XCTAssertEqual(usage.fiveHour?.usedPercent, 0)
    }

    func testFetchUsageOmitsWindowWhenHeaderMissing() async throws {
        let client = ClaudeCodeUsageClient(session: makeMockSession())

        MockURLProtocol.handler = { _ in
            Self.response(
                statusCode: 200,
                headers: [
                    "anthropic-ratelimit-unified-7d-utilization": "0.5",
                    "anthropic-ratelimit-unified-7d-reset": String(Date().addingTimeInterval(7 * 86400).timeIntervalSince1970)
                ]
            )
        }

        let usage = try await client.fetchUsage(accessToken: "tok")

        XCTAssertNil(usage.fiveHour)
        XCTAssertEqual(usage.weekly?.usedPercent, 50)
    }

    func testFetchUsageMapsUnauthorizedToActionableMessage() async throws {
        let client = ClaudeCodeUsageClient(session: makeMockSession())

        MockURLProtocol.handler = { _ in
            Self.response(statusCode: 401, headers: [:], body: #"{"error":"unauthorized"}"#)
        }

        do {
            _ = try await client.fetchUsage(accessToken: "tok")
            XCTFail("Expected unauthorized error")
        } catch {
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("claude login"), message)
            XCTAssertTrue(message.contains("HTTP 401"), message)
        }
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        statusCode: Int,
        headers: [String: String],
        body: String = ""
    ) -> (HTTPURLResponse, Data) {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        return (
            HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers)!,
            Data(body.utf8)
        )
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
