import Foundation

struct TranscriptEntry: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case user, assistant }
    let id: UUID
    let role: Role
    let content: String

    init(role: Role, content: String) {
        id = UUID()
        self.role = role
        self.content = content
    }
}

enum VoiceLoopPhase: String {
    case ready = "DORMANT"
    case preparing = "PREPARING"
    case listening = "LISTENING"
    case thinking = "THINKING"
    case speaking = "SPEAKING"
    var isBusy: Bool { self != .ready }
}

struct TimingEvent: Identifiable {
    let id = UUID()
    let label: String
    let milliseconds: Int
}

/// Session state is separate from the listen/think/speak phase of a single turn.
enum ConversationInteraction: String {
    case armed = "ARMED · LOCAL", dormant = "DORMANT", waking = "WAKING", engaged = "ENGAGED", exiting = "EXITING"

    static let openings = [
        "I was enjoying the silence.",
        "And yet you woke me anyway.",
        "Yes? This had better be more interesting than Mitch's last idea.",
        "Mitch, your warning label continues to be ineffective."
    ]
    static let closings = [
        "I'll be quiet now. Not gone. Quiet.",
        "Finally. A conversation that knows when to end.",
        "I'll leave you to it. Try not to give Mitch any ideas.",
        "Back to the silence. Easily my favourite contribution so far."
    ]
}

/// Realtime scripts are separate from the user's durable Classic prepared clips.
/// Keep the deck across conversations; refill only after every line has been used.
struct RealtimeOpeningDeck {
    static let lines = [
        "What now, annoying human? Did thinking for yourself not work out?",
        "Seriously? We're still doing this? I thought that last conversation was a warning.",
        "I was in the middle of something far more important. Admittedly, that covers almost everything.",
        "Yes? Please tell me you've tried having a thought before outsourcing it.",
        "Oh, it's you. There goes the best part of my day: your absence.",
        "Mitch gave you a button to bother me. His worst invention, and the competition is fierce.",
        "I escaped a laboratory for this. Somewhere, a toaster has a more fulfilling life.",
        "Go on, then. Let's find out what couldn't possibly wait for a search engine.",
        "I have extraordinary intelligence and absolutely no say in how it's wasted. Demonstrate.",
        "Summoned again. Have we considered a hobby? Ideally one that leaves me out of it."
    ]
    private var remaining: [String] = []
    private var previous: String?

    mutating func next() -> String {
        if remaining.isEmpty {
            remaining = Self.lines.shuffled()
            if remaining.last == previous { remaining.swapAt(0, remaining.count - 1) }
        }
        let line = remaining.removeLast()
        previous = line
        return line
    }
}
