import Foundation
import XCTest
@testable import MarvinCore

final class OpenAISpeechTests: XCTestCase {
    func testOldSettingsKeepTheirValuesAndDefaultToLocalSpeech() throws {
        let old = Data(#"{"model":"custom-model","voiceIdentifier":"saved-voice","rate":0.51,"pitch":0.95,"volume":0.8,"allowAppleServerRecognition":true,"maximumResponseWords":40,"endOfSpeechDelay":2.1}"#.utf8)
        let config = try JSONDecoder().decode(MarvinConfig.self, from: old)
        XCTAssertEqual(config.model, "custom-model")
        XCTAssertEqual(config.voiceIdentifier, "saved-voice")
        XCTAssertEqual(config.rate, 0.51)
        XCTAssertEqual(config.maximumResponseWords, 40)
        XCTAssertEqual(config.endOfSpeechDelay, 2.1)
        XCTAssertTrue(config.allowAppleServerRecognition)
        XCTAssertEqual(config.voiceProvider, .apple)
        XCTAssertEqual(config.cloudVoice, "cedar")
        XCTAssertEqual(config.conversationTimeout, 12)
        XCTAssertEqual(config.deliveryInstructions, MarvinConfig.defaultDelivery)
    }

    func testSpeechSettingsRoundTripAndValidation() throws {
        var config = MarvinConfig()
        config.voiceProvider = .openAI
        config.cloudVoice = "ash"
        config.deliveryInstructions = "Dry British delivery."
        config.cloudSpeed = 0.95
        XCTAssertEqual(try JSONDecoder().decode(MarvinConfig.self, from: JSONEncoder().encode(config)), config)
        config.cloudVoice = "unknown"
        config.cloudSpeed = 10
        config.deliveryInstructions = " "
        let validated = config.validated()
        XCTAssertEqual(validated.cloudVoice, "cedar")
        XCTAssertEqual(validated.cloudSpeed, 1.25)
        XCTAssertEqual(validated.deliveryInstructions, MarvinConfig.defaultDelivery)
    }

    func testConversationTimeoutMigrationAndBoundsPreserveChosenVoice() throws {
        let saved = Data(#"{"voiceProvider":"openAI","cloudVoice":"fable","deliveryInstructions":"Weary British sarcasm.","maximumResponseWords":40}"#.utf8)
        var config = try JSONDecoder().decode(MarvinConfig.self, from: saved)
        XCTAssertEqual(config.conversationTimeout, 12)
        config.conversationTimeout = 14
        let restored = try JSONDecoder().decode(MarvinConfig.self, from: JSONEncoder().encode(config)).validated()
        XCTAssertEqual(restored.conversationTimeout, 14)
        XCTAssertEqual(restored.cloudVoice, "fable")
        XCTAssertEqual(restored.deliveryInstructions, "Weary British sarcasm.")
        XCTAssertEqual(restored.maximumResponseWords, 40)
        config.conversationTimeout = -2
        XCTAssertEqual(config.validated().conversationTimeout, 10)
        config.conversationTimeout = 99
        XCTAssertEqual(config.validated().conversationTimeout, 15)
        config.conversationTimeout = .nan
        XCTAssertEqual(config.validated().conversationTimeout, 12)
    }

    func testDirectionsAreSeparateFromSpokenInputAndCredentials() throws {
        var config = MarvinConfig()
        config.cloudVoice = "ash"
        config.deliveryInstructions = "Speak with weary British sarcasm."
        let request = try OpenAISpeechClient().makeRequest("Mitch has another idea.", configuration: config, apiKey: "test-key")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/speech")
        XCTAssertEqual(body["input"] as? String, "Mitch has another idea.")
        XCTAssertEqual(body["instructions"] as? String, config.deliveryInstructions)
        XCTAssertEqual(body["voice"] as? String, "ash")
        XCTAssertEqual(body["response_format"] as? String, "pcm")
        XCTAssertNil(body["store"]) // Responses-only field must not leak into the speech API.
        XCTAssertNil(body["history"])
        XCTAssertFalse(String(data: request.httpBody!, encoding: .utf8)!.contains("test-key"))
        XCTAssertThrowsError(try OpenAISpeechClient().makeRequest("Hi", configuration: config, apiKey: " "))
    }

    func testSpeechTransportHandlesAudioAuthenticationAndMalformedResponses() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SpeechMockURLProtocol.self]
        let client = OpenAISpeechClient(session: URLSession(configuration: config))
        let collector = SpeechChunks()
        try await client.stream("Hi", configuration: .init(), apiKey: "good") { await collector.append($0) }
        let audio = await collector.data
        XCTAssertEqual(audio, Data([0x00, 0x80, 0xff, 0x7f]))
        for key in ["denied", "json", "empty", "odd", "timeout"] {
            do {
                try await client.stream("Hi", configuration: .init(), apiKey: key) { _ in }
                XCTFail("Expected failure for \(key)")
            } catch SpeechAPIError.http(let code) { XCTAssertEqual(code, 401) }
            catch SpeechAPIError.invalidResponse { XCTAssertTrue(["json", "odd"].contains(key)) }
            catch SpeechAPIError.emptyAudio { XCTAssertEqual(key, "empty") }
            catch let error as URLError { XCTAssertEqual(error.code, .timedOut) }
        }
    }

