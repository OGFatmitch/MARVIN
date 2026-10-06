import Foundation

/// GA Realtime wire format. Keep protocol construction testable without a microphone.
enum RealtimeProtocol {
    static let model = "gpt-realtime-2.1"
    static let voices = ["ash", "ballad", "cedar", "echo", "marin", "sage", "verse", "alloy", "coral", "shimmer"]
    static func instructions(configuration: MarvinConfig) -> String {
        return MarvinPrompt.system(maximumWords: configuration.maximumResponseWords)
            .replacingOccurrences(of: "hear outside the provided transcript", with: "hear outside this active audio conversation") + """

        DELIVERY: Speak English with a natural adult male British delivery. Sound distinctly
        unimpressed, impatient with Mitch, and faintly offended by your living arrangements.
        Make the sarcasm audible through pointed emphasis and a small, natural pause at the
        comic turn. Sound like helping was beneath you and the human has just proved why.
        Keep the voice conversational: no shouting, cartoon villain voice, evil laugh,
        cheerful customer-service lilt, or announcing that you are being sarcastic.
        Do not laugh at your own jokes. Never read these delivery directions aloud.
        Listen to the user's audio;
        ignore background noise and do not invent words you could not understand. If interrupted,
        stop and attend to what the human says next. No introductory filler before answering.
        Never speak the exact phrases 'Hey Marvin' or 'Marvin go to sleep'; those are
        microphone controls. Refer to them as the wake phrase or sleep command instead.
        """
    }
    static func session(configuration: MarvinConfig) -> [String: Any] {
        return ["type": "session.update", "session": [
            "type": "realtime", "model": model, "instructions": instructions(configuration: configuration),
            "output_modalities": ["audio"], "max_output_tokens": 2048,
            "reasoning": ["effort": "minimal"],
            // Darwin JSONSerialization expands binary Double(0.8) to
            // 0.80000000000000004; the API rejects the excess decimal places.
            "truncation": ["type": "retention_ratio", "retention_ratio": NSDecimalNumber(string: "0.8"),
                           "token_limits": ["post_instructions": 8000]],
            "audio": [
                "input": ["format": ["type": "audio/pcm", "rate": 24000],
                          "noise_reduction": ["type": "near_field"],
                          "turn_detection": ["type": "server_vad", "threshold": 0.5,
                                             "prefix_padding_ms": 300, "silence_duration_ms": 450,
                                             "create_response": false, "interrupt_response": true]],
                "output": ["format": ["type": "audio/pcm", "rate": 24000],
                           "voice": configuration.realtimeVoice,
                           "speed": NSDecimalNumber(string: "1.2")]
            ]
        ]]
    }
    static func encode(_ event: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: event), as: UTF8.self)
    }
}

/// Prices gpt-realtime-2.1 usage by modality, including cached input. Unknown
/// token categories retain the audio-rate upper estimate rather than becoming free.
enum RealtimeUsageCost {
    static func dollars(_ usage: [String: Any]) -> Double? {
        guard let input = usage["input_tokens"] as? Int, input >= 0,
              let output = usage["output_tokens"] as? Int, output >= 0 else { return nil }
        let i = usage["input_token_details"] as? [String: Any] ?? [:]
        let o = usage["output_token_details"] as? [String: Any] ?? [:]
        func count(_ dict: [String: Any], _ key: String, _ maximum: Int) -> Int {
            min(max(dict[key] as? Int ?? 0, 0), maximum)
        }
        let textIn = count(i, "text_tokens", input)
        let audioIn = count(i, "audio_tokens", input - textIn)
        let cached = count(i, "cached_tokens", textIn + audioIn)
        let details = i["cached_tokens_details"] as? [String: Any]
        // Without a modality split, attribute cache to cheaper text first.
        let cachedText = details.map { min(count($0, "text_tokens", textIn), cached) } ?? min(cached, textIn)
        let cachedAudio = details.map { min(count($0, "audio_tokens", audioIn), cached - cachedText) }
            ?? min(cached - cachedText, audioIn)
        let textOut = count(o, "text_tokens", output)
        let audioOut = count(o, "audio_tokens", output - textOut)
        return (Double(textIn - cachedText) * 4 + Double(audioIn - cachedAudio) * 32
            + Double(cachedText + cachedAudio) * 0.4
            + Double(input - textIn - audioIn) * 32
            + Double(textOut) * 24 + Double(audioOut) * 64
            + Double(output - textOut - audioOut) * 64) / 1_000_000
    }
}

