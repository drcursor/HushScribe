import FluidAudio
@preconcurrency import WhisperKit

/// Wraps WhisperKit for use as an ASR backend.
final class WhisperKitASRBackend: @unchecked Sendable, ASRBackend {
    private let whisperKit: WhisperKit

    init(_ whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    func transcribe(_ samples: [Float], source: AudioSource) async throws -> String {
        let results = try await whisperKit.transcribe(audioArray: samples)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
