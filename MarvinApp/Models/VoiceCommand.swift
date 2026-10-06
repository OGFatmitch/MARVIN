import Foundation

enum VoiceCommand: Equatable { case wake, sleep }

/// Strict phrases reduce accidental activation; recognition remains an auditioned
/// convenience, not speaker authentication or a dedicated low-power keyword model.
enum VoiceCommandMatcher {
    static func command(in text: String, active: Bool) -> VoiceCommand? {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if !active {
            guard words.count >= 2 else { return nil }
            for index in 0..<(words.count - 1) where words[index] == "hey" && words[index + 1] == "marvin" {
                let before = words[max(0, index - 3)..<index]
                if before.contains(where: { ["say", "said", "saying", "not", "don", "called"].contains($0) }) { continue }
                return .wake
            }
            return nil
        }
        var phrase = words
        if phrase.first == "please" { phrase.removeFirst() }
        if phrase.last == "please" { phrase.removeLast() }
        if phrase == ["marvin", "go", "to", "sleep"] || phrase == ["marvin", "go", "back", "to", "sleep"] {
            return .sleep
        }
        return nil
    }
}
