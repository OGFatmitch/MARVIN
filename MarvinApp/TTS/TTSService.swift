import AVFoundation
import Combine

enum SpeechPlaybackEvent {
    case preparedAudio
    case requestStarted
    case firstAudioReceived
    case audioReceived
    case appleFallback(String)
}

@MainActor
protocol TTSService: AnyObject {
    func prepareConversation(configuration: MarvinConfig, apiKey: String) async throws
    func endConversation()
    func speak(_ text: String, configuration: MarvinConfig,
               onEvent: @escaping @MainActor (SpeechPlaybackEvent) -> Void,
               onStart: @escaping @MainActor () -> Void) async throws
    func stop()
}

extension TTSService {
    func prepareConversation(configuration: MarvinConfig, apiKey: String) async throws {}
    func endConversation() { stop() }
    func speak(_ text: String, configuration: MarvinConfig,
               onStart: @escaping @MainActor () -> Void) async throws {
        try await speak(text, configuration: configuration, onEvent: { _ in }, onStart: onStart)
    }
}

enum TTSError: LocalizedError {
    case timedOut
    var errorDescription: String? { "Speech playback did not finish. Check audio output and try again." }
}

@MainActor
final class AppleTTSService: NSObject, TTSService, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Error>?
    private var utterance: AVSpeechUtterance?
    private var onStart: (@MainActor () -> Void)?
    private var timeoutTask: Task<Void, Never>?
    private var generation = UUID()

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    func speak(_ text: String, configuration: MarvinConfig,
               onEvent: @escaping @MainActor (SpeechPlaybackEvent) -> Void,
               onStart: @escaping @MainActor () -> Void) async throws {
        stop()
        try Task.checkCancellation()
        let token = UUID()
        generation = token
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.onStart = onStart
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = AppleVoiceSelection.resolve(configuration.voiceIdentifier)
                utterance.rate = configuration.rate
                utterance.pitchMultiplier = configuration.pitch
                utterance.volume = configuration.volume
                self.utterance = utterance
                synthesizer.speak(utterance)
                timeoutTask = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                    self?.complete(.failure(TTSError.timedOut), stopPlayback: true)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.generation == token else { return }
                self?.stop()
            }
        }
    }

    func stop() { complete(.failure(CancellationError()), stopPlayback: true) }

    private func complete(_ result: Result<Void, Error>, stopPlayback: Bool = false) {
        generation = UUID()
        timeoutTask?.cancel(); timeoutTask = nil
        let pending = continuation
        continuation = nil
        utterance = nil
        onStart = nil
        if stopPlayback { synthesizer.stopSpeaking(at: .immediate) }
        pending?.resume(with: result)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.utterance === utterance else { return }
            self.onStart?()
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.utterance === utterance else { return }
            self.complete(.success(()))
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.utterance === utterance else { return }
            self.complete(.failure(CancellationError()))
        }
    }
}

// Shared by playback and Settings so the displayed automatic voice is the one actually used.
enum AppleVoiceSelection {
    static var englishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en-") }
            .sorted {
                if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
                if ($0.language == "en-GB") != ($1.language == "en-GB") { return $0.language == "en-GB" }
                return $0.identifier < $1.identifier
            }
    }

    static func resolve(_ identifier: String) -> AVSpeechSynthesisVoice? {
        if !identifier.isEmpty, let selected = AVSpeechSynthesisVoice(identifier: identifier) { return selected }
        // Preserve Apple's original British default. Quality tiers are not a naturalness
        // ranking across voice families; audition alternatives explicitly in Settings.
        return AVSpeechSynthesisVoice(language: "en-GB")
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    static func label(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium: quality = "Premium"
        case .enhanced: quality = "Enhanced"
        default: quality = "Standard"
        }
        return "\(voice.name) · \(voice.language) · \(quality)"
    }
}

@MainActor
final class VoicePreview: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var playbackStatus = ""
    @Published private(set) var startupMilliseconds: Int?
    private let tts = ConfigurableTTSService(allowFallback: false)
    private let audio = AudioSessionManager()
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func play(configuration: MarvinConfig) {
        stop()
        errorMessage = nil
        let token = UUID()
        generation = token
        isPlaying = true
        startupMilliseconds = nil
        playbackStatus = "Preparing audio…"
        let startedAt = ProcessInfo.processInfo.systemUptime
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == token {
                    self.isPlaying = false
                    self.audio.deactivate()
                    self.task = nil
                }
            }
            do {
                try await self.audio.activate()
                try await self.tts.speak("Mitch has another idea. Do give me a moment to recover from the last one.",
                    configuration: configuration.validated(), onEvent: { [weak self] event in
                        guard let self, self.generation == token else { return }
                        switch event {
                        case .preparedAudio: self.playbackStatus = "Playing prepared voice"
                        case .requestStarted: self.playbackStatus = "OpenAI speech request active…"
                        case .firstAudioReceived: self.playbackStatus = "Streaming OpenAI voice…"
                        case .audioReceived: self.playbackStatus = "Playing OpenAI voice"
                        case .appleFallback(let reason): self.playbackStatus = reason
                        }
                    }, onStart: { [weak self] in
                        guard let self, self.generation == token else { return }
                        self.startupMilliseconds = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000)
                        self.playbackStatus = configuration.voiceProvider == .openAI ? "Playing OpenAI voice" : "Playing Apple voice"
                    })
                if self.generation == token { self.playbackStatus = "Preview finished" }
            } catch is CancellationError {
            } catch {
                if self.generation == token {
                    self.errorMessage = error.localizedDescription
                    self.playbackStatus = "Preview failed"
                }
            }
        }
    }

    func stop() {
        generation = UUID()
        task?.cancel(); task = nil
        tts.stop()
        if isPlaying { audio.deactivate() }
        isPlaying = false
        playbackStatus = ""
    }
}


@MainActor
final class PreparedVoiceLines: ObservableObject {
    @Published private(set) var isPreparing = false
    @Published private(set) var readyCount = 0
    @Published private(set) var message = ""
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func refresh(configuration: MarvinConfig) {
        stop()
        let token = generation
        readyCount = 0
        task = Task {
            let count = await PreparedSpeechCache.shared.count(configuration: configuration)
            guard generation == token else { return }
            readyCount = count
        }
    }

    func prepare(configuration: MarvinConfig) {
        stop()
        let token = generation
        isPreparing = true
        message = "Preparing voice lines…"
        task = Task {
            defer { if generation == token { isPreparing = false; task = nil } }
            do {
                let key = try KeychainStore().read()
                guard !key.isEmpty else { throw SpeechAPIError.missingKey }
                try await PreparedSpeechCache.shared.prepare(configuration: configuration, apiKey: key) { count in
                    await MainActor.run {
                        guard self.generation == token else { return }
                        self.readyCount = count
                        self.message = "Prepared \(count) of \(PreparedSpeechCache.lines.count) lines"
                    }
                }
                try Task.checkCancellation()
                if generation == token { message = "Ready for quick wake and closing remarks." }
            } catch is CancellationError {
            } catch {
                if generation == token { message = error.localizedDescription }
            }
        }
    }

    func clear(configuration: MarvinConfig) {
        stop()
        let token = generation
        task = Task {
            do {
                try await PreparedSpeechCache.shared.clear()
                guard generation == token else { return }
                readyCount = 0
                message = "Prepared lines removed."
            } catch { if generation == token { message = error.localizedDescription } }
        }
    }

    func stop() {
        generation = UUID()
        task?.cancel(); task = nil
        isPreparing = false
        message = ""
    }
}
