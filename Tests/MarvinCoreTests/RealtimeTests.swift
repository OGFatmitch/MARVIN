import XCTest
@testable import MarvinCore

final class RealtimeTests: XCTestCase {
    func testOpeningDeckExhaustsEachCycleWithoutBoundaryRepeat() {
        var deck = RealtimeOpeningDeck()
        var previous: String?
        for _ in 0..<20 {
            var cycle: [String] = []
            for _ in RealtimeOpeningDeck.lines {
                let line = deck.next()
                XCTAssertNotEqual(line, previous)
                cycle.append(line)
                previous = line
            }
            XCTAssertEqual(Set(cycle), Set(RealtimeOpeningDeck.lines))
        }
    }
    func testMoreThanTwentyRepliesAreAllowedUnderBudget() throws {
        var budget = RealtimeBudget()
        for _ in 0..<100 {
            let id = try XCTUnwrap(budget.reserve())
            budget.settle(id, usage: ["input_tokens": 100, "output_tokens": 10])
        }
        XCTAssertTrue(budget.canRequest)
    }
    func testLimitClosingWaitsForActiveResponseAndRunsOnlyOnce() {
        var exit = RealtimeLimitExit()
        XCTAssertTrue(exit.begin(.time))
        XCTAssertFalse(exit.begin(.spending))
        XCTAssertNil(exit.claimClosing(hasActiveResponse: false)) // response.done may race setup
        exit.prepare()
        XCTAssertNil(exit.claimClosing(hasActiveResponse: true))
        XCTAssertEqual(exit.claimClosing(hasActiveResponse: false), .time)
        XCTAssertNil(exit.claimClosing(hasActiveResponse: false))
        XCTAssertEqual(exit.reason, .time)
    }
    func testLimitFarewellHasNoLongConversationInputAndBoundedOutput() {
        let response = RealtimeClosingReason.spending.response(configuration: .init())
        XCTAssertEqual(response["conversation"] as? String, "none")
        XCTAssertEqual(response["input"] as? [String], [])
        XCTAssertEqual(response["max_output_tokens"] as? Int, 512)
        XCTAssertTrue((response["instructions"] as? String)?.contains("Never invent an actual bill") == true)
    }
    func testModalityAndCachedTokenPricesMatchDocumentedExample() throws {
        let usage: [String: Any] = ["input_tokens": 132, "output_tokens": 121,
            "input_token_details": ["text_tokens": 119, "audio_tokens": 13, "cached_tokens": 64,
                "cached_tokens_details": ["text_tokens": 64, "audio_tokens": 0]],
            "output_token_details": ["text_tokens": 30, "audio_tokens": 91]]
        XCTAssertEqual(try XCTUnwrap(RealtimeUsageCost.dollars(usage)), 0.0072056, accuracy: 0.00000001)
        XCTAssertEqual(try XCTUnwrap(RealtimeUsageCost.dollars([
            "input_tokens": 1000, "output_tokens": 0,
            "input_token_details": ["audio_tokens": 1000, "cached_tokens": 1000,
                "cached_tokens_details": ["audio_tokens": 1000]]])), 0.0004, accuracy: 0.00000001)
        XCTAssertNil(RealtimeUsageCost.dollars(["input_tokens": -1, "output_tokens": 0]))
    }
    func testReconciliationAndLegacyMigrationPreserveKnownUsage() throws {
        var budget = try JSONDecoder().decode(RealtimeBudget.self,
            from: Data(#"{"charged":3.59,"pending":{"old":2}}"#.utf8))
        XCTAssertEqual(budget.charged, 3.59)
        XCTAssertEqual(budget.pending["old"], 0.5)
        XCTAssertFalse(budget.reconcile(verifiedTotal: .nan))
        XCTAssertFalse(budget.reconcile(verifiedTotal: -1))
        XCTAssertTrue(budget.reconcile(verifiedTotal: 0.47))
        XCTAssertEqual(budget.total, 0.47)
        XCTAssertTrue(budget.pending.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(RealtimeBudget.self, from: JSONEncoder().encode(budget)).total, 0.47)
    }
    func testStartupAudioRecoveryIsBoundedAndDoesNotResurrectPlayback() {
        var startup = RealtimeStartupRecovery()
        XCTAssertTrue(startup.claimRecovery())
        XCTAssertFalse(startup.claimRecovery())
        var speaking = RealtimeStartupRecovery()
        speaking.didScheduleAudio()
        XCTAssertFalse(speaking.claimRecovery())
        var ended = RealtimeStartupRecovery()
        ended.end()
        XCTAssertFalse(ended.claimRecovery())
    }
    func testLockedAudioCannotRestartButReturningBeforeFirstAudioCanRecover() {
        var state = RealtimeStartupRecovery()
        state.isBackgrounded = true
        XCTAssertFalse(state.claimRecovery())
        state.isBackgrounded = false
        XCTAssertTrue(state.claimRecovery())
        XCTAssertFalse(state.claimRecovery())
    }
    func testOldSettingsPreserveFableAndEnableRealtimeTrial() throws {
        let config = try JSONDecoder().decode(MarvinConfig.self, from: Data(#"{"voiceProvider":"openAI","cloudVoice":"fable","maximumResponseWords":45}"#.utf8))
        XCTAssertEqual(config.cloudVoice, "fable")
        XCTAssertEqual(config.maximumResponseWords, 45)
        XCTAssertEqual(config.conversationEngine, .realtime)
        XCTAssertEqual(config.realtimeVoice, "ash")
        let roundTrip = try JSONDecoder().decode(MarvinConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(roundTrip, config)
    }
    func testSessionUsesExactWireDecimals() throws {
        let wire = try RealtimeProtocol.encode(RealtimeProtocol.session(configuration: .init()))
        // Parsing the JSON back to Double hides the bug; check the transmitted text.
        XCTAssertNotNil(wire.range(of: #""retention_ratio"\s*:\s*0\.8(?=[,}])"#, options: .regularExpression))
        XCTAssertFalse(wire.contains("0.80000000000000004"))
        XCTAssertNotNil(wire.range(of: #""speed"\s*:\s*1\.2(?=[,}])"#, options: .regularExpression))
    }
    func testSessionKeepsVADButRequiresBudgetedManualResponses() throws {
        let encoded = try RealtimeProtocol.encode(RealtimeProtocol.session(configuration: .init()))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
        let session = try XCTUnwrap(object["session"] as? [String: Any])
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let output = try XCTUnwrap(audio["output"] as? [String: Any])
        XCTAssertEqual(output["speed"] as? Double, 1.2)
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let vad = try XCTUnwrap(input["turn_detection"] as? [String: Any])
        XCTAssertEqual(vad["create_response"] as? Bool, false)
        XCTAssertEqual(vad["interrupt_response"] as? Bool, true)
        XCTAssertNil(input["transcription"])
        XCTAssertEqual(session["max_output_tokens"] as? Int, 2048)
        XCTAssertTrue((session["instructions"] as? String)?.contains("British") == true)
    }
    func testInterruptedAudioCannotRestartAfterLatePackets() {
        var state = RealtimeTurnState()
        state.begin("first"); state.item("item1")
        XCTAssertTrue(state.accepts("first"))
        state.interrupt()
        XCTAssertFalse(state.accepts("first"))
        state.begin("second")
        XCTAssertFalse(state.accepts("first"))
        XCTAssertTrue(state.accepts("second"))
        XCTAssertNil(state.itemID)
    }
    func testFinishedPlaybackDoesNotTruncateAlreadyHeardHistory() {
        var state = RealtimeTurnState()
        state.begin("first"); state.item("item1")
        state.clearItem()
        state.interrupt()
        XCTAssertNil(state.itemID)
        XCTAssertFalse(state.accepts("first"))
    }
    func testWaitingForNewResponseRejectsOldAudioAndDoneID() {
        var state = RealtimeTurnState()
        state.begin("first"); state.item("item1")
        state.awaitingResponse()
        XCTAssertNil(state.responseID)
        XCTAssertFalse(state.accepts("first"))
        state.begin("second")
        XCTAssertTrue(state.accepts("second"))
    }
    func testBudgetReservesBeforeRequestAndRejectsAtLimit() {
        var budget = RealtimeBudget()
        for _ in 0..<79 { XCTAssertNotNil(budget.reserve()) }
        XCTAssertNil(budget.reserve())
        XCTAssertEqual(budget.total, 39.5)
        XCTAssertNotNil(budget.reserve(closing: true))
    }
    func testCancelledUnknownUsageIsReservedAndKnownUsageIsCountedOnce() throws {
        var budget = RealtimeBudget()
        let unknown = try XCTUnwrap(budget.reserve())
        budget.settle(unknown, usage: nil)
        XCTAssertEqual(budget.total, 0.5)
        let known = try XCTUnwrap(budget.reserve())
        budget.settle(known, usage: ["input_tokens": 1000, "output_tokens": 200])
        XCTAssertEqual(budget.total, 0.5448, accuracy: 0.000001)
        budget.settle(known, usage: ["input_tokens": 1000, "output_tokens": 200])
        XCTAssertEqual(budget.total, 0.5448, accuracy: 0.000001)
    }
    func testBudgetSurvivesRestartAndCorruptionFailsClosed() throws {
        let name = "marvin.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var budget = RealtimeBudget()
        _ = budget.reserve(); budget.save(defaults: defaults)
        XCTAssertEqual(RealtimeBudget.load(defaults: defaults).total, 0.5)
        defaults.set(Data("broken".utf8), forKey: RealtimeBudget.key)
        XCTAssertFalse(RealtimeBudget.load(defaults: defaults).canRequest)
    }
}
