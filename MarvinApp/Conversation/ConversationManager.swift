import AVFoundation
import Combine
import Foundation

@MainActor
final class ConversationManager: ObservableObject {
    @Published private(set) var isArmed = false
    @Published private(set) var isArming = false
    private var armedListener: ArmedListeningService?
    private var armedAPIKey: String?
    private var armWork: Task<Void, Never>?
    private var armGeneration = UUID()
    @Published private(set) var interaction: ConversationInteraction = .dormant
    @Published private(set) var phase: VoiceLoopPhase = .ready
    @Published private(set) var liveTranscript = ""
    @Published private(set) var lastReply = ""
    @Published private(set) var context = ConversationContext()
    @Published private(set) var timings: [TimingEvent] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var cloudActive = false
    @Published private(set) var recognitionMode = "Microphone off"
    @Published private(set) var inputRoute = "Inactive"
    @Published private(set) var outputRoute = "Inactive"
    @Published private(set) var voiceStatus = "Idle"
    @Published private(set) var lastTurnLatency = "No completed reply yet"
    private var lastWordUpdate: Double?
    private var responseRequestTime: Double?
    private var responseReadyTime: Double?
    @Published private(set) var apiStatus = "Not contacted"
    @Published private(set) var isInBackground = false
    @Published private(set) var backgroundStatus = "Foreground"
    @Published var configuration = MarvinConfig.load()

    @Published private(set) var realtimeSpend = RealtimeBudget.load().total
    @Published private(set) var realtimeCharged = RealtimeBudget.load().charged
    @Published private(set) var realtimeReserved = RealtimeBudget.load().pending.values.reduce(0, +)
    @Published private(set) var realtimeReplyCount = 0
    private var realtime: RealtimeConversation?
    private var realtimeOpenings = RealtimeOpeningDeck()
    private let speech: any SpeechRecognitionService
    private let llm: any LLMService
    private let tts: any TTSService
    private let audio: AudioSessionManager
    private let backgroundTime = ConversationBackgroundTime()
    private var audioReady = false
    private let keychain = KeychainStore()
    private var work: Task<Void, Never>?
    private var generation = UUID()
    private var startedAt = ProcessInfo.processInfo.systemUptime
    private var subscriptions = Set<AnyCancellable>()

    convenience init() {
        self.init(speech: AppleSpeechRecognitionService(), llm: OpenAIService(),
                  tts: ConfigurableTTSService(), audio: AudioSessionManager())
    }

