import Foundation
import CryptoKit

protocol SpeechAudioClient {
    func stream(_ text: String, configuration: MarvinConfig, apiKey: String,
                onChunk: @escaping @Sendable (Data) async throws -> Void) async throws
}

enum SpeechAPIError: LocalizedError {
    case missingKey, invalidResponse, http(Int), emptyAudio
    var errorDescription: String? {
        switch self {
        case .missingKey: return "Save your OpenAI API key before trying cloud speech."
        case .invalidResponse: return "OpenAI speech returned an unexpected response."
        case .http(401): return "OpenAI speech rejected the API key. Check the saved key."
        case .http(403): return "Your API key does not have access to OpenAI speech. Check its permissions."
        case .http(429): return "OpenAI speech hit an API quota or rate limit. Check billing and limits."
        case .http(let code): return "OpenAI speech failed (HTTP \(code))."
        case .emptyAudio: return "OpenAI speech returned empty or oversized audio."
        }
    }
}

struct OpenAISpeechClient: SpeechAudioClient {
    static let model = "gpt-4o-mini-tts"
    private let session: URLSession

    init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.timeoutIntervalForResource = MarvinConfig().requestTimeout
        self.session = session ?? URLSession(configuration: config)
    }

    func makeRequest(_ text: String, configuration: MarvinConfig, apiKey: String) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw SpeechAPIError.missingKey }
        let config = configuration.validated()
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.timeoutInterval = config.requestTimeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.requestBody(text, configuration: config)
        return request
    }

    static func requestBody(_ text: String, configuration: MarvinConfig) throws -> Data {
        let config = configuration.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Body(
            model: Self.model, input: String(text.prefix(config.maximumTranscriptCharacters)),
            voice: config.cloudVoice, instructions: config.deliveryInstructions,
            response_format: "pcm", speed: config.cloudSpeed))
    }

    func stream(_ text: String, configuration: MarvinConfig, apiKey: String,
                onChunk: @escaping @Sendable (Data) async throws -> Void) async throws {
        try Task.checkCancellation()
        let request = try makeRequest(text, configuration: configuration, apiKey: apiKey)
        let (bytes, response) = try await session.bytes(for: request)
        // Closing the consumer, cancellation, and validation failures all close the request.
        defer { bytes.task.cancel() }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw SpeechAPIError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else { throw SpeechAPIError.http(http.statusCode) }
            guard http.mimeType?.hasPrefix("audio/") == true || http.mimeType == "application/octet-stream" else {
                throw SpeechAPIError.invalidResponse
            }
            // Raw mono PCM: 24 kHz, signed little-endian Int16. 200 ms per chunk.
            var chunk = Data()
            chunk.reserveCapacity(9_600)
            var total = 0
            for try await byte in bytes {
                try Task.checkCancellation()
                total += 1
                guard total <= 2_880_000 else { throw SpeechAPIError.emptyAudio } // 60 seconds
                chunk.append(byte)
                if chunk.count == 9_600 {
                    try await onChunk(chunk)
                    chunk.removeAll(keepingCapacity: true)
                }
            }
            try Task.checkCancellation()
            guard total > 0 else { throw SpeechAPIError.emptyAudio }
            guard total.isMultiple(of: 2) else { throw SpeechAPIError.invalidResponse }
            if !chunk.isEmpty { try await onChunk(chunk) }
        } onCancel: {
            bytes.task.cancel()
        }
    }

    private struct Body: Encodable {
        let model: String
        let input: String
        let voice: String
        let instructions: String
        let response_format: String
        let speed: Double
    }
}

