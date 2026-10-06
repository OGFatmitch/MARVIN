import AVFoundation
import Speech

/// Owns the microphone for the entire explicitly armed interval. Only an attached
/// conversation stream can receive PCM for cloud upload; standby has no connection.
@MainActor
final class ArmedListeningService {
    let audio = RealtimeAudioIO(queue: AudioSessionManager.sessionQueue)
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let pcm = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var capture: Task<Void, Never>?
    private var rotation: Task<Void, Never>?
    private var cloud: AsyncThrowingStream<Data, Error>.Continuation?
    private var active = false
    private var running = false
    private var generation = UUID()
    private var recognitionStarted = 0.0
    private var consecutiveFailures = 0
    private var onCommand: (VoiceCommand) -> Void = { _ in }
    private var onFailure: (String) -> Void = { _ in }
    private var onEvent: (String) -> Void = { _ in }

    func start(volume: Float, onCommand: @escaping (VoiceCommand) -> Void,
               onFailure: @escaping (String) -> Void, onEvent: @escaping (String) -> Void) async throws {
        guard let recognizer, recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
            throw RealtimeFailure.message("Local English speech recognition is unavailable. Arm listening requires on-device recognition; manual Wake Marvin still works.")
        }
        self.onCommand = onCommand; self.onFailure = onFailure; self.onEvent = onEvent
        running = true
        let stream = try await audio.start(volume: volume) { [weak self] event in
            Task { @MainActor in self?.onEvent(event) }
        }
        try Task.checkCancellation()
        guard running else { throw CancellationError() }
        startRecognition()
        capture = Task { [weak self] in
            do {
                for try await data in stream {
                    try Task.checkCancellation()
                    guard let self, self.running else { return }
                    if let cloud = self.cloud, case .dropped = cloud.yield(data) {
                        cloud.finish(throwing: RealtimeFailure.message("Live audio upload fell behind. Wake Marvin again."))
                        self.cloud = nil
                    }
                    if let request = self.request,
                       let buffer = AVAudioPCMBuffer(pcmFormat: self.pcm, frameCapacity: AVAudioFrameCount(data.count / 2)),
                       let samples = buffer.int16ChannelData?[0] {
                        buffer.frameLength = buffer.frameCapacity
                        data.copyBytes(to: UnsafeMutableRawBufferPointer(start: samples, count: data.count))
                        request.append(buffer)
                    }
                }
                guard let self, self.running, !Task.isCancelled else { return }
                self.fail("Armed microphone ended. Open Marvin to arm listening again.")
            } catch {
                guard let self, self.running, !Task.isCancelled else { return }
                self.fail("Armed microphone stopped: " + error.localizedDescription)
            }
        }
    }

    func beginConversation() {
        active = true
        pauseRecognition()
        scheduleRecognition(after: 0.2)
    }
    func openCloudInput() -> AsyncThrowingStream<Data, Error> {
        cloud?.finish()
        return AsyncThrowingStream(bufferingPolicy: .bufferingOldest(24)) { sink in
            if running && active { cloud = sink } else { sink.finish(throwing: CancellationError()) }
        }
    }
    func standby() {
        cloud?.finish(); cloud = nil
        active = false
        pauseRecognition()
        // Let the final speaker tail settle before recognizing a new wake phrase.
        scheduleRecognition(after: 1.2)
        onEvent("Armed standby: local recognition only; cloud detached")
    }
    func setBackgrounded(_ backgrounded: Bool) { audio.setBackgrounded(backgrounded) }
    func stop() {
        running = false
        pauseRecognition()
        capture?.cancel(); capture = nil
        cloud?.finish(); cloud = nil
        audio.stop()
    }

    private func pauseRecognition() {
        generation = UUID()
        rotation?.cancel(); rotation = nil
        request?.endAudio(); request = nil
        recognition?.cancel(); recognition = nil
    }
    private func scheduleRecognition(after seconds: Double) {
        guard running else { return }
        let token = generation
        rotation = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.running, self.generation == token else { return }
            self.startRecognition()
        }
    }
    private func startRecognition() {
        guard running, let recognizer, recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
            fail("Local wake listening became unavailable. Open Marvin to arm again, or use manual Wake.")
            return
        }
        pauseRecognition()
        let token = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = ["Hey Marvin", "Marvin go to sleep", "Marvin go back to sleep"]
        self.request = request
        recognitionStarted = ProcessInfo.processInfo.systemUptime
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Extract values before crossing to the main actor. Never store or display
            // standby transcripts; only a recognized command leaves this service.
            let segments = result?.bestTranscription.segments ?? []
            var utterance: [String] = []
            var end: TimeInterval = 0
            for segment in segments {
                if segment.timestamp - end > 0.7 { utterance.removeAll() }
                utterance.append(segment.substring)
                end = segment.timestamp + segment.duration
            }
            let text = utterance.joined(separator: " ")
            let final = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                guard let self, self.running, self.generation == token else { return }
                if let command = VoiceCommandMatcher.command(in: text, active: self.active) {
                    self.consecutiveFailures = 0
                    self.pauseRecognition()
                    self.onCommand(command)
                    if command == .sleep && self.running && self.active { self.scheduleRecognition(after: 0.8) }
                    return
                }
                if final || failed {
                    let elapsed = ProcessInfo.processInfo.systemUptime - self.recognitionStarted
                    self.consecutiveFailures = failed && elapsed < 3 ? self.consecutiveFailures + 1 : 0
                    guard self.consecutiveFailures < 3 else {
                        self.fail("On-device recognition repeatedly stopped. Local listening is disarmed; manual Wake remains available.")
                        return
                    }
                    self.pauseRecognition()
                    self.scheduleRecognition(after: failed ? 1 : 0.1)
                }
            }
        }
        // Rotate recognition tasks, not the microphone engine, before Apple's task
        // duration limit. The brief handoff and battery cost require phone testing.
        rotation = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            guard let self, self.running, self.generation == token else { return }
            self.startRecognition()
        }
    }
    private func fail(_ message: String) {
        guard running else { return }
        stop()
        onFailure(message)
    }
}
