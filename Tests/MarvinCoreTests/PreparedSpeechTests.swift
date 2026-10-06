import Foundation
import XCTest
@testable import MarvinCore

final class PreparedSpeechTests: XCTestCase {
    func testPreparedLinesPersistAndAreReusedWithoutRequests() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PreparedSpeechCache(directory: directory)
        let client = PreparedClient()
        var config = MarvinConfig()
        config.cloudVoice = "fable"
        try await cache.prepare(configuration: config, apiKey: "mock", client: client) { _ in }
        let reopened = PreparedSpeechCache(directory: directory)
        let ready = await reopened.count(configuration: config)
        XCTAssertEqual(ready, 8)
        try await reopened.prepare(configuration: config, apiKey: "mock", client: client) { _ in }
        let calls = await client.calls
        XCTAssertEqual(calls, 8)
        let audio = await reopened.audio(for: ConversationInteraction.openings[0], configuration: config)
        XCTAssertEqual(audio, Data([0, 0, 1, 0]))
        let conversation = await reopened.audio(for: "A private conversation reply", configuration: config)
        XCTAssertNil(conversation)
        try await reopened.clear()
        let remaining = await reopened.count(configuration: config)
        XCTAssertEqual(remaining, 0)
    }

    func testIdentityIncludesDeliveryVoiceAndSpeedButNotPlaybackVolume() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PreparedSpeechCache(directory: directory)
        let config = MarvinConfig()
        try await cache.prepare(configuration: config, apiKey: "mock", client: PreparedClient()) { _ in }
        var changed = config
        changed.volume = 0.1
        let volumeOnly = await cache.count(configuration: changed)
        XCTAssertEqual(volumeOnly, 8)
        for mutation in 0..<3 {
            changed = config
            if mutation == 0 { changed.cloudVoice = "fable" }
            if mutation == 1 { changed.deliveryInstructions = "A different performance." }
            if mutation == 2 { changed.cloudSpeed = 0.8 }
            let count = await cache.count(configuration: changed)
            XCTAssertEqual(count, 0)
        }
        try await cache.prepare(configuration: changed, apiKey: "mock", client: PreparedClient()) { _ in }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 8)
    }

    func testFailedOrCancelledPreparationDoesNotSavePartialAudioAndCanResume() async throws {
        for cancelled in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let cache = PreparedSpeechCache(directory: directory)
            do {
                try await cache.prepare(configuration: .init(), apiKey: "mock",
                    client: PreparedClient(failOnCall: 2, cancelled: cancelled)) { _ in }
                XCTFail("Expected interruption")
            } catch is CancellationError { XCTAssertTrue(cancelled) }
            catch SpeechAPIError.invalidResponse { XCTAssertFalse(cancelled) }
            let partialCount = await cache.count(configuration: .init())
            XCTAssertEqual(partialCount, 1)
            let retry = PreparedClient()
            try await cache.prepare(configuration: .init(), apiKey: "mock", client: retry) { _ in }
            let calls = await retry.calls
            XCTAssertEqual(calls, 7)
        }
    }

    func testLegacyClipsMigrateWithoutGenerationAndStayAfterCacheRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("Caches")
        let durable = root.appendingPathComponent("ApplicationSupport")
        let original = PreparedSpeechCache(directory: legacy)
        let client = PreparedClient()
        try await original.prepare(configuration: .init(), apiKey: "mock", client: client) { _ in }
        let updated = PreparedSpeechCache(directory: durable, legacyDirectory: legacy)
        let ready = await updated.count(configuration: .init())
        XCTAssertEqual(ready, 8)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        let reopened = PreparedSpeechCache(directory: durable, legacyDirectory: legacy)
        try await reopened.prepare(configuration: .init(), apiKey: "mock", client: client) { _ in }
        let calls = await client.calls
        XCTAssertEqual(calls, 8)
        let count = await reopened.count(configuration: .init())
        XCTAssertEqual(count, 8)
        try await reopened.clear()
        let empty = await PreparedSpeechCache(directory: durable, legacyDirectory: legacy).count(configuration: .init())
        XCTAssertEqual(empty, 0)
    }

    func testDeletingBeforeMigrationDoesNotRestoreLegacyClips() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("Caches")
        let durable = root.appendingPathComponent("ApplicationSupport")
        try await PreparedSpeechCache(directory: legacy).prepare(configuration: .init(), apiKey: "mock", client: PreparedClient()) { _ in }
        try await PreparedSpeechCache(directory: durable, legacyDirectory: legacy).clear()
        let count = await PreparedSpeechCache(directory: durable, legacyDirectory: legacy).count(configuration: .init())
        XCTAssertEqual(count, 0)
    }

    func testMalformedCachedClipIsNotPlayed() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PreparedSpeechCache(directory: directory)
        try await cache.prepare(configuration: .init(), apiKey: "mock", client: PreparedClient()) { _ in }
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try Data([1]).write(to: file)
        }
        let count = await cache.count(configuration: .init())
        XCTAssertEqual(count, 0)
    }
}

private actor PreparedClient: SpeechAudioClient {
    private(set) var calls = 0
    let failOnCall: Int?
    let cancelled: Bool
    init(failOnCall: Int? = nil, cancelled: Bool = false) {
        self.failOnCall = failOnCall
        self.cancelled = cancelled
    }
    func stream(_ text: String, configuration: MarvinConfig, apiKey: String,
                onChunk: @escaping @Sendable (Data) async throws -> Void) async throws {
        calls += 1
        try await onChunk(Data([0, 0, 1, 0]))
        if calls == failOnCall {
            if cancelled { throw CancellationError() }
            throw SpeechAPIError.invalidResponse
        }
    }
}
