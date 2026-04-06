@preconcurrency import ScreenCaptureKit
@preconcurrency import AVFoundation
import CoreMedia
import os

final class SystemAudioCapture: NSObject, @unchecked Sendable, SCStreamDelegate, SCStreamOutput {
    private let _stream = OSAllocatedUnfairLock<SCStream?>(uncheckedState: nil)
    private let _sysContinuation = OSAllocatedUnfairLock<AsyncStream<AVAudioPCMBuffer>.Continuation?>(uncheckedState: nil)
    private let _micContinuation = OSAllocatedUnfairLock<AsyncStream<AVAudioPCMBuffer>.Continuation?>(uncheckedState: nil)
    private let _audioLevel = AudioLevel()
    private let _paused = OSAllocatedUnfairLock<Bool>(uncheckedState: false)
    private let _muted = OSAllocatedUnfairLock<Bool>(uncheckedState: false)

    var audioLevel: Float { _audioLevel.value }
    var isMuted: Bool {
        get { _muted.withLock { $0 } }
        set { _muted.withLock { $0 = newValue }; if newValue { _audioLevel.value = 0 } }
    }

    // Temp WAV for diarization
    private let _bufferFilePath = OSAllocatedUnfairLock<URL?>(uncheckedState: nil)
    var bufferFilePath: URL? { _bufferFilePath.withLock { $0 } }

    private let _audioFileWriter = OSAllocatedUnfairLock<AVAudioFile?>(uncheckedState: nil)

    struct CaptureStreams {
        let systemAudio: AsyncStream<AVAudioPCMBuffer>
    }

    /// Start capturing system audio. Pass a bundle ID to filter to a specific app.
    func bufferStream(appBundleID: String? = nil) async throws -> CaptureStreams {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        // Build content filter — per-app if possible, otherwise all system audio
        let filter: SCContentFilter
        if let bundleID = appBundleID,
           let matchedApp = content.applications.first(where: { $0.bundleIdentifier == bundleID }) {
            diagLog("[SYS-FILTER] Per-app filter: \(bundleID)")
            filter = SCContentFilter(display: display, including: [matchedApp], exceptingWindows: [])
        } else {
            if let bundleID = appBundleID {
                diagLog("[SYS-FILTER] App \(bundleID) not found in shareable content, falling back to all system audio")
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        // Set up audio buffer file for post-session diarization
        let bufferURL = FileManager.default.temporaryDirectory.appendingPathComponent("hushscribe_sys_audio_\(UUID().uuidString).wav")
        _bufferFilePath.withLock { $0 = bufferURL }
        _audioFileWriter.withLock { $0 = nil } // will be created on first audio callback

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.channelCount = 1
        config.sampleRate = 48000

        // Minimal video — we only want audio
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let scStream = SCStream(filter: filter, configuration: config, delegate: self)
        try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))

        let sysStream = AsyncStream<AVAudioPCMBuffer> { cont in
            self._sysContinuation.withLock { $0 = cont }
        }

        _stream.withLock { $0 = scStream }
        try await scStream.startCapture()

        return CaptureStreams(systemAudio: sysStream)
    }

    func pause() {
        _paused.withLock { $0 = true }
        _audioLevel.value = 0
    }

    func resume() {
        _paused.withLock { $0 = false }
    }

    func stop() async {
        try? await _stream.withLock { $0 }?.stopCapture()
        _stream.withLock { $0 = nil }
        _sysContinuation.withLock { $0?.finish(); $0 = nil }
        _audioFileWriter.withLock { $0 = nil } // closes the file
        _audioLevel.value = 0
    }

    /// Remove the buffered audio file after diarization is complete
    func cleanupBufferFile() {
        if let path = _bufferFilePath.withLock({ $0 }) {
            try? FileManager.default.removeItem(at: path)
        }
        _bufferFilePath.withLock { $0 = nil }
    }

    // MARK: - SCStreamOutput

    private let _sampleCount = OSAllocatedUnfairLock<Int>(uncheckedState: 0)

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard !_paused.withLock({ $0 }) else { return }
        guard !_muted.withLock({ $0 }) else { _audioLevel.value = 0; return }
        guard let formatDesc = sampleBuffer.formatDescription,
              var asbd = formatDesc.audioStreamBasicDescription else { return }

        guard let format = AVAudioFormat(streamDescription: &asbd) else { return }

        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frameCount > 0 else { return }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )
        guard status == noErr else { return }

        // Update audio level for visualizer
        let rms = Self.normalizedRMS(from: pcmBuffer)
        _audioLevel.value = min(rms * 25, 1.0)

        // Diagnostic: log raw system audio levels periodically
        let count = _sampleCount.withLock { val -> Int in val += 1; return val }
        if count <= 5 || count % 200 == 0 {
            diagLog("[SYS-RAW] #\(count) frames=\(frameCount) sr=\(asbd.mSampleRate) ch=\(asbd.mChannelsPerFrame) rms=\(rms)")
        }

        // Buffer audio to disk for post-session diarization
        let sampleRate = asbd.mSampleRate
        _audioFileWriter.withLock { writer in
            if writer == nil, let bufferPath = self._bufferFilePath.withLock({ $0 }) {
                let wavFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
                writer = try? AVAudioFile(forWriting: bufferPath, settings: wavFormat.settings)
            }
            try? writer?.write(from: pcmBuffer)
        }

        _ = _sysContinuation.withLock { $0?.yield(pcmBuffer) }
    }

    // MARK: - SCStreamDelegate

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        print("SystemAudioCapture: stream stopped with error: \(error)")
        _sysContinuation.withLock { $0?.finish(); $0 = nil }
    }

    private static func normalizedRMS(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameLength {
            let s = channelData[0][i]
            sum += s * s
        }
        return sqrt(sum / Float(frameLength))
    }

    enum CaptureError: Error {
        case noDisplay
    }
}
