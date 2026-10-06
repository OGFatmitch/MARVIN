import AVFoundation
import Foundation

@MainActor
final class RealtimeConversation {
    enum Update {
        case ready, listening, thinking, speaking, closing
        case transcript(String), timing(String), latency(Double), budget(RealtimeBudget), replyCount(Int)
    }
    private let io: RealtimeAudioIO
    private let sharedInput: (() -> AsyncThrowingStream<Data, Error>)?
    private var didStop = false

    init(sharedAudio: RealtimeAudioIO? = nil, input: (() -> AsyncThrowingStream<Data, Error>)? = nil) {
        io = sharedAudio ?? RealtimeAudioIO(queue: AudioSessionManager.sessionQueue)
        sharedInput = input
    }
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var capture: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var lifetime: Task<Void, Never>?
    private var ping: Task<Void, Never>?
    private var running = false
    private var failure: Error?
    private var configured = false
    private var turn = RealtimeTurnState()
    private var reservation: String?
    private var budget = RealtimeBudget.load()
    private var responseCount = 0
    private var humanSpeaking = false
    private var pendingReply = false
    private var closing = false
    private var limitExit = RealtimeLimitExit()
    private var closingDeadline: Task<Void, Never>?
    private var receivedAudio = false
    private var truncatedItems = Set<String>()
    private var transcript = ""
    private var opening = ""
    private var speechStoppedAt: Double?
    private var config = MarvinConfig()
    private var update: (Update) -> Void = { _ in }

