import AVFoundation
import FluidAudio
import Speech

enum SFSpeechBackendError: Error, LocalizedError {
    case notAuthorized
    case unavailable
    case noResult

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Speech recognition permission denied."
        case .unavailable: return "Apple Speech recognizer is not available for the selected language."
        case .noResult: return "Speech recognizer returned no result."
        }
    }
}

/// Wraps SFSpeechRecognizer for use as an ASR backend.
final class SFSpeechBackend: @unchecked Sendable, ASRBackend {
    private let recognizer: SFSpeechRecognizer

    init(locale: Locale) throws {
        guard let rec = SFSpeechRecognizer(locale: locale), rec.isAvailable else {
            throw SFSpeechBackendError.unavailable
        }
        self.recognizer = rec
    }

    /// Request Speech Recognition authorization. Returns true if granted.
    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func transcribe(_ samples: [Float], source: AudioSource, onPartial: (@Sendable (String) -> Void)?) async throws -> String {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw SFSpeechBackendError.noResult
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channelData = buffer.floatChannelData {
            channelData[0].update(from: samples, count: samples.count)
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = onPartial != nil
        request.append(buffer)
        request.endAudio()

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }
                if let error {
                    resumed = true
                    continuation.resume(throwing: error)
                } else if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        resumed = true
                        if text.isEmpty {
                            continuation.resume(throwing: SFSpeechBackendError.noResult)
                        } else {
                            continuation.resume(returning: text)
                        }
                    } else if !text.isEmpty {
                        onPartial?(text)
                    }
                }
            }
        }
    }
}
