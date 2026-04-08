import FluidAudio

/// Abstraction over ASR engines (FluidAudio / WhisperKit / Apple Speech).
protocol ASRBackend: Sendable {
    func transcribe(_ samples: [Float], source: AudioSource, onPartial: (@Sendable (String) -> Void)?) async throws -> String
}

/// Wraps FluidAudio's AsrManager.
struct FluidAudioASRBackend: ASRBackend {
    let manager: AsrManager

    func transcribe(_ samples: [Float], source: AudioSource, onPartial: (@Sendable (String) -> Void)?) async throws -> String {
        let result = try await manager.transcribe(samples, source: source)
        return result.text
    }
}
