import Foundation
import NaturalLanguage

/// Generates a structured summary (highlights + to-dos) from a transcript
/// entirely on-device using Apple's NaturalLanguage framework. No data leaves the device.
struct SummaryService {
    private static let maxHighlights = 5
    private static let maxTodos = 5

    // Phrases that suggest a to-do or commitment
    private static let actionTriggers = [
        "will ", "should ", "need to", "needs to", "have to", "going to",
        "action item", "follow up", "follow-up", "next step",
        "let's ", "let us ", "we'll ", "i'll ", "i will "
    ]

    // Verbs that signal a conclusion, decision, or notable event — higher scoring
    private static let conclusionVerbs: Set<String> = [
        "decided", "agreed", "confirmed", "approved", "rejected", "concluded",
        "determined", "resolved", "committed", "planned", "announced", "launched",
        "completed", "achieved", "proposed", "recommended", "suggested", "identified",
        "highlighted", "noted", "found", "discovered", "realized", "established",
        "signed", "released", "scheduled", "assigned", "defined", "created"
    ]

    // Stop words excluded from content scoring
    private static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "up", "about", "into", "is", "are", "was",
        "were", "be", "been", "have", "has", "had", "do", "does", "did", "will",
        "would", "could", "should", "may", "might", "can", "i", "we", "you",
        "he", "she", "they", "it", "this", "that", "these", "those", "there",
        "here", "just", "also", "so", "then", "than", "yeah", "yes", "no",
        "okay", "ok", "right", "well", "um", "uh", "hmm", "actually",
        "basically", "really", "very", "quite", "much", "more", "some", "all",
        "any", "our", "my", "your", "their", "its", "as", "not", "don't",
        "didn't", "isn't", "aren't", "wasn't", "weren't", "wouldn't", "couldn't",
        "thing", "things", "think", "know", "got", "get", "go", "going", "make",
        "said", "say", "says", "lot", "kind", "sort", "stuff", "want", "wants",
        "like", "because", "when", "where", "what", "who", "how", "if"
    ]

    // Speaker label pattern: "**You** (12:34:56)" or "**Speaker 2** (12:34:56)"
    private static let speakerPrefix = try? NSRegularExpression(
        pattern: #"^\*\*[^*]+\*\*\s*\(\d+:\d+:\d+\)\s*"#
    )

    // Inline filler patterns — removed before presenting a highlight
    private static let fillerPatterns: [NSRegularExpression] = [
        // Hedge phrases
        try! NSRegularExpression(pattern: #"\b(I mean|you know|kind of|sort of|I think|I believe|I guess|I suppose|I feel like),?\s*"#, options: .caseInsensitive),
        // Discourse markers used as fillers
        try! NSRegularExpression(pattern: #"\b(basically|actually|literally|honestly|frankly|clearly|obviously|simply|essentially|certainly|definitely|absolutely),?\s*"#, options: .caseInsensitive),
        // Spoken noise
        try! NSRegularExpression(pattern: #"\b(um+|uh+|hmm+|er+|ah+|like),?\s*"#, options: .caseInsensitive),
        // Leading sentence starters
        try! NSRegularExpression(pattern: #"^(So|Well|Yeah|Okay|Right|And|But|Also|Now)[,.]?\s+"#, options: .caseInsensitive),
        // Mid-sentence parenthetical filler: ", right," / ", you know,"
        try! NSRegularExpression(pattern: #",\s*(right|you know|I mean|like),?\s*"#, options: .caseInsensitive),
    ]

    // MARK: - Public API

    /// Generate a summary for a transcript. Returns the formatted markdown string.
    static func summarize(transcript: String) -> String {
        let sentences = splitSentences(transcript)
        guard !sentences.isEmpty else { return "- No content to summarize." }

        let highlights = extractHighlights(sentences: sentences, fullText: transcript)
        let todos = extractTodos(sentences: sentences)

        var output = "**Highlights**\n"
        output += highlights.isEmpty
            ? "- None identified.\n"
            : highlights.map { "- \($0)" }.joined(separator: "\n") + "\n"
        output += "\n**To-Dos**\n"
        output += todos.isEmpty
            ? "- None identified."
            : todos.map { "- \($0)" }.joined(separator: "\n")
        return output
    }

    // MARK: - Sentence splitting

    private static func splitSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let raw = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            let clean = stripSpeakerLabel(raw)
            let wordCount = clean.split(separator: " ").count
            if wordCount >= 6 { sentences.append(clean) }
            return true
        }
        return sentences
    }

    private static func stripSpeakerLabel(_ sentence: String) -> String {
        guard let re = speakerPrefix else { return sentence }
        let ns = sentence as NSString
        let range = NSRange(location: 0, length: ns.length)
        return re.stringByReplacingMatches(in: sentence, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Highlights

    private static func extractHighlights(sentences: [String], fullText: String) -> [String] {
        let docNouns = nounSet(from: fullText)

        let scored: [(sentence: String, score: Double)] = sentences.map { sentence in
            let words = tokenizeWords(sentence)
            guard !words.isEmpty else { return (sentence, 0) }

            let sentenceNouns = nounSet(from: sentence)
            let nounDensity = Double(sentenceNouns.count) / Double(words.count)
            let overlap = Double(sentenceNouns.intersection(docNouns).count)

            // Boost sentences that contain conclusion/decision verbs
            let lower = sentence.lowercased()
            let hasConclusion = conclusionVerbs.contains { lower.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }
            let conclusionBoost = hasConclusion ? 0.4 : 0.0

            // Mild length penalty: prefer 10–30 word sentences
            let wc = Double(words.count)
            let lengthScore = wc < 10 ? wc / 10.0 : wc > 30 ? 30.0 / wc : 1.0

            return (sentence, (nounDensity + overlap * 0.05 + conclusionBoost) * lengthScore)
        }

        let ranked = scored.sorted { $0.score > $1.score }
        var chosen: [String] = []
        var chosenWordSets: [Set<String>] = []

        for candidate in ranked {
            guard chosen.count < maxHighlights else { break }
            let words = Set(tokenizeWords(candidate.sentence))
            let isDuplicate = chosenWordSets.contains { existing in
                guard !existing.isEmpty else { return false }
                return Double(words.intersection(existing).count) / Double(existing.count) > 0.5
            }
            if !isDuplicate {
                let compressed = compress(candidate.sentence)
                if !compressed.isEmpty {
                    chosen.append(compressed)
                    chosenWordSets.append(words)
                }
            }
        }
        return chosen
    }

    // MARK: - To-Dos

    private static func extractTodos(sentences: [String]) -> [String] {
        var todos: [String] = []
        for sentence in sentences {
            let lower = sentence.lowercased()
            if actionTriggers.contains(where: { lower.contains($0) }) {
                todos.append(compress(sentence))
                if todos.count == maxTodos { break }
            }
        }
        return todos
    }

    // MARK: - Sentence compression

    /// Strip filler, collapse whitespace, trim to 20 words, polish punctuation.
    private static func compress(_ sentence: String) -> String {
        var s = sentence

        // Remove filler patterns
        for pattern in fillerPatterns {
            let ns = s as NSString
            s = pattern.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        }

        // Collapse multiple spaces and trim
        s = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove leading punctuation artifacts
        while let first = s.first, ",.;:".contains(first) {
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        // Capitalise first letter
        if let first = s.first {
            s = first.uppercased() + s.dropFirst()
        }

        // Trim to 20 words at a word boundary
        let words = s.split(separator: " ", omittingEmptySubsequences: true)
        if words.count > 20 {
            s = words.prefix(20).joined(separator: " ") + "…"
        }

        // Ensure ends with punctuation
        if let last = s.last, !".!?…".contains(last) {
            s += "."
        }

        return s
    }

    // MARK: - NLP helpers

    private static func nounSet(from text: String) -> Set<String> {
        var nouns: Set<String> = []

        let lexTagger = NLTagger(tagSchemes: [.lexicalClass])
        lexTagger.string = text
        lexTagger.enumerateTags(in: text.startIndex..<text.endIndex,
                                unit: .word,
                                scheme: .lexicalClass,
                                options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            if tag == .noun {
                let w = String(text[range]).lowercased()
                if w.count > 2 && !stopWords.contains(w) { nouns.insert(w) }
            }
            return true
        }

        let nerTagger = NLTagger(tagSchemes: [.nameType])
        nerTagger.string = text
        nerTagger.enumerateTags(in: text.startIndex..<text.endIndex,
                                unit: .word,
                                scheme: .nameType,
                                options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            if let tag, [NLTag.personalName, .placeName, .organizationName].contains(tag) {
                let w = String(text[range]).lowercased()
                if w.count > 1 { nouns.insert(w) }
            }
            return true
        }

        return nouns
    }

    private static func tokenizeWords(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var words: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let w = String(text[range]).lowercased()
            if !stopWords.contains(w) { words.append(w) }
            return true
        }
        return words
    }

    // MARK: - File parsing

    static func extractTranscript(from fileContent: String) -> String {
        guard let range = fileContent.range(of: "## Transcript\n") else { return fileContent }
        return String(fileContent[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