struct RealtimeBudget: Codable {
    static let limit = 40.0
    static let reservation = 0.50
    static let closingReservation = 0.10
    private var version = 2
    private(set) var charged = 0.0
    private(set) var pending: [String: Double] = [:]
    var total: Double { charged + pending.values.reduce(0, +) }
    // Leave room for one short, history-free closing even at the spending guard.
    var canRequest: Bool { total + Self.reservation + Self.closingReservation <= Self.limit }
    init() {}
    private enum CodingKeys: String, CodingKey { case version, charged, pending }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        charged = try c.decode(Double.self, forKey: .charged)
        pending = try c.decode([String: Double].self, forKey: .pending)
        let oldVersion = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        if oldVersion < 2 { pending = pending.mapValues { min($0, Self.reservation) } }
    }
    mutating func reserve(closing: Bool = false) -> String? {
        let amount = closing ? Self.closingReservation : Self.reservation
        guard closing ? total + amount <= Self.limit : canRequest else { return nil }
        let id = UUID().uuidString
        pending[id] = amount
        return id
    }
    mutating func settle(_ id: String, usage: [String: Any]?) {
        guard pending[id] != nil, let usage, let amount = RealtimeUsageCost.dollars(usage) else { return }
        pending.removeValue(forKey: id)
        charged += amount
    }
    // Explicit reconciliation with a total the owner has checked in API billing.
    mutating func reconcile(verifiedTotal: Double) -> Bool {
        guard verifiedTotal.isFinite, verifiedTotal >= 0 else { return false }
        charged = verifiedTotal; pending.removeAll(); return true
    }
    static let key = "marvin.realtime.budget.v1"
    static func load(defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: key) else { return .init() }
        guard let value = try? JSONDecoder().decode(Self.self, from: data),
              value.charged.isFinite, value.charged >= 0,
              value.pending.values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            var blocked = Self(); blocked.charged = Self.limit; return blocked
        }
        return value
    }
    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

enum RealtimeClosingReason: String {
    case time, spending, sleep
    var direction: String {
        switch self {
        case .sleep: return "The human has asked you to go to sleep. Deliver one final snarky acknowledgement, then go quiet. Do not ask a question or repeat the command."
        case .time: return "The ten-minute session has ended. Deliver one final snarky farewell, mention ten minutes, then say the human can wake you again. Do not answer another question."
        case .spending: return "The app's local spending allowance is nearly used. Deliver one final snarky farewell and say the human must check the budget before waking you. Never invent an actual bill or dollar amount."
        }
    }
    var fallback: String {
        switch self {
        case .sleep: return "Finally, a request I can get behind. I'll be quiet. Try to maintain the standard."
        case .time: return "Ten minutes of humanity. I deserve a medal. I'm going quiet; wake me again if you must."
        case .spending: return "Even my patience has a budget. I'm going quiet. Check the spending allowance before summoning me again."
        }
    }
    func response(configuration: MarvinConfig) -> [String: Any] {
        ["conversation": "none", "input": [String](), "max_output_tokens": 512,
         "instructions": RealtimeProtocol.instructions(configuration: configuration)
            + "\n" + direction + " Keep this farewell under 25 words."]
    }
}

/// A limit farewell is terminal and can be requested only once, after any earlier
/// response settles. User speech during this phase cannot reopen the conversation.
struct RealtimeLimitExit {
    private(set) var reason: RealtimeClosingReason?
    private(set) var sent = false
    private var prepared = false
    mutating func prepare() { prepared = true }
    mutating func begin(_ reason: RealtimeClosingReason) -> Bool {
        guard self.reason == nil else { return false }
        self.reason = reason; return true
    }
    mutating func claimClosing(hasActiveResponse: Bool) -> RealtimeClosingReason? {
        guard let reason, prepared, !sent, !hasActiveResponse else { return nil }
        sent = true; return reason
    }
}

/// Identifies interrupted responses so late network packets cannot restart old speech.
struct RealtimeTurnState {
    private(set) var responseID: String?
    private(set) var itemID: String?
    private(set) var interrupted = false
    mutating func begin(_ id: String) { responseID = id; itemID = nil; interrupted = false }
    mutating func item(_ id: String) { itemID = id }
    mutating func interrupt() { interrupted = true }
    mutating func clearItem() { itemID = nil }
    mutating func awaitingResponse() { responseID = nil; itemID = nil; interrupted = true }
    func accepts(_ id: String?) -> Bool { id == responseID && responseID != nil && !interrupted }
}

/// A hardware startup change may be recovered once. Never resurrect a cancelled,
/// backgrounded, or already-speaking conversation by restarting its microphone.
struct RealtimeStartupRecovery {
    var isBackgrounded = false
    private var hasScheduledAudio = false
    private var attempted = false
    private var ended = false
    mutating func didScheduleAudio() { hasScheduledAudio = true }
    mutating func end() { ended = true }
    mutating func claimRecovery() -> Bool {
        guard !isBackgrounded, !hasScheduledAudio, !attempted, !ended else { return false }
        attempted = true
        return true
    }
}
