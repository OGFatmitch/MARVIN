import Foundation

struct MarvinConfig: Codable, Equatable {
    enum ConversationEngine: String, Codable, CaseIterable {
        case realtime, classic
        var title: String { self == .realtime ? "Realtime · interruptible" : "Classic · separate speech" }
    }
    var conversationEngine: ConversationEngine = .realtime
    var realtimeVoice = "ash"
    enum VoiceProvider: String, Codable, CaseIterable {
        case apple, openAI
        var title: String { self == .apple ? "Apple · on device" : "OpenAI · cloud" }
    }
    static let cloudVoices = ["cedar", "marin", "ash", "ballad", "coral", "echo", "fable", "onyx", "sage", "shimmer", "verse", "alloy", "nova"]
    static let defaultDelivery = """
    Speak with an adult British accent and a calm, articulate voice. Every statement carries
    dry sarcasm, weary cynicism, and quiet amusement. Sound mildly exasperated by Mitch and
    entirely confident in yourself. Use natural conversational pacing and a subtle pause
    before a punchline. Underplay the performance. Never sound cheerful, salesy, cruel,
    angry, theatrical, or like a customer-service agent. Keep the delivery playful and
    appropriate around children. Speak only the supplied input text; do not read these directions.
    """
    var voiceProvider: VoiceProvider = .apple
    var cloudVoice = "cedar"
    var cloudSpeed: Double = 1.0
    var deliveryInstructions = Self.defaultDelivery
    var model = "gpt-4.1-mini"
    var voiceIdentifier = ""
    var rate: Float = 0.47
    var pitch: Float = 0.90
    var volume: Float = 0.90
    var allowAppleServerRecognition = false
    var maximumResponseWords = 25
    var endOfSpeechDelay: Double = 0.8
    var conversationTimeout: Double = 12
    private let endpointVersion = 2
    let maximumRecordingDuration: Double = 20
    let requestTimeout: Double = 15
    let maximumHistoryPairs = 4
    let maximumTranscriptCharacters = 1500
    private enum CodingKeys: String, CodingKey {
        case conversationEngine, realtimeVoice
        case model, voiceIdentifier, rate, pitch, volume, allowAppleServerRecognition
        case maximumResponseWords, endOfSpeechDelay, conversationTimeout, endpointVersion
        case voiceProvider, cloudVoice, cloudSpeed, deliveryInstructions
    }
    init() {}

    // Additive decoding preserves settings saved before cloud speech was introduced.
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        conversationEngine = try values.decodeIfPresent(ConversationEngine.self, forKey: .conversationEngine) ?? conversationEngine
        realtimeVoice = try values.decodeIfPresent(String.self, forKey: .realtimeVoice) ?? realtimeVoice
        model = try values.decodeIfPresent(String.self, forKey: .model) ?? model
        voiceIdentifier = try values.decodeIfPresent(String.self, forKey: .voiceIdentifier) ?? voiceIdentifier
        rate = try values.decodeIfPresent(Float.self, forKey: .rate) ?? rate
        pitch = try values.decodeIfPresent(Float.self, forKey: .pitch) ?? pitch
        volume = try values.decodeIfPresent(Float.self, forKey: .volume) ?? volume
        allowAppleServerRecognition = try values.decodeIfPresent(Bool.self, forKey: .allowAppleServerRecognition) ?? allowAppleServerRecognition
        maximumResponseWords = try values.decodeIfPresent(Int.self, forKey: .maximumResponseWords) ?? maximumResponseWords
        endOfSpeechDelay = try values.decodeIfPresent(Double.self, forKey: .endOfSpeechDelay) ?? endOfSpeechDelay
        if !values.contains(.endpointVersion), abs(endOfSpeechDelay - 1.4) < 0.001 {
            endOfSpeechDelay = 0.8 // Migrate the old default; preserve custom pauses.
        }
        conversationTimeout = try values.decodeIfPresent(Double.self, forKey: .conversationTimeout) ?? conversationTimeout
        voiceProvider = try values.decodeIfPresent(VoiceProvider.self, forKey: .voiceProvider) ?? voiceProvider
        cloudVoice = try values.decodeIfPresent(String.self, forKey: .cloudVoice) ?? cloudVoice
        cloudSpeed = try values.decodeIfPresent(Double.self, forKey: .cloudSpeed) ?? cloudSpeed
        deliveryInstructions = try values.decodeIfPresent(String.self, forKey: .deliveryInstructions) ?? deliveryInstructions
    }

    static let storageKey = "marvin.configuration.v1"

    func validated() -> MarvinConfig {
        var value = self
        if !RealtimeProtocol.voices.contains(realtimeVoice) { value.realtimeVoice = "ash" }
        if !Self.cloudVoices.contains(cloudVoice) { value.cloudVoice = "cedar" }
        value.cloudSpeed = cloudSpeed.isFinite ? min(max(cloudSpeed, 0.75), 1.25) : 1
        value.deliveryInstructions = String(deliveryInstructions.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        if value.deliveryInstructions.isEmpty { value.deliveryInstructions = Self.defaultDelivery }
        value.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.model.isEmpty { value.model = "gpt-4.1-mini" }
        value.maximumResponseWords = min(max(maximumResponseWords, 10), 60)
        value.endOfSpeechDelay = endOfSpeechDelay.isFinite ? min(max(endOfSpeechDelay, 0.5), 3) : 0.8
        value.conversationTimeout = conversationTimeout.isFinite ? min(max(conversationTimeout, 10), 15) : 12
        value.rate = min(max(rate, 0.35), 0.6)
        value.pitch = min(max(pitch, 0.7), 1.2)
        value.volume = min(max(volume, 0), 1)
        return value
    }

    static func load() -> MarvinConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return value.validated()
    }

    func save() {
        if let data = try? JSONEncoder().encode(validated()) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
