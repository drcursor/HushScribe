@preconcurrency import AVFoundation
import FluidAudio
import os

// VAD + ASR pipeline
final class StreamingTranscriber: @unchecked Sendable {
    private let asrBackend: any ASRBackend
    private let vadManager: VadManager
    private let speaker: Speaker
    private let audioSource: AudioSource
    private let onSpeechStart: (@Sendable () -> Void)?
    private let onPartial: @Sendable (String) -> Void
    private let onFinal: @Sendable (String) -> Void
    private let log = Logger(subsystem: "com.drcursor.hushscribe", category: "StreamingTranscriber")

    /// Resampler from source format to 16kHz mono Float32.
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    init(
        asrBackend: any ASRBackend,
        vadManager: VadManager,
        speaker: Speaker,
        audioSource: AudioSource = .microphone,
        onSpeechStart: (@Sendable () -> Void)? = nil,
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String) -> Void
    ) {
        self.asrBackend = asrBackend
        self.vadManager = vadManager
        self.speaker = speaker
        self.audioSource = audioSource
        self.onSpeechStart = onSpeechStart
        self.onPartial = onPartial
        self.onFinal = onFinal
    }

    /// Silero VAD expects chunks of 4096 samples (256ms at 16kHz).
    private static let vadChunkSize = 4096
    // Continuous speech used to be flushed every 6 s at a fixed sample count. That cut words
    // in half and started each piece without context, so words at the joins were lost or
    // replaced by invented ones.
    /// During continuous speech, transcribe after at most ~14 s (one recogniser window)...
    private static let maxSegment = 224_000
    /// ...cutting at the quietest moment of the last 4 s, so the cut falls between words.
    private static let splitSearch = 64_000
    /// Audio kept from just before the detector reports speech (it reports late).
    private static let preRoll = 8_192

    /// Index at which to cut `samples`: the centre of the quietest 100 ms in its last 4 s.
    static func quietestSplit(_ samples: [Float]) -> Int {
        let win = 1_600, hop = 800
        let start = max(win, samples.count - splitSearch)
        var best = samples.count, bestEnergy = Float.greatestFiniteMagnitude
        var i = start
        while i + win <= samples.count - win {
            var e: Float = 0
            for j in i..<(i + win) { e += samples[j] * samples[j] }
            if e < bestEnergy { bestEnergy = e; best = i + win / 2 }
            i += hop
        }
        return best
    }

    /// Main loop: reads audio buffers, runs VAD, transcribes speech segments.
    /// - Parameter offsetTracker: optional tracker updated with total 16 kHz samples consumed,
    ///   used during file transcription to compute file-relative utterance timestamps.
    /// Returns `true` if the loop exited due to fatal (repeated) errors.
    @discardableResult
    func run(stream: AsyncStream<AVAudioPCMBuffer>, offsetTracker: FileOffsetTracker? = nil) async -> Bool {
        var vadState = await vadManager.makeStreamState()
        var speechSamples: [Float] = []
        var vadBuffer: [Float] = []
        var isSpeaking = false
        var recent: [Float] = []        // the last moments of non-speech audio (pre-roll)
        var bufferCount = 0
        var consecutiveErrors = 0
        var totalVADSamples = 0

        outerLoop: for await buffer in stream {
            bufferCount += 1
            if bufferCount <= 3 {
                let fmt = buffer.format
                diagLog("[\(speaker.rawValue)] buffer #\(bufferCount): frames=\(buffer.frameLength) sr=\(fmt.sampleRate) ch=\(fmt.channelCount) interleaved=\(fmt.isInterleaved) common=\(fmt.commonFormat.rawValue)")
            }

            guard let samples = extractSamples(buffer) else { continue }

            if bufferCount <= 3 {
                let maxVal = samples.max() ?? 0
                diagLog("[\(speaker.rawValue)] samples: count=\(samples.count) max=\(maxVal)")
            }

            vadBuffer.append(contentsOf: samples)

            while vadBuffer.count >= Self.vadChunkSize {
                let chunk = Array(vadBuffer.prefix(Self.vadChunkSize))
                vadBuffer.removeFirst(Self.vadChunkSize)
                totalVADSamples += Self.vadChunkSize
                offsetTracker?.set(totalVADSamples)

                do {
                    let result = try await vadManager.processStreamingChunk(
                        chunk,
                        state: vadState,
                        config: .default,
                        returnSeconds: true,
                        timeResolution: 2
                    )
                    vadState = result.state
                    consecutiveErrors = 0

                    if let event = result.event {
                        switch event.kind {
                        case .speechStart:
                            isSpeaking = true
                            speechSamples = recent      // keep the onset the detector was late for
                            recent.removeAll(keepingCapacity: true)
                            onSpeechStart?()
                            diagLog("[\(self.speaker.rawValue)] speech start")

                        case .speechEnd:
                            isSpeaking = false
                            diagLog("[\(self.speaker.rawValue)] speech end, samples=\(speechSamples.count)")
                            if speechSamples.count > 8000 {
                                let segment = speechSamples
                                speechSamples.removeAll(keepingCapacity: true)
                                if await !transcribeSegment(segment) {
                                    consecutiveErrors += 1
                                    if consecutiveErrors > 10 { break outerLoop }
                                } else {
                                    consecutiveErrors = 0
                                }
                            } else {
                                speechSamples.removeAll(keepingCapacity: true)
                            }
                        }
                    }

                    if !isSpeaking {
                        recent.append(contentsOf: chunk)
                        if recent.count > Self.preRoll { recent.removeFirst(recent.count - Self.preRoll) }
                    }
                    if isSpeaking {
                        speechSamples.append(contentsOf: chunk)

                        // Long unbroken speech: transcribe up to the quietest recent moment and
                        // carry the rest into the next piece, so no audio is dropped.
                        if speechSamples.count >= Self.maxSegment {
                            let cut = Self.quietestSplit(speechSamples)
                            let segment = Array(speechSamples[..<cut])
                            speechSamples = Array(speechSamples[cut...])
                            if await !transcribeSegment(segment) {
                                consecutiveErrors += 1
                                if consecutiveErrors > 10 { break outerLoop }
                            } else {
                                consecutiveErrors = 0
                            }
                        }
                    }
                } catch {
                    log.error("VAD error: \(error.localizedDescription)")
                    consecutiveErrors += 1
                    if consecutiveErrors > 10 { break outerLoop }
                }
            }
        }

        if speechSamples.count > 8000 {
            _ = await transcribeSegment(speechSamples)
        }

        return consecutiveErrors > 10
    }

    /// Returns `true` on success, `false` on ASR error.
    private func transcribeSegment(_ samples: [Float]) async -> Bool {
        do {
            let text = try await asrBackend.transcribe(samples, source: audioSource, onPartial: onPartial)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return true }
            log.info("[\(self.speaker.rawValue)] transcribed: \(trimmed.prefix(80))")
            onFinal(trimmed)
            return true
        } catch {
            log.error("ASR error: \(error.localizedDescription)")
            return false
        }
    }

    /// Extract [Float] samples from an AVAudioPCMBuffer, resampling if needed.
    private func extractSamples(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let sourceFormat = buffer.format
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        // Fast path: already Float32 at 16kHz (common for system audio from ScreenCaptureKit)
        if sourceFormat.commonFormat == .pcmFormatFloat32 && sourceFormat.sampleRate == 16000 {
            guard let channelData = buffer.floatChannelData else { return nil }
            if sourceFormat.channelCount == 1 {
                // Mono — direct copy
                return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            } else {
                // Multi-channel — take first channel only
                return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            }
        }

        // Slow path: need to resample via AVAudioConverter
        if converter == nil || converter?.inputFormat != sourceFormat {
            converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outputFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard outputFrames > 0 else { return nil }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrames
        ) else { return nil }

        var error: NSError?
        final class ConsumedFlag: @unchecked Sendable { var value = false }
        let consumed = ConsumedFlag()
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed.value {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed.value = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            log.error("Resample error: \(error.localizedDescription)")
            return nil
        }

        guard let channelData = outputBuffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(outputBuffer.frameLength)
        ))
    }
}
