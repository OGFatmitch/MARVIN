import AVFoundation

/// Selects speech independently from the language model. Previews disable fallback so
/// a failed cloud request cannot be mistaken for an audition of the cloud voice.
@MainActor
final class ConfigurableTTSService: TTSService {
    private let apple = AppleTTSService()
    private let cloud = OpenAITTSService()
    private let allowFallback: Bool
    private var generation = UUID()

    init(allowFallback: Bool = true) { self.allowFallback = allowFallback }

    func prepareConversation(configuration: MarvinConfig, apiKey: String) async throws {
        if configuration.voiceProvider == .openAI {
            try await cloud.prepareConversation(configuration: configuration, apiKey: apiKey)
        }
    }

    func endConversation() {
        stop()
        cloud.endConversation()
    }

    func speak(_ text: String, configuration: MarvinConfig,
               onEvent: @escaping @MainActor (SpeechPlaybackEvent) -> Void,
               onStart: @escaping @MainActor () -> Void) async throws {
        stop()
        let token = UUID()
        generation = token
        guard configuration.voiceProvider == .openAI else {
            try await apple.speak(text, configuration: configuration, onEvent: onEvent, onStart: onStart)
            return
        }
        // Never repeat the entire line if cloud playback has already begun.
        var playbackBegan = false
        do {
            try await cloud.speak(text, configuration: configuration, onEvent: onEvent) {
                playbackBegan = true
                onStart()
            }
        } catch {
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            guard !(error is CancellationError), allowFallback, !playbackBegan else { throw error }
            onEvent(.appleFallback(error.localizedDescription))
            try await apple.speak(text, configuration: configuration, onEvent: onEvent, onStart: onStart)
        }
    }

    func stop() {
        generation = UUID()
        cloud.stop()
        apple.stop()
    }
}

/// Streams PCM into an audio engine. The engine and buffers are owned by a serial
/// worker queue so audio setup never blocks the UI thread.
@MainActor
final class OpenAITTSService: TTSService {
    private let client: any SpeechAudioClient
    private let credentials: () throws -> String
    private var conversationKey: String?
    private var preparedClips: [String: Data] = [:]
    private var requestTask: Task<Void, Error>?
    private var playback: StreamingPCMPlayback?
    private var generation = UUID()

    init(client: any SpeechAudioClient = OpenAISpeechClient(),
         credentials: @escaping () throws -> String = { try KeychainStore().read() }) {
        self.client = client
        self.credentials = credentials
    }

    func prepareConversation(configuration: MarvinConfig, apiKey: String) async throws {
        endConversation()
        var clips: [String: Data] = [:]
        for line in PreparedSpeechCache.lines {
            if let data = await PreparedSpeechCache.shared.audio(for: line, configuration: configuration) {
                clips[line] = data
            }
            try Task.checkCancellation()
        }
        conversationKey = apiKey
        preparedClips = clips
    }

    func endConversation() {
        stop()
        conversationKey = nil
        preparedClips.removeAll()
    }

    func speak(_ text: String, configuration: MarvinConfig,
               onEvent: @escaping @MainActor (SpeechPlaybackEvent) -> Void,
               onStart: @escaping @MainActor () -> Void) async throws {
        stop()
        try Task.checkCancellation()
        let key = try conversationKey ?? credentials()
        guard !key.isEmpty else { throw SpeechAPIError.missingKey }
        let token = UUID()
        generation = token
        let playback = StreamingPCMPlayback(volume: configuration.volume)
        self.playback = playback
        try await withTaskCancellationHandler {
            defer {
                playback.stop()
                if generation == token { self.playback = nil; requestTask = nil }
            }
            let task = Task {
                let prepared: Data?
                if let clip = self.preparedClips[text] { prepared = clip }
                else if self.conversationKey != nil { prepared = nil }
                else { prepared = await PreparedSpeechCache.shared.audio(for: text, configuration: configuration) }
                try Task.checkCancellation()
                guard self.generation == token else { throw CancellationError() }
                if let prepared {
                    onEvent(.preparedAudio)
                    _ = try await playback.enqueue(prepared)
                    try Task.checkCancellation()
                    guard self.generation == token else { throw CancellationError() }
                    onStart()
                } else {
                    onEvent(.requestStarted)
                    try await client.stream(text, configuration: configuration, apiKey: key) { data in
                        try Task.checkCancellation()
                        let started = try await playback.enqueue(data)
                        if started {
                            await MainActor.run {
                                guard self.generation == token else { return }
                                onEvent(.firstAudioReceived)
                                onStart()
                            }
                        }
                    }
                    try Task.checkCancellation()
                    guard self.generation == token else { throw CancellationError() }
                    onEvent(.audioReceived)
                }
                try await playback.finish()
            }
            requestTask = task
            do { try await task.value }
            catch {
                if generation != token || Task.isCancelled { throw CancellationError() }
                throw error
            }
        } onCancel: {
            playback.stop()
            Task { @MainActor [weak self] in
                guard self?.generation == token else { return }
                self?.stop()
            }
        }
    }