    func testFirstChunkArrivesBeforeEOFAndCancellationStopsWaiting() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpeechMockURLProtocol.self]
        let client = OpenAISpeechClient(session: URLSession(configuration: configuration))
        let firstChunk = expectation(description: "Audio delivered while response remains open")
        let task = Task {
            try await client.stream("Hi", configuration: .init(), apiKey: "streaming") { data in
                XCTAssertEqual(data.count, 9_600)
                firstChunk.fulfill()
            }
        }
        await fulfillment(of: [firstChunk], timeout: 3)
        task.cancel()
        do { try await task.value; XCTFail("Cancelled stream succeeded") }
        catch is CancellationError { }
        catch let error as URLError { XCTAssertEqual(error.code, .cancelled) }
    }

    func testPlaybackConsumerFailureEndsAnOpenStream() async throws {
        enum PlaybackFailure: Error { case rejected }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpeechMockURLProtocol.self]
        let client = OpenAISpeechClient(session: URLSession(configuration: configuration))
        do {
            try await client.stream("Hi", configuration: .init(), apiKey: "streaming") { _ in
                throw PlaybackFailure.rejected
            }
            XCTFail("Expected playback failure")
        } catch PlaybackFailure.rejected { }
    }

    func testStreamingPreservesFinalPartialChunkAndSampleBoundaries() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpeechMockURLProtocol.self]
        let client = OpenAISpeechClient(session: URLSession(configuration: configuration))
        let collector = SpeechChunks()
        try await client.stream("Hi", configuration: .init(), apiKey: "chunks") { await collector.append($0) }
        let chunks = await collector.chunks
        XCTAssertEqual(chunks.map(\.count), [9_600, 4])
        XCTAssertEqual(chunks.reduce(Data(), +), Data(repeating: 0x12, count: 9_601) + Data([0x34, 0x56, 0x78]))
    }

}

private final class SpeechMockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let key = request.value(forHTTPHeaderField: "Authorization") ?? ""
        if key == "Bearer timeout" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: key == "Bearer denied" ? 401 : 200,
            httpVersion: nil, headerFields: ["Content-Type": key == "Bearer json" ? "application/json" : "audio/pcm"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if key == "Bearer streaming" {
            client?.urlProtocol(self, didLoad: Data(repeating: 0, count: 9_600))
            return // Deliberately no EOF: the test must receive audio before completion.
        }
        if key == "Bearer chunks" {
            client?.urlProtocol(self, didLoad: Data(repeating: 0x12, count: 9_601))
            client?.urlProtocol(self, didLoad: Data([0x34, 0x56, 0x78]))
        } else {
            let data = key == "Bearer empty" ? Data() :
                key == "Bearer odd" ? Data([0]) : Data([0x00, 0x80, 0xff, 0x7f])
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor SpeechChunks {
    var chunks: [Data] = []
    var data: Data { chunks.reduce(Data(), +) }
    func append(_ data: Data) { chunks.append(data) }
}
