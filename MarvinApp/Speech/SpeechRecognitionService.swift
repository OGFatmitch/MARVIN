import AVFoundation
import Speech

@MainActor
protocol SpeechRecognitionService: AnyObject {
    var processingDescription: String { get }
    func beginConversation() throws
    func requestPermissions() async throws
    func recognize(configuration: MarvinConfig,
                   onStart: @escaping @MainActor () -> Void,
                   onPartial: @escaping @MainActor (String) -> Void) async throws -> String
    func finish()
    func cancel()
}

enum SpeechError: LocalizedError {
    case microphoneDenied, speechDenied, unavailable, localUnavailable, noSpeech, invalidInput
    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "Microphone permission is required. Enable it in iPhone Settings → Marvin."
        case .speechDenied: return "Speech Recognition permission is required. Enable it in iPhone Settings → Marvin."
        case .unavailable: return "Speech recognition is currently unavailable. Try again shortly."
        case .localUnavailable: return "On-device English speech recognition is unavailable. Check installed language support, or explicitly allow Apple server recognition in Marvin Settings."
        case .noSpeech: return "No speech detected. Tap Wake Marvin and try again."
        case .invalidInput: return "No working microphone route. Reconnect the microphone and try again."
        }
    }
}

@MainActor
final class AppleSpeechRecognitionService: SpeechRecognitionService {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<String, Error>?
    private var silenceTask: Task<Void, Never>?
    private var inactivityTask: Task<Void, Never>?
    private var limitTask: Task<Void, Never>?
    private let inputGate = SpeechInputGate()
    private var hasTap = false
    private var transcript = ""
    private var generation = UUID()
    private(set) var processingDescription = "Microphone off"

    func requestPermissions() async throws {
        let microphone = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        try Task.checkCancellation()
        guard microphone else { throw SpeechError.microphoneDenied }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        try Task.checkCancellation()
        guard speech == .authorized else { throw SpeechError.speechDenied }
    }

    func beginConversation() throws {
        cancel()
        // The hardware input must be established while unlocked. Keep it alive
        // until dormancy; only gate delivery to each short recognition request.
        engine = AVAudioEngine()
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechError.invalidInput }
        let gate = inputGate
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            gate.append(buffer)
        }
        hasTap = true
        do {
            engine.prepare()
            try engine.start()
        } catch {
            cancel()
            throw error
        }
        processingDescription = "Microphone active · transcription paused"
    }

    func recognize(configuration: MarvinConfig,
                   onStart: @escaping @MainActor () -> Void,
                   onPartial: @escaping @MainActor (String) -> Void) async throws -> String {
        resolve(.failure(CancellationError()))
        try Task.checkCancellation()
        guard engine.isRunning else { throw SpeechError.invalidInput }
        guard let recognizer, recognizer.isAvailable else { throw SpeechError.unavailable }
        let local = recognizer.supportsOnDeviceRecognition
        guard local || configuration.allowAppleServerRecognition else { throw SpeechError.localUnavailable }
        processingDescription = local ? "On-device transcription" : "Apple server transcription may be active"
        let token = UUID()
        generation = token
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                request.requiresOnDeviceRecognition = local
                request.taskHint = .dictation
                request.contextualStrings = ["Marvin", "Mitch", "containment", "citizen development"]
                self.request = request
                recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    let text = result?.bestTranscription.formattedString
                    let final = result?.isFinal ?? false
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token, self.continuation != nil else { return }
                        if let text, text.contains(where: { $0.isLetter || $0.isNumber }) {
                            self.inactivityTask?.cancel(); self.inactivityTask = nil
                            // Punctuation-only revisions are not new human speech.
                            let changed = Self.words(self.transcript) != Self.words(text)
                            self.transcript = String(text.prefix(configuration.maximumTranscriptCharacters))
                            onPartial(self.transcript)
                            if final { self.finish(); return }
                            if changed { self.scheduleEnd(after: configuration.endOfSpeechDelay) }
                        }
                        if let error { self.resolve(.failure(error)) }
                    }
                }
                inputGate.setRequest(request)
                onStart()
                inactivityTask = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: UInt64(configuration.conversationTimeout * 1_000_000_000)) }
                    catch { return }
                    guard self?.generation == token else { return }
                    self?.finish()
                }
                limitTask = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: UInt64(configuration.maximumRecordingDuration * 1_000_000_000)) }
                    catch { return }
                    self?.finish()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.generation == token else { return }
                self?.cancel()
            }
        }
    }

    private func scheduleEnd(after seconds: Double) {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            catch { return }
            self?.finish()
        }
    }

    func finish() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        resolve(text.isEmpty ? .failure(SpeechError.noSpeech) : .success(text))
    }
    func cancel() {
        resolve(.failure(CancellationError()))
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        processingDescription = "Microphone off"
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    private func resolve(_ result: Result<String, Error>) {
        generation = UUID()
        silenceTask?.cancel(); silenceTask = nil
        limitTask?.cancel(); limitTask = nil
        inactivityTask?.cancel(); inactivityTask = nil
        inputGate.setRequest(nil)
        request?.endAudio()
        recognitionTask?.cancel(); recognitionTask = nil
        request = nil
        transcript = ""
        let pending = continuation
        continuation = nil
        processingDescription = engine.isRunning ? "Microphone active · transcription paused" : "Microphone off"
        pending?.resume(with: result)
    }
}


/// Synchronizes render-thread delivery with main-thread recognition transitions.
/// Closing the gate waits for any in-flight append before ending that request.
private final class SpeechInputGate: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func setRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        request?.append(buffer)
    }
}
