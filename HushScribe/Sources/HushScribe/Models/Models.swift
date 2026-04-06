import Foundation

enum Speaker: String, Codable, Sendable {
    case you
    case them
}

struct Utterance: Identifiable, Codable, Sendable {
    let id: UUID
    let text: String
    let speaker: Speaker
    let timestamp: Date

    init(text: String, speaker: Speaker, timestamp: Date = .now) {
        self.id = UUID()
        self.text = text
        self.speaker = speaker
        self.timestamp = timestamp
    }
}

// MARK: - Session Record

/// Codable record for JSONL session persistence
struct SessionRecord: Codable {
    let speaker: Speaker
    let text: String
    let timestamp: Date

    init(speaker: Speaker, text: String, timestamp: Date) {
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
    }
}