    init(speech: any SpeechRecognitionService, llm: any LLMService,
         tts: any TTSService, audio: AudioSessionManager) {
        self.speech = speech
        self.llm = llm
        self.tts = tts
        self.audio = audio
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      raw == AVAudioSession.InterruptionType.began.rawValue else { return }
                self?.reset(message: "Audio interrupted. Tap Wake Marvin when ready.")
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                self.refreshRoutes()
                let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                if (self.phase.isBusy || self.isArmed || self.isArming) && (raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                    || raw == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue) {
                    self.reset(message: "Audio device changed. Tap Wake Marvin to use the current route.")
                }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reset(message: "Audio services restarted. Reopen Marvin before the next turn.")
            }.store(in: &subscriptions)
    }

    func armListening() {
        guard !phase.isBusy, !isArmed, !isArming, !isInBackground else { return }
        guard configuration.conversationEngine == .realtime else {
            errorMessage = "Select Realtime in Settings to arm voice commands."
            return
        }
        let id = UUID(); armGeneration = id
        generation = UUID()
        isArming = true; phase = .preparing; errorMessage = nil
        startedAt = ProcessInfo.processInfo.systemUptime; timings = []
        mark("Arm local listening")
        protectAudioGap(token: generation)
        armWork = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.speech.requestPermissions()
                try Task.checkCancellation()
                let key = try self.keychain.read()
                guard !key.isEmpty else { throw LLMError.missingKey }
                guard self.armGeneration == id, !self.isInBackground else { throw CancellationError() }
                self.armedAPIKey = key
                try await self.audio.activate(realtime: true)
                try Task.checkCancellation()
                let listener = ArmedListeningService()
                self.armedListener = listener
                try await listener.start(volume: self.configuration.volume, onCommand: { [weak self] command in
                    guard let self, self.armGeneration == id, self.isArmed else { return }
                    switch command {
                    case .wake: self.wake()
                    case .sleep: self.sendToSleep()
                    }
                }, onFailure: { [weak self] message in
                    guard let self, self.armGeneration == id else { return }
                    self.reset(message: message)
                }, onEvent: { [weak self] event in
                    guard let self, self.armGeneration == id else { return }
                    self.mark(event)
                })
                try Task.checkCancellation()
                guard self.armGeneration == id else { return }
                self.isArmed = true; self.isArming = false; self.audioReady = true
                self.phase = .ready; self.interaction = .armed
                self.recognitionMode = "Local wake listening · no cloud audio"
                self.apiStatus = "Disconnected · local standby"
                self.backgroundTime.end(); self.refreshRoutes()
                self.mark("Armed: say Hey Marvin")
                self.armWork = nil
            } catch {
                guard self.armGeneration == id else { return }
                self.reset(message: error is CancellationError ? nil : error.localizedDescription)
            }
        }
    }

    func sendToSleep() {
        guard phase.isBusy, !isArming else { return }
        realtime?.requestSleep()
    }

    func wake() {
        guard !phase.isBusy, !isArming, !isInBackground || isArmed else { return }
        errorMessage = nil
        voiceStatus = "Idle"
        let key: String
        do {
            if isArmed { key = armedAPIKey ?? "" } else { key = try keychain.read() }
            guard !key.isEmpty else { throw LLMError.missingKey }
        } catch { errorMessage = error.localizedDescription; return }
        configuration = configuration.validated()
        let config = configuration
        let token = UUID()
        generation = token
        interaction = .waking
        context.clear()
        phase = .preparing
        liveTranscript = ""
        lastReply = ""
        timings = []
        realtimeReplyCount = 0
        responseRequestTime = nil
        responseReadyTime = nil
        lastWordUpdate = nil
        lastTurnLatency = "No completed reply yet"
        startedAt = ProcessInfo.processInfo.systemUptime
        mark(isArmed ? "Wake from local standby" : "Button wake")
        if isArmed { armedListener?.beginConversation() }
        protectAudioGap(token: token)
        work = Task { [weak self] in
            guard let self, self.generation == token else { return }
            defer {
                if self.generation == token {
                    self.realtime?.stop(); self.realtime = nil
                    self.speech.cancel()
                    self.tts.endConversation()
                    self.backgroundTime.end()
                    self.cloudActive = false
                    if self.isArmed, let listener = self.armedListener {
                        listener.standby()
                        self.audioReady = true
                        self.recognitionMode = "Local wake listening · no cloud audio"
                        self.apiStatus = "Disconnected · local standby"
                        self.interaction = .armed
                        self.backgroundStatus = self.isInBackground ? "Armed · local background listening" : "Foreground"
                    } else {
                        self.audioReady = false
                        self.backgroundStatus = self.isInBackground ? "Dormant · no background activity" : "Foreground"
                        self.recognitionMode = "Microphone off"
                        self.audio.deactivate()
                        self.interaction = .dormant
                    }
                    self.refreshRoutes()
                    self.context.clear()
                    self.liveTranscript = ""
                    self.lastReply = ""
                    self.voiceStatus = "Idle"
                    self.mark(self.isArmed ? "Conversation cleared / returned to local standby" : "Dormant / conversation cleared")
                    self.phase = .ready
                    self.work = nil
                }
            }
            do {
                if config.conversationEngine == .realtime {
                    let realtime: RealtimeConversation
                    if self.isArmed, let listener = self.armedListener {
                        realtime = RealtimeConversation(sharedAudio: listener.audio, input: { listener.openCloudInput() })
                        self.mark("Realtime startup: using armed microphone")
                    } else {
                        self.mark("Realtime startup: activating iPhone audio session")
                        try await self.audio.activate(realtime: true)
                        self.mark("Realtime startup: audio session activated")
                        try Task.checkCancellation()
                        realtime = RealtimeConversation()
                    }
                    self.realtime = realtime
                    do {
                    try await realtime.run(configuration: config, key: key, opening: self.realtimeOpenings.next()) { [weak self] update in
                        guard let self, self.generation == token else { return }
                        switch update {
                        case .ready:
                            self.audioReady = true
                            self.backgroundTime.end()
                            self.cloudActive = true
                            self.recognitionMode = "Live audio to OpenAI · interruptions enabled"
                            self.apiStatus = "Realtime connected"
                            self.refreshRoutes()
                        case .listening:
                            self.interaction = .engaged; self.phase = .listening
                        case .thinking:
                            self.phase = .thinking
                        case .speaking:
                            self.phase = .speaking
                            if self.interaction != .exiting { self.interaction = .engaged }
                            self.voiceStatus = "Realtime · " + config.realtimeVoice
                        case .closing:
                            self.interaction = .exiting; self.phase = .thinking
                        case .transcript(let text): self.lastReply = text
                        case .timing(let label): self.mark(label)
                        case .latency(let delay):
                            self.lastTurnLatency = String(format: "After detected speech end: %.2fs (+ 0.45s silence detection)", delay)
                        case .budget(let budget):
                            self.realtimeSpend = budget.total
                            self.realtimeCharged = budget.charged
                            self.realtimeReserved = budget.pending.values.reduce(0, +)
                        case .replyCount(let count): self.realtimeReplyCount = count
                        }
                    }
                    } catch RealtimeFailure.closingFallback(let line) {
                        try Task.checkCancellation()
                        guard self.generation == token else { throw CancellationError() }
                        self.protectAudioGap(token: token)
                        self.interaction = .exiting; self.phase = .speaking
                        self.cloudActive = false; self.lastReply = line
                        self.voiceStatus = "Local closing fallback"
                        var local = config; local.voiceProvider = .apple
                        try await self.tts.speak(line, configuration: local) { [weak self] in
                            guard let self, self.generation == token else { return }
                            self.backgroundTime.end()
                            self.mark("Local limit farewell playback")
                        }
                    }
                    return
                }
                try await self.speech.requestPermissions()
                try Task.checkCancellation()
                try await self.audio.activate()
                try self.speech.beginConversation()
                self.audioReady = true
                self.recognitionMode = "Microphone active · transcription paused"
                self.mark("Conversation microphone started")
                try await self.tts.prepareConversation(configuration: config, apiKey: key)
                try Task.checkCancellation()
                self.refreshRoutes()
                try await self.say(ConversationInteraction.openings.randomElement()!, config: config, token: token)
                try Task.checkCancellation()
                self.interaction = .engaged
                while !Task.isCancelled {
                    self.protectAudioGap(token: token)
                    self.phase = .listening
                    self.liveTranscript = ""
                    self.lastWordUpdate = nil
                    self.mark("Listening resumed / transcription gate open")
                    self.recognitionMode = config.allowAppleServerRecognition
                        ? "Apple server recognition allowed" : "On-device transcription required"
                    let transcript: String
                    do {
                        transcript = try await self.speech.recognize(configuration: config, onStart: { [weak self] in
                            guard let self, self.generation == token else { return }
                            self.backgroundTime.end()
                            self.mark("Microphone capture active")
                        }) { [weak self] text in
                            guard let self, self.generation == token else { return }
                            let oldWords = self.liveTranscript.lowercased().split { !$0.isLetter && !$0.isNumber }
                            let newWords = text.lowercased().split { !$0.isLetter && !$0.isNumber }
                            if oldWords != newWords { self.lastWordUpdate = ProcessInfo.processInfo.systemUptime }
                            self.liveTranscript = text
                            self.recognitionMode = self.speech.processingDescription
                        }
                    } catch SpeechError.noSpeech {
                        try Task.checkCancellation()
                        self.recognitionMode = "Microphone active · transcription paused"
                        self.interaction = .exiting
                        self.mark("Inactivity / closing conversation")
                        try await self.say(ConversationInteraction.closings.randomElement()!, config: config, token: token)
                        return
                    }
                    try Task.checkCancellation()
                    self.liveTranscript = transcript
                    self.recognitionMode = "Microphone active · transcription paused"
                    self.mark("Transcription complete")
                    self.protectAudioGap(token: token)
                    self.phase = .thinking
                    self.cloudActive = true
                    self.apiStatus = "Request in progress"
                    self.responseRequestTime = ProcessInfo.processInfo.systemUptime
                    self.mark("API request start")
                    let reply: String
                    do {
                        reply = try await self.llm.reply(to: transcript, history: self.context.entries,
                                                        configuration: config, apiKey: key)
                        try Task.checkCancellation()
                    } catch {
                        try Task.checkCancellation()
                        self.cloudActive = false
                        self.apiStatus = "Request failed"
                        self.errorMessage = error.localizedDescription
                        self.context.clear()
                        self.liveTranscript = ""
                        self.lastReply = MarvinPrompt.networkFallback
                        self.phase = .speaking
                        var fallbackConfig = config
                        fallbackConfig.voiceProvider = .apple
                        self.voiceStatus = "Apple · local error response"
                        try await self.tts.speak(MarvinPrompt.networkFallback, configuration: fallbackConfig) { [weak self] in
                            guard let self, self.generation == token else { return }
                            self.backgroundTime.end()
                            self.mark("Fallback TTS start")
                        }
                        return
                    }
                    self.cloudActive = false
                    self.apiStatus = "Response received"
                    self.responseReadyTime = ProcessInfo.processInfo.systemUptime
                    self.mark("Response complete")
                    try await self.say(reply, config: config, token: token)
                    try Task.checkCancellation()
                    self.context.appendExchange(user: transcript, assistant: reply,
                                                maximumPairs: config.maximumHistoryPairs)
                    self.mark("Turn complete")
                    self.responseRequestTime = nil
                    self.responseReadyTime = nil
                }
            } catch is CancellationError {
                // Reset/interruption owns the visible state; stale completions are discarded.
            } catch {
                guard self.generation == token else { return }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func say(_ reply: String, config: MarvinConfig, token: UUID) async throws {
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        protectAudioGap(token: token)
        self.recognitionMode = "Microphone active · transcription paused"
        self.lastReply = reply
        self.phase = .speaking
        self.voiceStatus = config.voiceProvider.title
        try await self.tts.speak(reply, configuration: config, onEvent: { [weak self] event in
            guard let self, self.generation == token else { return }
            switch event {
            case .preparedAudio:
                self.cloudActive = false
                self.voiceStatus = "Prepared voice · local playback"
                self.mark("Prepared speech ready / no network request")
            case .requestStarted:
                self.cloudActive = true
                self.phase = .thinking
                self.voiceStatus = "Generating OpenAI voice"
                self.mark("Speech API request start")
            case .firstAudioReceived:
                self.voiceStatus = "Streaming OpenAI voice"
                self.mark("Speech first audio chunk")
            case .audioReceived:
                self.cloudActive = false
                self.voiceStatus = "OpenAI audio received"
                self.mark("Speech download complete")
            case .appleFallback(let reason):
                self.cloudActive = false
                self.voiceStatus = "Apple fallback"
                self.errorMessage = "OpenAI voice unavailable; using Apple voice. " + reason
                self.mark("Apple speech fallback")
            }
        }, onStart: { [weak self] in
            guard let self, self.generation == token else { return }
            self.backgroundTime.end()
            self.phase = .speaking
            self.mark("TTS start / time to audible reply")
            if let sent = self.responseRequestTime, let ready = self.responseReadyTime {
                let now = ProcessInfo.processInfo.systemUptime
                self.lastTurnLatency = String(format: "Endpoint %.1fs · reply %.1fs · voice %.1fs",
                    max(0, sent - (self.lastWordUpdate ?? sent)), ready - sent, now - ready)
            }
        })
        try Task.checkCancellation()
    }

    func finishListening() {
        if phase == .listening && !liveTranscript.isEmpty { speech.finish() }
    }

    func reset(message: String? = nil) {
        generation = UUID()
        armGeneration = UUID()
        armWork?.cancel(); armWork = nil
        isArmed = false; isArming = false; armedAPIKey = nil
        armedListener?.stop(); armedListener = nil
        work?.cancel(); work = nil
        realtime?.stop(); realtime = nil
        speech.cancel()
        tts.endConversation()
        backgroundTime.end()
        audioReady = false
        backgroundStatus = isInBackground ? "Dormant · no background activity" : "Foreground"
        audio.deactivate()
        interaction = .dormant
        phase = .ready
        cloudActive = false
        recognitionMode = "Microphone off"
        apiStatus = "Not contacted"
        voiceStatus = "Idle"
        context.clear()
        liveTranscript = ""
        lastReply = ""
        timings = []
        realtimeReplyCount = 0
        responseRequestTime = nil
        responseReadyTime = nil
        lastWordUpdate = nil
        lastTurnLatency = "No completed reply yet"
        errorMessage = message
        refreshRoutes()
    }

    func setBackgrounded(_ backgrounded: Bool) {
        isInBackground = backgrounded
        realtime?.setBackgrounded(backgrounded)
        armedListener?.setBackgrounded(backgrounded)
        if backgrounded && phase.isBusy && !audioReady {
            reset(message: "Open Marvin and wait for the opening before locking the phone.")
            return
        }
        backgroundStatus = backgrounded
            ? (phase.isBusy ? "Active conversation · background audio" : (isArmed ? "Armed · local background listening" : "Dormant · no background activity"))
            : "Foreground"
        if phase.isBusy { mark(backgrounded ? "Entered background" : "Returned to foreground") }
    }

    private func protectAudioGap(token: UUID) {
        backgroundTime.begin { [weak self] in
            guard let self, self.generation == token else { return }
            self.reset(message: "iOS ended the background response time. Open Marvin and wake him again.")
        }
    }

    func reconcileBudget(verifiedTotal: Double) -> Bool {
        guard !phase.isBusy, !isArmed, !isArming else { return false }
        var budget = RealtimeBudget.load()
        guard budget.reconcile(verifiedTotal: verifiedTotal) else { return false }
        budget.save()
        realtimeSpend = budget.total; realtimeCharged = budget.charged; realtimeReserved = 0
        return true
    }
    func saveConfiguration(_ config: MarvinConfig) {
        configuration = config.validated()
        configuration.save()
    }
    private func refreshRoutes() {
        inputRoute = audio.inputRoute.isEmpty ? "Inactive" : audio.inputRoute
        outputRoute = audio.outputRoute.isEmpty ? "Inactive" : audio.outputRoute
    }
    private func mark(_ label: String) {
        if timings.count >= 200 { timings.removeFirst() }
        timings.append(TimingEvent(label: label,
            milliseconds: Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000)))
    }
}
