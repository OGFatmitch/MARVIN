import AVFoundation
import UIKit

@MainActor
final class AudioSessionManager {
    // AVAudioSession is process-wide. Use one FIFO queue for all managers (including
    // voice preview), so a previous turn's teardown cannot overtake a new activation.
    static let sessionQueue = DispatchQueue(label: "com.marvin.audio-session", qos: .userInitiated)
    private let session = AVAudioSession.sharedInstance()
    var inputRoute: String { session.currentRoute.inputs.map(\.portName).joined(separator: ", ") }
    var outputRoute: String { session.currentRoute.outputs.map(\.portName).joined(separator: ", ") }

    func activate(realtime: Bool = false) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Self.sessionQueue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    // These synchronous system calls may block: never run on the UI thread.
                    // HFP routing and voice-processing tuning remain a separate milestone.
                    try session.setCategory(.playAndRecord, mode: realtime ? .voiceChat : .default, options: [.defaultToSpeaker])
                    try session.setActive(true)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        // Reset may have occurred while the system call was in flight. Its queued
        // deactivation still runs; the cancelled caller must not start capture/playback.
        try Task.checkCancellation()
    }

    func deactivate() {
        // Enqueue immediately, rather than spawning an unstructured Task whose order
        // could change. Callers stop capture/playback before submitting this operation.
        Self.sessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}


/// Finite execution allowance for gaps between real recording and playback.
/// No silent audio loop and no attempt to keep a dormant app running.
@MainActor
final class ConversationBackgroundTime {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var generation = UUID()

    func begin(onExpiration: @escaping @MainActor () -> Void) {
        guard identifier == .invalid else { return }
        let token = UUID()
        generation = token
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Marvin response") { [weak self] in
            guard let self, self.generation == token else { return }
            self.end()
            onExpiration()
        }
        if identifier == .invalid { onExpiration() }
    }

    func end() {
        generation = UUID()
        let previous = identifier
        identifier = .invalid
        if previous != .invalid { UIApplication.shared.endBackgroundTask(previous) }
    }
}
