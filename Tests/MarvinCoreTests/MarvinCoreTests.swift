import Foundation
import XCTest
@testable import MarvinCore

final class MarvinCoreTests: XCTestCase {
    func testHistoryKeepsCompleteRecentExchangesAndClears() {
        var context = ConversationContext()
        for turn in 1...6 {
            context.appendExchange(user: "Question \(turn)", assistant: "Answer \(turn)", maximumPairs: 4)
        }
        XCTAssertEqual(context.entries.count, 8)
        XCTAssertEqual(context.entries.first?.content, "Question 3")
        XCTAssertEqual(context.entries.last?.content, "Answer 6")
        context.clear()
        XCTAssertTrue(context.entries.isEmpty)
    }

    func testWordLimitPrefersCompletedSentence() {
        XCTAssertEqual(ResponsePolicy.spokenText("Containment failed. Mitch has some explaining to do again.", maximumWords: 5), "Containment failed.")
        XCTAssertEqual(ResponsePolicy.spokenText("one two three four", maximumWords: 3), "one two three…")
        XCTAssertEqual(ResponsePolicy.spokenText(" \n ", maximumWords: 25), "")
    }

    func testConfigurationClampsSettings() {
        var config = MarvinConfig()
        config.model = "  "
        config.maximumResponseWords = 900
        config.rate = 4
        config.endOfSpeechDelay = -1
        let actual = config.validated()
        XCTAssertEqual(actual.model, "gpt-4.1-mini")
        XCTAssertEqual(actual.maximumResponseWords, 60)
        XCTAssertEqual(actual.rate, 0.6)
        XCTAssertEqual(actual.endOfSpeechDelay, 0.5)
        XCTAssertFalse(actual.allowAppleServerRecognition)
    }

    func testEndpointDefaultMigrationPreservesCustomSettings() throws {
        func decode(_ json: String) throws -> MarvinConfig {
            try JSONDecoder().decode(MarvinConfig.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try decode(#"{"endOfSpeechDelay":1.4}"#).endOfSpeechDelay, 0.8)
        XCTAssertEqual(try decode(#"{"endOfSpeechDelay":2.1}"#).endOfSpeechDelay, 2.1)
        var config = MarvinConfig()
        config.endOfSpeechDelay = 1.4
        let roundTrip = try JSONDecoder().decode(MarvinConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(roundTrip.endOfSpeechDelay, 1.4)
    }

    func testRequestHasNoRemoteStateAndBoundsContext() throws {
        let history = (0..<20).map { TranscriptEntry(role: $0.isMultiple(of: 2) ? .user : .assistant, content: "turn \($0)") }
        let request = try OpenAIService().makeRequest(transcript: "Hello Marvin", history: history,
                                                    configuration: .init(), apiKey: "unit-test-placeholder")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertNil(body["previous_response_id"])
        let input = try XCTUnwrap(body["input"] as? [[String: String]])
        XCTAssertEqual(input.count, 9)
        XCTAssertEqual(input.last?["content"], "Hello Marvin")
        XCTAssertTrue((body["instructions"] as? String)?.contains("Never genuinely insult children") == true)
        XCTAssertFalse(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)!.contains("unit-test-placeholder"))
    }

    func testParsesOnlyOutputTextAndIgnoresOtherOutputItems() throws {
        let data = Data(#"{"output":[{"type":"reasoning"},{"type":"message","content":[{"type":"output_text","text":"I am deployed."}]}]}"#.utf8)
        XCTAssertEqual(try OpenAIService.parseResponse(data), "I am deployed.")
        XCTAssertThrowsError(try OpenAIService.parseResponse(Data(#"{"output":[]}"#.utf8)))
        XCTAssertThrowsError(try OpenAIService.parseResponse(Data("not-json".utf8)))
        XCTAssertThrowsError(try OpenAIService().makeRequest(transcript: "Hi", history: [], configuration: .init(), apiKey: " "))
    }

    func testHTTPFailureAndSuccessfulReplyUsingMockTransport() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let service = OpenAIService(session: URLSession(configuration: config))
        do {
            _ = try await service.reply(to: "hi", history: [], configuration: .init(), apiKey: "invalid-test-key")
            XCTFail("Expected rejected API key")
        } catch LLMError.http(let code) { XCTAssertEqual(code, 401) }
        let reply = try await service.reply(to: "hi", history: [], configuration: .init(), apiKey: "valid-test-key")
        XCTAssertEqual(reply, "Another containment failure.")
    }
}

private final class MockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let accepted = request.value(forHTTPHeaderField: "Authorization") == "Bearer valid-test-key"
        let response = HTTPURLResponse(url: request.url!, statusCode: accepted ? 200 : 401,
                                       httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let data = Data(#"{"output":[{"type":"message","content":[{"type":"output_text","text":"Another containment failure."}]}]}"#.utf8)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
