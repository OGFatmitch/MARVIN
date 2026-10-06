import Foundation

struct OpenAIService: LLMService {
    let session: URLSession
    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = MarvinConfig().requestTimeout
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        self.session = session ?? URLSession(configuration: configuration)
    }

    func makeRequest(transcript: String, history: [TranscriptEntry],
                     configuration: MarvinConfig, apiKey: String) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.missingKey
        }
        let config = configuration.validated()
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = config.requestTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let recent = history.suffix(config.maximumHistoryPairs * 2)
        let input = recent.map { Input(role: $0.role.rawValue, content: $0.content) }
            + [Input(role: "user", content: String(transcript.prefix(config.maximumTranscriptCharacters)))]
        request.httpBody = try JSONEncoder().encode(Body(
            model: config.model, instructions: MarvinPrompt.system(maximumWords: config.maximumResponseWords),
            input: input, store: false, max_output_tokens: 160))
        return request
    }

    func reply(to transcript: String, history: [TranscriptEntry],
               configuration: MarvinConfig, apiKey: String) async throws -> String {
        let request = try makeRequest(transcript: transcript, history: history,
                                      configuration: configuration, apiKey: apiKey)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw LLMError.http(response.statusCode) }
        let text = try Self.parseResponse(data)
        return ResponsePolicy.spokenText(text, maximumWords: configuration.validated().maximumResponseWords)
    }

    static func parseResponse(_ data: Data) throws -> String {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw LLMError.invalidResponse
        }
        let text = response.output.filter { $0.type == "message" }.flatMap { $0.content ?? [] }
            .filter { $0.type == "output_text" }.compactMap(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LLMError.emptyResponse }
        return text
    }

    private struct Input: Encodable { let role: String; let content: String }
    private struct Body: Encodable {
        let model: String
        let instructions: String
        let input: [Input]
        let store: Bool
        let max_output_tokens: Int
    }
    private struct Response: Decodable {
        let output: [Output]
        struct Output: Decodable {
            let type: String
            let content: [Content]?
        }
        struct Content: Decodable { let type: String; let text: String? }
    }
}
