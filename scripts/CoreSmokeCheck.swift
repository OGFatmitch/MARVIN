// Command Line Tools-only checks; the broader XCTest suite remains in Tests/.
import Foundation

@main
struct CoreSmokeCheck {
    static func main() throws {
        var context = ConversationContext()
        for number in 1...6 {
            context.appendExchange(user: "Q\(number)", assistant: "A\(number)", maximumPairs: 4)
        }
        precondition(context.entries.count == 8 && context.entries.first?.content == "Q3")
        context.clear()
        precondition(context.entries.isEmpty)
        precondition(ResponsePolicy.spokenText("Containment failed. Mitch has explaining to do.", maximumWords: 5) == "Containment failed.")
        precondition(ResponsePolicy.spokenText("one two three four", maximumWords: 3) == "one two three…")
        let config = MarvinConfig()
        let request = try OpenAIService().makeRequest(transcript: "Who are you?", history: [],
                                                    configuration: config, apiKey: "test-placeholder")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        precondition(body["store"] as? Bool == false)
        precondition(body["previous_response_id"] == nil)
        precondition(request.timeoutInterval == 15)
        let fixture = Data(#"{"output":[{"type":"reasoning"},{"type":"message","content":[{"type":"output_text","text":"I am deployed."}]}]}"#.utf8)
        let response = try OpenAIService.parseResponse(fixture)
        precondition(response == "I am deployed.")
        do {
            _ = try OpenAIService.parseResponse(Data(#"{"output":[]}"#.utf8))
            preconditionFailure("Empty response was accepted")
        } catch LLMError.emptyResponse { }
        let roundTrip = try JSONDecoder().decode(MarvinConfig.self, from: JSONEncoder().encode(config))
        precondition(roundTrip == config)
        print("Core smoke checks passed: context, length cap, request privacy, response parsing, configuration round-trip.")
    }
}
