import XCTest
@testable import MarvinCore

final class VoiceCommandTests: XCTestCase {
    func testWakePhraseWithPunctuationAndFollowup() {
        XCTAssertEqual(VoiceCommandMatcher.command(in: "Hey, MARVIN!", active: false), .wake)
        XCTAssertEqual(VoiceCommandMatcher.command(in: "Hey Marvin, are you there?", active: false), .wake)
        XCTAssertNil(VoiceCommandMatcher.command(in: "Marvin is annoying", active: false))
        XCTAssertNil(VoiceCommandMatcher.command(in: "Hey Martin", active: false))
        XCTAssertNil(VoiceCommandMatcher.command(in: "Say hey Marvin", active: false))
        XCTAssertNil(VoiceCommandMatcher.command(in: "Don't say hey Marvin", active: false))
    }
    func testOnlyExplicitSleepCommandEndsConversation() {
        XCTAssertEqual(VoiceCommandMatcher.command(in: "Marvin, go to sleep.", active: true), .sleep)
        XCTAssertEqual(VoiceCommandMatcher.command(in: "Please Marvin go back to sleep please", active: true), .sleep)
        XCTAssertNil(VoiceCommandMatcher.command(in: "I should go to sleep", active: true))
        XCTAssertNil(VoiceCommandMatcher.command(in: "Don't go to sleep Marvin", active: true))
        XCTAssertNil(VoiceCommandMatcher.command(in: "Say Marvin go to sleep", active: true))
        XCTAssertNil(VoiceCommandMatcher.command(in: "Marvin go to sleep tomorrow", active: true))
        XCTAssertNil(VoiceCommandMatcher.command(in: "Hey Marvin", active: true))
        XCTAssertNil(VoiceCommandMatcher.command(in: "Marvin go to sleep", active: false))
    }
    func testSpokenSleepUsesTheSameSingleFarewellGate() {
        var exit = RealtimeLimitExit()
        XCTAssertTrue(exit.begin(.sleep))
        XCTAssertFalse(exit.begin(.time))
        exit.prepare()
        XCTAssertNil(exit.claimClosing(hasActiveResponse: true))
        XCTAssertEqual(exit.claimClosing(hasActiveResponse: false), .sleep)
        XCTAssertNil(exit.claimClosing(hasActiveResponse: false))
    }
}