/// Only fixed, app-authored wake/closing lines may be persisted. User speech and
/// generated conversation replies never enter this cache.
actor PreparedSpeechCache {
    static let shared = PreparedSpeechCache()
    private let directory: URL
    private let legacyDirectory: URL?
    private var migrationComplete = false

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MarvinPreparedSpeech", isDirectory: true)
        legacyDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MarvinPreparedSpeech", isDirectory: true)
    }

    init(directory: URL, legacyDirectory: URL? = nil) {
        self.directory = directory
        self.legacyDirectory = legacyDirectory
    }

    static var lines: [String] { ConversationInteraction.openings + ConversationInteraction.closings }

    func audio(for text: String, configuration: MarvinConfig) -> Data? {
        // Retry failed migrations on later access. Existing audio remains usable in
        // its old location if a temporary filesystem error prevents the move.
        try? migratePreparedLines()
        guard let url = try? location(for: text, configuration: configuration) else { return nil }
        if let data = readAudio(at: url) { return data }
        return legacyDirectory.flatMap { readAudio(at: $0.appendingPathComponent(url.lastPathComponent)) }
    }

    private func readAudio(at url: URL) -> Data? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= 2_880_000, size.isMultiple(of: 2),
              let data = try? Data(contentsOf: url) else { return nil }
        return data
    }

    func count(configuration: MarvinConfig) -> Int {
        Self.lines.filter { audio(for: $0, configuration: configuration) != nil }.count
    }

    func prepare(configuration: MarvinConfig, apiKey: String,
                 client: any SpeechAudioClient = OpenAISpeechClient(),
                 onProgress: @escaping @Sendable (Int) async -> Void) async throws {
        try Task.checkCancellation()
        try migratePreparedLines()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Bound disk usage to one set of voice/delivery settings.
        let keep = Set(try Self.lines.map { try location(for: $0, configuration: configuration).lastPathComponent })
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            if !keep.contains(url.lastPathComponent) { try FileManager.default.removeItem(at: url) }
        }
        var completed = 0
        for text in Self.lines {
            try Task.checkCancellation()
            if audio(for: text, configuration: configuration) == nil {
                let collector = PreparedAudioCollector()
                try await client.stream(text, configuration: configuration, apiKey: apiKey) { chunk in
                    try await collector.append(chunk)
                }
                try Task.checkCancellation()
                let data = await collector.data
                try Task.checkCancellation()
                guard !data.isEmpty, data.count.isMultiple(of: 2) else { throw SpeechAPIError.invalidResponse }
                try data.write(to: location(for: text, configuration: configuration), options: .atomic)
            }
            completed += 1
            await onProgress(completed)
        }
    }

    func clear() throws {
        // Remove legacy clips too, so a later launch cannot resurrect deleted audio.
        for folder in [legacyDirectory, directory].compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        }
        migrationComplete = true
    }

    private func migratePreparedLines() throws {
        guard !migrationComplete else { return }
        let files = FileManager.default
        guard let legacyDirectory, legacyDirectory != directory,
              files.fileExists(atPath: legacyDirectory.path) else {
            migrationComplete = true
            return
        }
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        for source in try files.contentsOfDirectory(at: legacyDirectory, includingPropertiesForKeys: nil) {
            guard source.pathExtension == "pcm", readAudio(at: source) != nil else { continue }
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            if readAudio(at: destination) == nil {
                // Atomic replacement preserves an existing usable destination on errors.
                try Data(contentsOf: source).write(to: destination, options: .atomic)
            }
            try files.removeItem(at: source)
        }
        try files.removeItem(at: legacyDirectory)
        migrationComplete = true
    }

    private func location(for text: String, configuration: MarvinConfig) throws -> URL {
        guard Self.lines.contains(text) else { throw SpeechAPIError.invalidResponse }
        // Canonical body includes model, voice, directions, speed, text and format.
        // Credentials never enter the identity or the saved files.
        let canonical = try OpenAISpeechClient.requestBody(text, configuration: configuration)
        let digest = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".pcm")
    }
}

private actor PreparedAudioCollector {
    var data = Data()
    func append(_ chunk: Data) throws {
        guard data.count + chunk.count <= 2_880_000 else { throw SpeechAPIError.emptyAudio }
        data.append(chunk)
    }
}
