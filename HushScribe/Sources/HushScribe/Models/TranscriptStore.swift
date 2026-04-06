import Foundation
import Observation

@Observable
@MainActor
final class TranscriptStore {
    private(set) var utterances: [Utterance] = []
    var volatileYouText: String = ""
    var volatileThemText: String = ""

    /// Timestamp of the most recent finalized utterance
    private(set) var lastUtteranceTimestamp: Date?

    func append(_ utterance: Utterance) {
        utterances.append(utterance)
        lastUtteranceTimestamp = utterance.timestamp
    }

    func clear() {
        utterances.removeAll()
        volatileYouText = ""
        volatileThemText = ""
        lastUtteranceTimestamp = nil
    }
}
