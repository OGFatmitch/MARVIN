import AVFoundation
import Foundation

/// One voice-processing engine stays running through listening, speech, and interruptions.
/// Only the player is stopped on barge-in; the microphone is never restarted while locked.
final class RealtimeAudioIO: @unchecked Sendable {
    private let queue: DispatchQueue
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    private var configurationObserver: NSObjectProtocol?
    private var recovery = RealtimeStartupRecovery()
    private var onEvent: @Sendable (String) -> Void = { _ in }
    private var installed = false
    private var stopped = false
    private var outputGeneration = UUID()
    private var scheduledFrames: Int64 = 0
    private var completedFrames: Int64 = 0
    private var pendingBuffers = 0
    private var drain: (@Sendable () -> Void)?
    private var streamContinuation: AsyncThrowingStream<Data, Error>.Continuation?

    init(queue: DispatchQueue) { self.queue = queue }

    func start(volume: Float, onEvent: @escaping @Sendable (String) -> Void) async throws -> AsyncThrowingStream<Data, Error> {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    guard !self.stopped else { throw CancellationError() }
                    let input = self.engine.inputNode
                    try input.setVoiceProcessingEnabled(true)
                    self.onEvent = onEvent
                    let stream = AsyncThrowingStream<Data, Error>(bufferingPolicy: .bufferingOldest(24)) { sink in
                        self.streamContinuation = sink
                    }
                    try self.installInputTap()
                    self.engine.attach(self.player)
                    self.engine.connect(self.player, to: self.engine.mainMixerNode, format: self.outputFormat)
                    self.player.volume = volume
                    self.configurationObserver = NotificationCenter.default.addObserver(
                        forName: .AVAudioEngineConfigurationChange, object: self.engine, queue: nil
                    ) { [weak self] _ in
                        // Apple's callback uses an internal audio queue. Never stop or
                        // rebuild an engine there; serialize with session operations.
                        guard let self else { return }
                        self.queue.async { self.configurationChanged() }
                    }
                    self.engine.prepare()
                    try self.engine.start()
                    self.reportFormat("Realtime engine started")
                    continuation.resume(returning: stream)
                } catch {
                    self.shutdown()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func enqueue(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do { try self.ensureRunning() }
                catch { continuation.resume(throwing: error); return }
                let frames = data.count / 2
                guard data.count % 2 == 0, frames > 0, frames <= 24000 * 10,
                      self.scheduledFrames + Int64(frames) <= 24000 * 60,
                      let buffer = AVAudioPCMBuffer(pcmFormat: self.outputFormat, frameCapacity: AVAudioFrameCount(frames)),
                      let samples = buffer.floatChannelData?[0] else {
                    continuation.resume(throwing: RealtimeFailure.message("Invalid or oversized Realtime audio.")); return
                }
                buffer.frameLength = AVAudioFrameCount(frames)
                data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                    for index in 0..<frames {
                        let low = UInt16(bytes[index * 2])
                        let high = UInt16(bytes[index * 2 + 1]) << 8
                        samples[index] = Float(Int16(bitPattern: low | high)) / 32768
                    }
                }
                self.recovery.didScheduleAudio()
                self.scheduledFrames += Int64(frames)
                self.pendingBuffers += 1
                let token = self.outputGeneration
                self.player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
                    self.queue.async {
                        guard token == self.outputGeneration, !self.stopped else { return }
                        self.completedFrames += Int64(frames)
                        self.pendingBuffers -= 1
                        if self.pendingBuffers == 0, let callback = self.drain {
                            self.drain = nil; callback()
                        }
                    }
                }
                if !self.player.isPlaying { self.player.play() }
                continuation.resume()
            }
        }
    }

    func setBackgrounded(_ backgrounded: Bool) {
        queue.async { self.recovery.isBackgrounded = backgrounded }
    }

    private func installInputTap() throws {
        let input = engine.inputNode
        if installed { input.removeTap(onBus: 0); installed = false }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let sink = streamContinuation,
              let pcm = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000,
                                     channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: format, to: pcm) else {
            throw RealtimeFailure.message("Microphone format unavailable. Reopen Marvin.")
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 24000 / format.sampleRate) + 16)
            guard let converted = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            if let error { sink.finish(throwing: error); return }
            guard converted.frameLength > 0, let samples = converted.int16ChannelData?[0] else { return }
            if case .dropped = sink.yield(Data(bytes: samples, count: Int(converted.frameLength) * 2)) {
                sink.finish(throwing: RealtimeFailure.message("Network cannot keep up with live audio. Wake Marvin to reconnect."))
            }
        }
        installed = true
    }

    private func configurationChanged() {
        guard !stopped else { return }
        reportFormat("Realtime audio configuration changed")
        // Some notifications describe changes that do not stop this engine.
        guard !engine.isRunning else { return }
        do { try ensureRunning() }
        catch {
            streamContinuation?.finish(throwing: error)
            shutdown()
        }
    }

    private func ensureRunning() throws {
        guard !stopped else { throw CancellationError() }
        guard !engine.isRunning else { return }
        reportFormat("Realtime engine unexpectedly stopped")
        guard recovery.claimRecovery() else {
            throw RealtimeFailure.message("Realtime audio stopped. Reopen Marvin and wake him again; audio details are in Diagnostics.")
        }
        // A format change can stop the engine after start() succeeds. Recover only
        // once, while foregrounded and before any reply audio has been scheduled.
        // The main mixer tracks the hardware output format when the engine restarts.
        try AVAudioSession.sharedInstance().setActive(true)
        try installInputTap() // Refresh conversion for the current hardware format.
        engine.prepare()
        try engine.start()
        guard engine.isRunning else {
            throw RealtimeFailure.message("Realtime audio could not start. Audio details are in Diagnostics.")
        }
        reportFormat("Realtime startup audio recovered")
    }

    private func reportFormat(_ label: String) {
        let input = engine.inputNode.outputFormat(forBus: 0)
        let output = engine.outputNode.inputFormat(forBus: 0)
        onEvent("\(label) · running=\(engine.isRunning) · input \(Int(input.sampleRate))Hz/\(input.channelCount)ch · output \(Int(output.sampleRate))Hz/\(output.channelCount)ch")
    }

    /// Uses the player's render clock, bounded by audio actually received. Subtract output
    /// latency so the server never remembers speech that is still in the hardware buffer.
    func interrupt() async -> Int {
        await withCheckedContinuation { continuation in
            queue.async {
                var frames = self.completedFrames
                if let render = self.player.lastRenderTime, let time = self.player.playerTime(forNodeTime: render) {
                    let latency = AVAudioSession.sharedInstance().outputLatency * 24000
                    frames = max(frames, time.sampleTime - Int64(latency))
                }
                let milliseconds = Int(max(0, min(frames, self.scheduledFrames)) * 1000 / 24000)
                self.clearPlayback()
                continuation.resume(returning: milliseconds)
            }
        }
    }
    func whenDrained(_ callback: @escaping @Sendable () -> Void) {
        queue.async {
            guard !self.stopped else { return }
            if self.pendingBuffers == 0 { callback() } else { self.drain = callback }
        }
    }
    func stopPlayback() { queue.async { self.clearPlayback() } }
    func stop() { queue.async { self.shutdown() } }
    private func clearPlayback() {
        outputGeneration = UUID(); drain = nil
        player.stop(); scheduledFrames = 0; completedFrames = 0; pendingBuffers = 0
    }
    private func shutdown() {
        stopped = true
        recovery.end()
        if let observer = configurationObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationObserver = nil
        }
        streamContinuation?.finish(); streamContinuation = nil
        clearPlayback()
        if installed { engine.inputNode.removeTap(onBus: 0); installed = false }
        engine.stop()
    }
}

enum RealtimeFailure: LocalizedError {
    case message(String)
    case closingFallback(String)
    var errorDescription: String? {
        switch self { case .message(let text), .closingFallback(let text): return text }
    }
}
