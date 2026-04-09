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

    // Words that are too generic or noisy to appear as topic labels in highlights
    private static let synthesisNoiseWords: Set<String> = [
        // Contractions NLTokenizer may leave whole
        "i'll", "i've", "i'm", "i'd", "we'll", "we've", "we're", "we'd",
        "you'll", "you've", "you're", "you'd", "they'll", "they've", "they're",
        "it's", "that's", "there's", "let's",
        // Generic gerunds / abstract verbs
        "getting", "going", "having", "being", "doing", "making", "looking",
        "saying", "talking", "thinking", "trying", "putting", "taking",
        "coming", "using", "working", "sharing", "showing",
        // Generic nouns that add no topic value
        "something", "anything", "everything", "nothing",
        "someone", "anyone", "everyone",
        "number", "kind", "sort", "type", "stuff",
        "share", "look", "care", "need", "want", "show", "tell",
    ]

    // Speaker label pattern: "**You** (12:34:56)" or "**Speaker 2** (12:34:56)"
    private static let speakerPrefix = try? NSRegularExpression(
        pattern: #"^\*\*[^*]+\*\*\s*\(\d+:\d+:\d+\)\s*"#
    )
    private static let speakerHeaderRe = try? NSRegularExpression(
        pattern: #"^\*\*([^*]+)\*\*\s*\(\d+:\d+:\d+\)"#
    )

    // First-person → third-person substitutions for to-do paraphrase
    private static let firstPersonSubs: [(NSRegularExpression, String)] = [
        (try! NSRegularExpression(pattern: #"^I(?:'m going| am going) to\s+"#, options: .caseInsensitive), "Will "),
        (try! NSRegularExpression(pattern: #"^I(?:'ll| will)\s+"#,             options: .caseInsensitive), "Will "),
        (try! NSRegularExpression(pattern: #"^I want to\s+"#,                   options: .caseInsensitive), "Wants to "),
        (try! NSRegularExpression(pattern: #"^I need to\s+"#,                   options: .caseInsensitive), "Needs to "),
        (try! NSRegularExpression(pattern: #"^I should\s+"#,                    options: .caseInsensitive), "Should "),
        (try! NSRegularExpression(pattern: #"^I have to\s+"#,                   options: .caseInsensitive), "Has to "),
        (try! NSRegularExpression(pattern: #"^We(?:'re going| are going) to\s+"#, options: .caseInsensitive), "Will "),
        (try! NSRegularExpression(pattern: #"^We(?:'ll| will)\s+"#,             options: .caseInsensitive), "Will "),
        (try! NSRegularExpression(pattern: #"^We should\s+"#,                   options: .caseInsensitive), "Should "),
        (try! NSRegularExpression(pattern: #"^We need to\s+"#,                  options: .caseInsensitive), "Need to "),
        (try! NSRegularExpression(pattern: #"^We have to\s+"#,                  options: .caseInsensitive), "Have to "),
    ]

    // Inline filler patterns — removed before presenting a highlight or to-do
    private static let fillerPatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"\b(I mean|you know|kind of|sort of|I think|I believe|I guess|I suppose|I feel like),?\s*"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"\b(basically|actually|literally|honestly|frankly|clearly|obviously|simply|essentially|certainly|definitely|absolutely),?\s*"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"\b(um+|uh+|hmm+|er+|ah+|like),?\s*"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"^(So|Well|Yeah|Okay|Right|And|But|Also|Now)[,.]?\s+"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #",\s*(right|you know|I mean|like),?\s*"#, options: .caseInsensitive),
    ]

    // MARK: - Public API

    /// Generate a summary for a transcript. Returns the formatted markdown string.
    static func summarize(transcript: String) -> String {
        let pairs = splitSentencesWithSpeakers(transcript)
        guard !pairs.isEmpty else { return "- No content to summarize." }
        let sentences = pairs.map { $0.sentence }

        let highlights = extractHighlights(sentences: sentences, fullText: transcript)
        let todos = extractTodosWithSpeakers(pairs: pairs)

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

    /// Splits the transcript into `(speaker, sentence)` pairs by parsing utterance blocks.
    private static func splitSentencesWithSpeakers(_ text: String) -> [(speaker: String, sentence: String)] {
        let blocks = text.components(separatedBy: "\n\n")
        var result: [(speaker: String, sentence: String)] = []

        for block in blocks {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            var speaker = "Unknown"
            var body = trimmed

            if let re = speakerHeaderRe {
                let ns = trimmed as NSString
                if let match = re.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
                   let speakerRange = Range(match.range(at: 1), in: trimmed) {
                    speaker = String(trimmed[speakerRange])
                    if let newline = trimmed.firstIndex(of: "\n") {
                        body = String(trimmed[trimmed.index(after: newline)...])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        body = ""
                    }
                }
            }

            guard !body.isEmpty else { continue }

            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = body
            tokenizer.enumerateTokens(in: body.startIndex..<body.endIndex) { range, _ in
                let s = String(body[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if s.split(separator: " ").count >= 6 {
                    result.append((speaker: speaker, sentence: s))
                }
                return true
            }
        }
        return result
    }

    private static func stripSpeakerLabel(_ sentence: String) -> String {
        guard let re = speakerPrefix else { return sentence }
        let ns = sentence as NSString
        return re.stringByReplacingMatches(in: sentence, range: NSRange(location: 0, length: ns.length), withTemplate: "")
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
            let lower = sentence.lowercased()
            let hasConclusion = conclusionVerbs.contains { lower.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }
            let conclusionBoost = hasConclusion ? 0.4 : 0.0
            let wc = Double(words.count)
            let lengthScore = wc < 10 ? wc / 10.0 : wc > 30 ? 30.0 / wc : 1.0
            return (sentence, (nounDensity + overlap * 0.05 + conclusionBoost) * lengthScore)
        }

        let topCandidates = scored
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(maxHighlights * 4)
            .map { $0.sentence }

        // Cluster by shared noun overlap so each highlight covers a distinct topic
        var clusters: [[String]] = []
        for sentence in topCandidates {
            let words = Set(tokenizeWords(sentence))
            var placed = false
            for i in 0..<clusters.count {
                let clusterWords = Set(clusters[i].flatMap { tokenizeWords($0) })
                let overlap = Double(words.intersection(clusterWords).count) / Double(max(words.count, 1))
                if overlap > 0.25 {
                    clusters[i].append(sentence)
                    placed = true
                    break
                }
            }
            if !placed { clusters.append([sentence]) }
        }

        // Synthesise one headline per cluster; deduplicate
        var highlights: [String] = []
        var seenTopics: Set<String> = []
        for cluster in clusters.prefix(maxHighlights) {
            let h = synthesizeHighlight(from: cluster)
            guard !h.isEmpty else { continue }
            let key = h.lowercased().prefix(30).trimmingCharacters(in: .whitespaces)
            guard !seenTopics.contains(key) else { continue }
            seenTopics.insert(key)
            highlights.append(h)
        }
        return highlights
    }

    /// Synthesises a short, third-person headline from a cluster of related sentences.
    /// Uses only true NL nouns and named entities — never quotes the transcript verbatim.
    private static func synthesizeHighlight(from sentences: [String]) -> String {
        guard !sentences.isEmpty else { return "" }

        var entityFreq: [String: Int] = [:]
        var nounFreq: [String: Int] = [:]
        var conclusionVerb: String? = nil

        for sentence in sentences {
            let lower = sentence.lowercased()
            if conclusionVerb == nil {
                conclusionVerb = conclusionVerbs.first {
                    lower.range(of: "\\b\($0)\\b", options: .regularExpression) != nil
                }
            }

            // Named entities (people, organisations, places)
            let nerTagger = NLTagger(tagSchemes: [.nameType])
            nerTagger.string = sentence
            nerTagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex,
                                    unit: .word, scheme: .nameType,
                                    options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
                if let tag, [NLTag.personalName, .placeName, .organizationName].contains(tag) {
                    let e = String(sentence[range])
                    if e.count > 1 { entityFreq[e, default: 0] += 1 }
                }
                return true
            }

            // True nouns only (lexicalClass = .noun); excludes verbs, pronouns, contractions
            let lexTagger = NLTagger(tagSchemes: [.lexicalClass])
            lexTagger.string = sentence
            lexTagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex,
                                    unit: .word, scheme: .lexicalClass,
                                    options: [.omitWhitespace, .omitPunctuation]) { tag, range in
                guard tag == .noun else { return true }
                let w = String(sentence[range]).lowercased()
                if w.count > 3 && !stopWords.contains(w) && !synthesisNoiseWords.contains(w) {
                    nounFreq[w, default: 0] += 1
                }
                return true
            }
        }

        // Prefer named entities; fall back to most-frequent true noun
        let topEntity = entityFreq.sorted { $0.value > $1.value }.first?.key
        let topNoun = nounFreq
            .sorted { $0.value > $1.value }
            .first
            .map { $0.key.prefix(1).uppercased() + $0.key.dropFirst() }

        let topic = topEntity ?? topNoun
        guard let t = topic else { return "" }

        if let verb = conclusionVerb {
            return "\(t) \(verb)."
        } else {
            return "Discussion about \(t)."
        }
    }

    // MARK: - To-Dos

    /// Returns attributed to-do bullets: "**Speaker:** Paraphrased action."
    private static func extractTodosWithSpeakers(pairs: [(speaker: String, sentence: String)]) -> [String] {
        var todos: [String] = []
        var seen: Set<String> = []

        for (speaker, sentence) in pairs {
            let lower = sentence.lowercased()
            guard actionTriggers.contains(where: { lower.contains($0) }) else { continue }

            let paraphrased = paraphraseTodo(sentence)
            let key = "\(speaker):\(paraphrased.prefix(24))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            todos.append("**\(speaker):** \(paraphrased)")
            if todos.count == maxTodos { break }
        }
        return todos
    }

    /// Converts a first-person action sentence to a clean, concise third-person action phrase.
    private static func paraphraseTodo(_ sentence: String) -> String {
        var s = sentence

        // Convert first-person opener to third-person
        for (re, replacement) in firstPersonSubs {
            let ns = s as NSString
            let range = NSRange(location: 0, length: ns.length)
            if re.firstMatch(in: s, range: range) != nil {
                s = re.stringByReplacingMatches(in: s, range: range, withTemplate: replacement)
                break
            }
        }

        // Remove filler
        for pattern in fillerPatterns {
            let ns = s as NSString
            s = pattern.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        }

        // Collapse whitespace and trim
        s = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove leading punctuation artifacts
        while let first = s.first, ",.;:".contains(first) {
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        // Truncate to 15 words — keeps it concise and avoids transcription noise at end of sentences
        let words = s.split(separator: " ", omittingEmptySubsequences: true)
        if words.count > 15 {
            s = words.prefix(15).joined(separator: " ") + "…"
        }

        if let first = s.first { s = first.uppercased() + s.dropFirst() }
        if let last = s.last, !".!?…".contains(last) { s += "." }

        return s
    }

    // MARK: - Sentence compression (used for fallback)

    private static func compress(_ sentence: String) -> String {
        var s = sentence
        for pattern in fillerPatterns {
            let ns = s as NSString
            s = pattern.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        }
        s = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = s.first, ",.;:".contains(first) {
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        if let first = s.first { s = first.uppercased() + s.dropFirst() }
        let words = s.split(separator: " ", omittingEmptySubsequences: true)
        if words.count > 20 { s = words.prefix(20).joined(separator: " ") + "…" }
        if let last = s.last, !".!?…".contains(last) { s += "." }
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