    func stop() {
        generation = UUID()
        requestTask?.cancel(); requestTask = nil
        playback?.stop(); playback = nil
    }
}

private final class StreamingPCMPlayback: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MARVIN.streaming-playback")
    // All mutable state below is accessed exclusively on queue.
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var pendingBuffers = 0
    private var stopped = false
    private var terminalResult: Result<Void, Error>?
    private var drain: CheckedContinuation<Void, Error>?
    private var watchdog: DispatchWorkItem?
    private let volume: Float

    init(volume: Float) { self.volume = volume }

    func enqueue(_ data: Data) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    guard !self.stopped else {
                        try self.terminalResult?.get()
                        throw CancellationError()
                    }
                    guard !data.isEmpty, data.count.isMultiple(of: 2),
                          let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1),
                          let buffer = AVAudioPCMBuffer(pcmFormat: format,
                              frameCapacity: AVAudioFrameCount(data.count / 2)),
                          let samples = buffer.floatChannelData?[0] else {
                        throw SpeechAPIError.invalidResponse
                    }
                    buffer.frameLength = buffer.frameCapacity
                    data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                        for index in 0..<Int(buffer.frameLength) {
                            let bits = UInt16(bytes[index * 2]) | (UInt16(bytes[index * 2 + 1]) << 8)
                            samples[index] = Float(Int16(bitPattern: bits)) / 32_768
                        }
                    }
                    let first = self.engine == nil
                    if first {
                        let engine = AVAudioEngine()
                        let player = AVAudioPlayerNode()
                        engine.attach(player)
                        engine.connect(player, to: engine.mainMixerNode, format: format)
                        player.volume = self.volume
                        self.engine = engine
                        self.player = player
                        engine.prepare()
                        try engine.start()
                        let watchdog = DispatchWorkItem { [weak self] in
                            self?.complete(.failure(TTSError.timedOut))
                        }
                        self.watchdog = watchdog
                        self.queue.asyncAfter(deadline: .now() + 65, execute: watchdog)
                    }
                    self.pendingBuffers += 1
                    self.player!.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                        guard let self else { return }
                        self.queue.async {
                            guard !self.stopped else { return }
                            self.pendingBuffers -= 1
                            if self.pendingBuffers == 0, self.drain != nil { self.complete(.success(())) }
                        }
                    }
                    if first { self.player!.play() }
                    continuation.resume(returning: first)
                } catch {
                    self.complete(.failure(error))
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func finish() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard !self.stopped else {
                    continuation.resume(with: self.terminalResult ?? .failure(CancellationError()))
                    return
                }
                self.drain = continuation
                if self.pendingBuffers == 0 { self.complete(.success(())) }
            }
        }
    }

    func stop() { queue.async { self.complete(.failure(CancellationError())) } }

    private func complete(_ result: Result<Void, Error>) {
        guard !stopped else { return }
        stopped = true
        terminalResult = result
        watchdog?.cancel(); watchdog = nil
        player?.stop()
        engine?.stop()
        player = nil; engine = nil
        let continuation = drain
        drain = nil
        continuation?.resume(with: result)
    }
}
