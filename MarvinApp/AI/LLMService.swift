import Foundation

protocol LLMService {
    func reply(to transcript: String, history: [TranscriptEntry],
               configuration: MarvinConfig, apiKey: String) async throws -> String
}

enum LLMError: LocalizedError {
    case missingKey, http(Int), invalidResponse, emptyResponse
    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add your OpenAI API key in Settings."
        case .http(401): return "API key was rejected. Replace it in Settings."
        case .http(429): return "API quota or rate limit reached. Check your API account."
        case .http(let code): return "AI service returned HTTP \(code). Check the model and account access."
        case .invalidResponse: return "AI service returned an unreadable response."
        case .emptyResponse: return "AI service returned no spoken answer."
        }
    }
}
