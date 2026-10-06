import Foundation

struct ConversationContext {
    private(set) var entries: [TranscriptEntry] = []

    mutating func appendExchange(user: String, assistant: String, maximumPairs: Int) {
        entries.append(TranscriptEntry(role: .user, content: user))
        entries.append(TranscriptEntry(role: .assistant, content: assistant))
        entries = Array(entries.suffix(max(0, maximumPairs) * 2))
    }

    mutating func clear() { entries.removeAll() }
}

enum ResponsePolicy {
    // Sentence-aware cap; avoids speaking an arbitrarily long model response.
    static func spokenText(_ text: String, maximumWords: Int) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        guard maximumWords > 0, !words.isEmpty else { return "" }
        guard words.count > maximumWords else { return words.joined(separator: " ") }
        let prefix = Array(words.prefix(maximumWords))
        if let lastSentence = prefix.lastIndex(where: { word in
            guard let last = word.last else { return false }
            return ".!?".contains(last)
        }) {
            return prefix[...lastSentence].joined(separator: " ")
        }
        return prefix.joined(separator: " ") + "…"
    }
}