    func run(configuration: MarvinConfig, key: String, opening: String, onUpdate: @escaping (Update) -> Void) async throws {
        guard budget.canRequest else { throw RealtimeFailure.closingFallback(RealtimeClosingReason.spending.fallback) }
        config = configuration; self.opening = opening; update = onUpdate; running = true
        update(.budget(budget))
        defer { stop() }
        update(.timing("Realtime startup: checking microphone permission"))
        let granted = await AVAudioApplication.requestRecordPermission()
        try Task.checkCancellation()
        guard granted else { throw RealtimeFailure.message("Allow microphone access in iPhone Settings to talk to Marvin.") }
        guard running else { throw CancellationError() }
        var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?model=\(RealtimeProtocol.model)")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let connection = URLSession(configuration: .ephemeral)
        session = connection
        let socket = connection.webSocketTask(with: request)
        socket.maximumMessageSize = 2 * 1024 * 1024
        self.socket = socket
        update(.timing("Realtime startup: opening connection to OpenAI"))
        socket.resume()
        armTimeout(seconds: 20, message: "Realtime connection timed out. Check the connection and API model access.")
        lifetime = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(600)) } catch { return }
            guard let self else { return }
            do { try await self.beginLimitClosing(.time) }
            catch { self.stop(error: RealtimeFailure.closingFallback(RealtimeClosingReason.time.fallback)) }
        }
        ping = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                guard let self, self.running else { return }
                self.socket?.sendPing { [weak self] error in
                    if let error { Task { @MainActor in self?.stop(error: error) } }
                }
            }
        }
        do {
            while running {
                let message = try await socket.receive()
                try Task.checkCancellation()
                guard running else { break }
                let data: Data
                switch message {
                case .string(let string): data = Data(string.utf8)
                case .data(let bytes): data = bytes
                @unknown default: continue
                }
                guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                try await handle(event)
            }
        } catch {
            if let failure { throw failure }
            if running && !Task.isCancelled {
                if let reason = limitExit.reason, !limitExit.sent || !receivedAudio { throw RealtimeFailure.closingFallback(reason.fallback) }
                throw error
            }
        }
        if let failure { throw failure }
        try Task.checkCancellation()
    }

    func requestSleep() {
        guard running, configured else { return }
        Task { [weak self] in
            guard let self else { return }
            do { try await self.beginLimitClosing(.sleep) }
            catch { self.stop(error: RealtimeFailure.closingFallback(RealtimeClosingReason.sleep.fallback)) }
        }
    }

    func setBackgrounded(_ backgrounded: Bool) { io.setBackgrounded(backgrounded) }

    func stop(error: Error? = nil) {
        guard !didStop else { return }
        didStop = true
        if failure == nil, let error {
            if let reason = limitExit.reason, !limitExit.sent || !receivedAudio {
                failure = RealtimeFailure.closingFallback(reason.fallback)
            } else { failure = error }
        }
        running = false
        capture?.cancel(); capture = nil
        timeout?.cancel(); timeout = nil
        lifetime?.cancel(); lifetime = nil
        closingDeadline?.cancel(); closingDeadline = nil
        ping?.cancel(); ping = nil
        if sharedInput == nil { io.stop() } else { io.stopPlayback() }
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        // Do not release unresolved reservations: the server may already have billed them.
    }

    private func send(_ event: [String: Any]) async throws {
        guard running, let socket else { throw CancellationError() }
        try await socket.send(.string(RealtimeProtocol.encode(event)))
    }

    private func handle(_ event: [String: Any]) async throws {
        let type = event["type"] as? String ?? ""
        switch type {
        case "session.created":
            update(.timing("Realtime startup: server connected; sending session settings"))
            try await send(RealtimeProtocol.session(configuration: config))
        case "session.updated":
            guard !configured else { return }
            configured = true
            update(.timing("Realtime startup: settings accepted; starting audio engine"))
            let stream: AsyncThrowingStream<Data, Error>
            if let sharedInput {
                stream = sharedInput()
            } else {
                stream = try await io.start(volume: config.volume) { [weak self] event in
                    Task { @MainActor in
                        guard let self, self.running else { return }
                        self.update(.timing(event))
                    }
                }
            }
            guard running, !Task.isCancelled else {
                if sharedInput == nil { io.stop() }
                throw CancellationError()
            }
            update(.ready); update(.timing("Realtime connected / microphone and echo cancellation active"))
            capture = Task { [weak self] in
                do {
                    for try await data in stream {
                        try Task.checkCancellation()
                        guard let self, self.running else { return }
                        try await self.send(["type": "input_audio_buffer.append", "audio": data.base64EncodedString()])
                    }
                } catch {
                    guard let self, self.running, !Task.isCancelled else { return }
                    self.stop(error: error)
                }
            }
            try await requestReply(line: opening)
        case "input_audio_buffer.speech_started":
            guard limitExit.reason == nil else { return }
            timeout?.cancel()
            humanSpeaking = true; closing = false
            speechStoppedAt = nil
            turn.interrupt()
            let item = turn.itemID
            turn.clearItem()
            let played = await io.interrupt()
            guard running else { return }
            update(.transcript("")); update(.listening)
            update(.timing("Speech detected / stopped Marvin playback"))
            if let item, receivedAudio {
                truncatedItems.insert(item)
                try await send(["type": "conversation.item.truncate", "item_id": item,
                                "content_index": 0, "audio_end_ms": played])
            }
            armTimeout(seconds: 40, message: "Microphone heard continuous speech or noise for 40 seconds. Wake Marvin in a quieter spot.")
        case "input_audio_buffer.speech_stopped":
            guard limitExit.reason == nil else { return }
            humanSpeaking = false
            speechStoppedAt = ProcessInfo.processInfo.systemUptime
            update(.thinking); update(.timing("Realtime end of speech detected"))
            armTimeout(seconds: 20, message: "Realtime did not complete the voice turn. Wake Marvin to reconnect.")
        case "input_audio_buffer.committed":
            guard limitExit.reason == nil else { return }
            pendingReply = true
            if reservation == nil && !humanSpeaking { try await requestReply() }
        case "response.created":
            guard reservation != nil, let response = event["response"] as? [String: Any],
                  let id = response["id"] as? String else {
                throw RealtimeFailure.message("Unexpected Realtime response; stopped to protect the spending limit.")
            }
            turn.begin(id)
            if humanSpeaking || (limitExit.reason != nil && !limitExit.sent) {
                turn.interrupt()
                try await send(["type": "response.cancel", "response_id": id])
            }
        case "response.output_item.added":
            if event["response_id"] as? String == turn.responseID,
               let item = event["item"] as? [String: Any], item["role"] as? String == "assistant",
               let id = item["id"] as? String {
                turn.item(id)
            }
        case "response.output_audio.delta":
            guard turn.accepts(event["response_id"] as? String),
                  let encoded = event["delta"] as? String, let bytes = Data(base64Encoded: encoded) else { return }
            try await io.enqueue(bytes)
            guard running else { return }
            if !receivedAudio {
                receivedAudio = true
                update(.speaking); update(.timing("Realtime first audio scheduled for playback"))
                if let start = speechStoppedAt { update(.latency(ProcessInfo.processInfo.systemUptime - start)) }
                armTimeout(seconds: 60, message: "Realtime reply exceeded its playback deadline. Wake Marvin again.")
            }
        case "response.output_audio_transcript.delta":
            guard turn.accepts(event["response_id"] as? String), let delta = event["delta"] as? String else { return }
            transcript = String((transcript + delta).prefix(4000)); update(.transcript(transcript))
        case "response.done":
            guard let response = event["response"] as? [String: Any],
                  let id = response["id"] as? String, id == turn.responseID,
                  let reserved = reservation else { return }
            let usage = response["usage"] as? [String: Any]
            budget.settle(reserved, usage: usage)
            budget.save(); update(.budget(budget)); reservation = nil
            if limitExit.reason != nil && !limitExit.sent {
                try await requestLimitClosing()
                return
            }
            if limitExit.reason == nil, turn.interrupted, let items = response["output"] as? [[String: Any]] {
                // If interruption arrived before an audio content part existed, truncation
                // would be invalid. Delete that entirely unheard item after generation ends.
                for item in items where item["role"] as? String == "assistant" {
                    if let itemID = item["id"] as? String, !truncatedItems.contains(itemID) {
                        try await send(["type": "conversation.item.delete", "item_id": itemID])
                    }
                }
            }
            let status = response["status"] as? String ?? "failed"
            if status == "failed" {
                throw RealtimeFailure.message("Realtime could not generate a reply. Check API billing and model access, then try again.")
            }
            if pendingReply && !humanSpeaking { try await requestReply(); return }
            guard !humanSpeaking, !turn.interrupted else { return }
            guard receivedAudio else { throw RealtimeFailure.message("Realtime returned no playable audio. Try another voice or Classic mode.") }
            io.whenDrained { [weak self] in
                Task { @MainActor in
                    guard let self, self.running, self.turn.accepts(id), !self.humanSpeaking else { return }
                    self.turn.clearItem()
                    self.update(.timing("Realtime reply playback finished"))
                    if self.closing { self.stop(); return }
                    self.update(.listening)
                    self.armIdle()
                }
            }
        case "error":
            let error = event["error"] as? [String: Any]
            let code = error?["code"] as? String ?? "unknown"
            // A server-VAD cancellation may beat our explicit cancellation during startup.
            if code == "response_cancel_not_active" { return }
            // Show only a bounded code, never raw network payloads or an echoed API key.
            let safeCode = String(code.filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(100))
            let parameter = error?["param"] as? String ?? ""
            let safeParameter = String(parameter.filter { $0.isLetter || $0.isNumber || "_.[]".contains($0) }.prefix(100))
            let detail = safeParameter.isEmpty ? safeCode : "\(safeCode); \(safeParameter)"
            throw RealtimeFailure.message("Realtime error (\(detail)). Check API access/billing or use Classic mode.")
        default: break
        }
    }

    private func requestReply(line: String? = nil) async throws {
        guard running, limitExit.reason == nil, reservation == nil else { return }
        if !budget.canRequest {
            try await beginLimitClosing(.spending)
            return
        }
        guard let reserved = budget.reserve() else { return }
        budget.save(); reservation = reserved; update(.budget(budget))
        turn.awaitingResponse()
        truncatedItems.removeAll()
        responseCount += 1
        update(.replyCount(responseCount))
        pendingReply = false; receivedAudio = false; transcript = ""
        _ = await io.interrupt()
        update(.transcript("")); update(closing ? .closing : .thinking)
        var response: [String: Any] = [:]
        if let line {
            response["instructions"] = RealtimeProtocol.instructions(configuration: config) + "\nFor this reply, say exactly this one line, without a preamble, extra joke, or follow-up question. Stop after the supplied line: \(line)"
        }
        // If the deadline arrived while this response was being prepared, still send
        // it so the existing reservation can settle; response.created cancels it.
        try await send(["type": "response.create", "response": response])
        update(.timing("Realtime response requested"))
        armTimeout(seconds: 20, message: "Realtime response timed out. Wake Marvin to reconnect.")
    }
    private func beginLimitClosing(_ reason: RealtimeClosingReason) async throws {
        guard running, limitExit.begin(reason) else { return }
        closing = true; humanSpeaking = false; pendingReply = false
        timeout?.cancel()
        capture?.cancel(); capture = nil
        update(.closing); update(.timing("Limit farewell: " + reason.rawValue))
        closingDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(35)) } catch { return }
            guard let self, self.running else { return }
            self.stop(error: self.limitExit.sent && self.receivedAudio
                ? RealtimeFailure.message("Closing playback timed out. Marvin is dormant.")
                : RealtimeFailure.closingFallback(reason.fallback))
        }
        // Mark the current turn interrupted before awaiting any socket operation.
        turn.interrupt()
        _ = await io.interrupt()
        // Keep the engine running for locked-phone playback, but end cloud input.
        try await send(["type": "session.update", "session": ["type": "realtime",
            "audio": ["input": ["turn_detection": NSNull()]]]])
        try await send(["type": "input_audio_buffer.clear"])
        guard running else { return }
        limitExit.prepare()
        if reservation != nil {
            if let id = turn.responseID {
                try await send(["type": "response.cancel", "response_id": id])
            }
            // Otherwise response.created will cancel it; response.done settles its
            // usage before issuing the one final response.
        } else { try await requestLimitClosing() }
    }

    private func requestLimitClosing() async throws {
        guard running, let reason = limitExit.claimClosing(hasActiveResponse: reservation != nil) else { return }
        guard let reserved = budget.reserve(closing: true) else {
            throw RealtimeFailure.closingFallback(reason.fallback)
        }
        budget.save(); reservation = reserved; update(.budget(budget))
        turn.awaitingResponse(); truncatedItems.removeAll()
        receivedAudio = false; transcript = ""; speechStoppedAt = nil
        update(.transcript("")); update(.closing)
        try await send(["type": "response.create", "response": reason.response(configuration: config)])
        update(.timing("Generated limit farewell requested"))
    }

    private func armIdle() {
        timeout?.cancel()
        timeout = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: .seconds(self.config.conversationTimeout)) } catch { return }
            guard self.running, self.limitExit.reason == nil, !self.humanSpeaking, self.reservation == nil else { return }
            self.closing = true
            do { try await self.requestReply(line: ConversationInteraction.closings.randomElement()!) }
            catch { self.stop(error: error) }
        }
    }
    private func armTimeout(seconds: Double, message: String) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.stop(error: RealtimeFailure.message(message))
        }
    }
}
