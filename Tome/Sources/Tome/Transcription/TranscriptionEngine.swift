import AVFoundation
import CoreAudio
import FluidAudio
import Observation
import WhisperKit
import os

// Writes to /tmp/hushscribe.log
func diagLog(_ msg: String) {
    #if DEBUG
    let line = "\(Date()): \(msg)\n"
    let path = "/tmp/hushscribe.log"
    if let fh = FileHandle(forWritingAtPath: path) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
    #endif
}

enum ModelDownloadState {
    case needed
    case downloading
    case ready
}

/// Dual-stream mic + system audio transcription.
@Observable
@MainActor
final class TranscriptionEngine {
    private(set) var isRunning = false
    private(set) var isPaused = false
    private(set) var modelDownloadState: ModelDownloadState
    var assetStatus: String = "Ready"
    var lastError: String?

    private let systemCapture = SystemAudioCapture()
    private let micCapture = MicCapture()
    private let transcriptStore: TranscriptStore

    /// Individual audio levels for the split VU meter.
    var micAudioLevel: Float { micCapture.audioLevel }
    var sysAudioLevel: Float { systemCapture.audioLevel }

    /// Mute controls — silences the respective audio stream.
    var isMicMuted: Bool {
        get { micCapture.isMuted }
        set { micCapture.isMuted = newValue }
    }
    var isSysMuted: Bool {
        get { systemCapture.isMuted }
        set { systemCapture.isMuted = newValue }
    }

    /// Combined level used for silence detection.
    var audioLevel: Float { max(micCapture.audioLevel, systemCapture.audioLevel) }

    private var micTask: Task<Void, Never>?
    private var sysTask: Task<Void, Never>?
    /// Keeps the mic stream alive for the audio level meter when transcription isn't running.
    private var micKeepAliveTask: Task<Void, Never>?

    /// The selected transcription model. Update via setModel() between sessions.
    private(set) var selectedModel: TranscriptionModel = .parakeet

    /// Shared FluidAudio instances
    private var asrManager: AsrManager?
    private var micVadManager: VadManager?
    private var sysVadManager: VadManager?

    /// WhisperKit backend (loaded on demand when WhisperKit model is selected).
    private var whisperKitBackend: WhisperKitASRBackend?

    /// Apple Speech backend (loaded on demand).
    private var sfSpeechBackend: SFSpeechBackend?

    /// Tracks the resolved mic device ID currently in use.
    private var currentMicDeviceID: AudioDeviceID = 0

    /// Tracks whether user selected "System Default" (0) or a specific device.
    private var userSelectedDeviceID: AudioDeviceID = 0

    /// Listens for default input device changes at the OS level.
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?

    init(transcriptStore: TranscriptStore) {
        self.transcriptStore = transcriptStore
        let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)
        self.modelDownloadState = AsrModels.modelsExist(at: cacheDir, version: .v3) ? .ready : .needed
    }

    /// Download and cache models without starting a recording session.
    func downloadModels() async {
        guard modelDownloadState != .ready else { return }
        modelDownloadState = .downloading
        assetStatus = "Downloading multilingual model..."
        diagLog("[ENGINE] downloading models on demand...")

        // Step 1: Download files to disk. This is the only step that determines
        // whether models are "downloaded" — in-memory loading is a separate concern.
        do {
            try await AsrModels.download(version: .v3, progressHandler: { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch progress.phase {
                    case .listing:
                        self.assetStatus = "Listing model files..."
                    case .downloading:
                        // fractionCompleted spans 0→0.5 during the download phase
                        let pct = min(100, Int(progress.fractionCompleted * 200))
                        self.assetStatus = "Downloading model... \(pct)%"
                    case .compiling(let name):
                        self.assetStatus = name.isEmpty ? "Compiling models..." : "Compiling \(name)..."
                    }
                }
            })
        } catch {
            let msg = "Failed to download models: \(error.localizedDescription)"
            diagLog("[ENGINE] \(msg)")
            lastError = msg
            modelDownloadState = .needed
            assetStatus = "Ready"
            return
        }

        // Step 2: Load into memory so the user can start recording immediately.
        // If this fails, files are already on disk — mark ready and let start() retry.
        diagLog("[ENGINE] models downloaded; loading into memory...")
        do {
            let models = try await AsrModels.loadFromCache(version: .v3)
            assetStatus = "Initializing ASR..."
            let asr = AsrManager(config: .default)
            try await asr.loadModels(models)
            self.asrManager = asr
            assetStatus = "Loading VAD model..."
            let micVad = try await VadManager()
            self.micVadManager = micVad
            let sysVad = try await VadManager(config: VadConfig(defaultThreshold: 0.92))
            self.sysVadManager = sysVad
            diagLog("[ENGINE] models loaded into memory")
        } catch {
            diagLog("[ENGINE] in-memory load failed after download: \(error.localizedDescription)")
            // Don't surface as a hard error — files are on disk; start() will load them.
        }

        modelDownloadState = .ready
        assetStatus = "Ready"
        diagLog("[ENGINE] models downloaded and cached")
    }

    /// Switch the active model. Must be called while a session is not running.
    func setModel(_ model: TranscriptionModel) {
        guard !isRunning else { return }
        selectedModel = model
        // Clear backends that don't match the new model so they reload on next start().
        if !model.isWhisperKit { whisperKitBackend = nil }
        if !model.isAppleSpeech { sfSpeechBackend = nil }
        if model.isWhisperKit || model.isAppleSpeech { asrManager = nil }
    }

    func start(locale: Locale, inputDeviceID: AudioDeviceID = 0, appBundleID: String? = nil, sysVadThreshold: Double = 0.92) async {
        diagLog("[ENGINE-0] start() called, isRunning=\(isRunning)")
        guard !isRunning else { return }
        lastError = nil

        guard await ensureMicrophonePermission() else { return }

        isRunning = true
        isPaused = false

        // Load ASR backend and VAD managers based on selected model.
        let asrBackend: any ASRBackend
        if selectedModel.isWhisperKit {
            // WhisperKit path: load VAD first (independent of FluidAudio model bundle),
            // then load WhisperKit.
            if micVadManager == nil || sysVadManager == nil {
                assetStatus = "Loading VAD model..."
                diagLog("[ENGINE-1b] loading VAD model...")
                do {
                    let micVad = try await VadManager()
                    self.micVadManager = micVad
                    let sysVad = try await VadManager(config: VadConfig(defaultThreshold: Float(sysVadThreshold)))
                    self.sysVadManager = sysVad
                } catch {
                    let msg = "Failed to load VAD: \(error.localizedDescription)"
                    diagLog("[ENGINE-VAD-FAIL] \(msg)")
                    lastError = msg
                    assetStatus = "Ready"
                    isRunning = false
                    return
                }
            }
            if let existing = whisperKitBackend {
                asrBackend = existing
            } else {
                let modelID = selectedModel.whisperModelID!
                assetStatus = "Downloading \(selectedModel.displayName)..."
                diagLog("[ENGINE-WK] loading WhisperKit model \(modelID)...")
                do {
                    let wk = try await WhisperKit(model: modelID)
                    let backend = WhisperKitASRBackend(wk)
                    self.whisperKitBackend = backend
                    asrBackend = backend
                } catch {
                    let msg = "Failed to load WhisperKit: \(error.localizedDescription)"
                    diagLog("[ENGINE-WK-FAIL] \(msg)")
                    lastError = msg
                    assetStatus = "Ready"
                    isRunning = false
                    return
                }
            }
        } else if selectedModel.isAppleSpeech {
            // Apple Speech path: request authorization, load VAD independently, then init recognizer.
            let authorized = await SFSpeechBackend.requestAuthorization()
            guard authorized else {
                lastError = "Speech recognition permission denied. Enable it in System Settings > Privacy & Security > Speech Recognition."
                assetStatus = "Ready"
                isRunning = false
                return
            }
            if micVadManager == nil || sysVadManager == nil {
                assetStatus = "Loading VAD model..."
                diagLog("[ENGINE-1b] loading VAD model...")
                do {
                    let micVad = try await VadManager()
                    self.micVadManager = micVad
                    let sysVad = try await VadManager(config: VadConfig(defaultThreshold: Float(sysVadThreshold)))
                    self.sysVadManager = sysVad
                } catch {
                    let msg = "Failed to load VAD: \(error.localizedDescription)"
                    diagLog("[ENGINE-VAD-FAIL] \(msg)")
                    lastError = msg
                    assetStatus = "Ready"
                    isRunning = false
                    return
                }
            }
            if let existing = sfSpeechBackend {
                asrBackend = existing
            } else {
                diagLog("[ENGINE-SF] initializing Apple Speech recognizer...")
                do {
                    let backend = try SFSpeechBackend(locale: locale)
                    self.sfSpeechBackend = backend
                    asrBackend = backend
                } catch {
                    let msg = "Failed to initialize Apple Speech: \(error.localizedDescription)"
                    diagLog("[ENGINE-SF-FAIL] \(msg)")
                    lastError = msg
                    assetStatus = "Ready"
                    isRunning = false
                    return
                }
            }
        } else {
            // Parakeet path: preserve the original loading order — ASR first, then VAD.
            // VadManager depends on the FluidAudio model bundle being available.
            if asrManager == nil || micVadManager == nil || sysVadManager == nil {
                guard modelDownloadState == .ready else {
                    lastError = "Models not downloaded. Please download the model first."
                    assetStatus = "Ready"
                    isRunning = false
                    return
                }
                assetStatus = "Loading models..."
                diagLog("[ENGINE-1] loading FluidAudio ASR models from cache...")
                do {
                    let models = try await AsrModels.downloadAndLoad(version: .v3)
                    assetStatus = "Initializing ASR..."
                    let asr = AsrManager(config: .default)
                    try await asr.loadModels(models)
                    self.asrManager = asr

                    assetStatus = "Loading VAD model..."
                    diagLog("[ENGINE-1b] loading VAD model...")
                    let micVad = try await VadManager()
                    self.micVadManager = micVad
                    let sysVad = try await VadManager(config: VadConfig(defaultThreshold: Float(sysVadThreshold)))
                    self.sysVadManager = sysVad

                    assetStatus = "Models ready"
                    diagLog("[ENGINE-2] FluidAudio models loaded from cache")
                } catch {
                    let msg = "Failed to load models: \(error.localizedDescription)"
                    diagLog("[ENGINE-2-FAIL] \(msg)")
                    lastError = msg
                    assetStatus = "Ready"
                    isRunning = false
                    return
                }
            }
            guard let asr = asrManager else { return }
            asrBackend = FluidAudioASRBackend(manager: asr)
        }

        guard let micVadManager, let sysVadManager else { return }

        // 2. Start mic capture
        userSelectedDeviceID = inputDeviceID
        let targetMicID = inputDeviceID > 0 ? inputDeviceID : MicCapture.defaultInputDeviceID()
        currentMicDeviceID = targetMicID ?? 0
        diagLog("[ENGINE-3] starting mic capture, targetMicID=\(String(describing: targetMicID))")
        let micStream = micCapture.bufferStream(deviceID: targetMicID)

        // 3. Start system audio capture
        diagLog("[ENGINE-4] starting system audio capture...")
        let sysStreams: SystemAudioCapture.CaptureStreams?
        do {
            sysStreams = try await systemCapture.bufferStream(appBundleID: appBundleID)
            diagLog("[ENGINE-5] system audio capture started OK")
        } catch {
            let msg = "Failed to start system audio: \(error.localizedDescription)"
            diagLog("[ENGINE-5-FAIL] \(msg)")
            lastError = msg
            sysStreams = nil
        }

        // 4. Start mic transcription
        let store = transcriptStore
        let micTranscriber = StreamingTranscriber(
            asrBackend: asrBackend,
            vadManager: micVadManager,
            speaker: .you,
            audioSource: .microphone,
            onPartial: { text in
                Task { @MainActor in store.volatileYouText = text }
            },
            onFinal: { text in
                Task { @MainActor in
                    store.volatileYouText = ""
                    store.append(Utterance(text: text, speaker: .you))
                }
            }
        )
        let reportMicError: @Sendable (String) -> Void = { [weak self] msg in
            Task { @MainActor in self?.lastError = msg }
        }
        micTask = Task.detached {
            let hadFatalError = await micTranscriber.run(stream: micStream)
            if hadFatalError {
                reportMicError("Mic transcription failed — restart session")
            }
        }

        // 5. Start system audio transcription
        if let sysStream = sysStreams?.systemAudio {
            let sysTranscriber = StreamingTranscriber(
                asrBackend: asrBackend,
                vadManager: sysVadManager,
                speaker: .them,
                audioSource: .system,
                onPartial: { text in
                    Task { @MainActor in store.volatileThemText = text }
                },
                onFinal: { text in
                    Task { @MainActor in
                        store.volatileThemText = ""
                        store.append(Utterance(text: text, speaker: .them))
                    }
                }
            )
            let reportSysError: @Sendable (String) -> Void = { [weak self] msg in
                Task { @MainActor in self?.lastError = msg }
            }
            sysTask = Task.detached {
                let hadFatalError = await sysTranscriber.run(stream: sysStream)
                if hadFatalError {
                    reportSysError("System audio transcription failed — restart session")
                }
            }
        }

        assetStatus = "Transcribing (\(selectedModel.displayName))"
        diagLog("[ENGINE-6] all transcription tasks started")

        // Install CoreAudio listener for default input device changes
        installDefaultDeviceListener()
    }

    /// Restart only the mic capture with a new device, keeping system audio and models intact.
    /// Pass the raw setting value (0 = system default, or a specific AudioDeviceID).
    func restartMic(inputDeviceID: AudioDeviceID) {
        guard isRunning, let micVadManager else { return }
        let backend: any ASRBackend
        if selectedModel.isWhisperKit, let wk = whisperKitBackend {
            backend = wk
        } else if selectedModel.isAppleSpeech, let sf = sfSpeechBackend {
            backend = sf
        } else if let asr = asrManager {
            backend = FluidAudioASRBackend(manager: asr)
        } else {
            return
        }

        // Only update user selection when explicitly changed (not from OS listener)
        if inputDeviceID != 0 || userSelectedDeviceID != 0 {
            userSelectedDeviceID = inputDeviceID
        }
        let targetMicID = inputDeviceID > 0 ? inputDeviceID : MicCapture.defaultInputDeviceID() ?? 0
        guard targetMicID != currentMicDeviceID else {
            diagLog("[ENGINE-MIC-SWAP] same device \(targetMicID), skipping")
            return
        }

        diagLog("[ENGINE-MIC-SWAP] switching mic from \(currentMicDeviceID) to \(targetMicID)")

        // Tear down old mic
        micTask?.cancel()
        micTask = nil
        micCapture.stop()

        currentMicDeviceID = targetMicID

        // Start new mic stream
        let micStream = micCapture.bufferStream(deviceID: targetMicID)
        let store = transcriptStore
        let micTranscriber = StreamingTranscriber(
            asrBackend: backend,
            vadManager: micVadManager,
            speaker: .you,
            audioSource: .microphone,
            onPartial: { text in
                Task { @MainActor in store.volatileYouText = text }
            },
            onFinal: { text in
                Task { @MainActor in
                    store.volatileYouText = ""
                    store.append(Utterance(text: text, speaker: .you))
                }
            }
        )
        let reportMicError: @Sendable (String) -> Void = { [weak self] msg in
            Task { @MainActor in self?.lastError = msg }
        }
        micTask = Task.detached {
            let hadFatalError = await micTranscriber.run(stream: micStream)
            if hadFatalError {
                reportMicError("Mic transcription failed — restart session")
            }
        }

        diagLog("[ENGINE-MIC-SWAP] mic restarted on device \(targetMicID)")
    }

    // MARK: - Default Device Listener

    private func installDefaultDeviceListener() {
        guard defaultDeviceListenerBlock == nil else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isRunning, self.userSelectedDeviceID == 0 else { return }
                // User has "System Default" selected — follow the OS default
                self.restartMic(inputDeviceID: 0)
            }
        }
        defaultDeviceListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func removeDefaultDeviceListener() {
        guard let block = defaultDeviceListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        defaultDeviceListenerBlock = nil
    }

    private func ensureMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                lastError = "Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone."
                assetStatus = "Ready"
            }
            return granted
        case .denied, .restricted:
            lastError = "Microphone access is disabled. Enable it in System Settings > Privacy & Security > Microphone."
            assetStatus = "Ready"
            return false
        @unknown default:
            lastError = "Unable to verify microphone permission."
            assetStatus = "Ready"
            return false
        }
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        micCapture.pause()
        systemCapture.pause()
        isPaused = true
        assetStatus = "Paused"
        diagLog("[ENGINE] paused")
    }

    func resume() {
        guard isRunning, isPaused else { return }
        do {
            try micCapture.resume()
        } catch {
            lastError = "Failed to resume mic: \(error.localizedDescription)"
            diagLog("[ENGINE] resume mic failed: \(error)")
        }
        systemCapture.resume()
        isPaused = false
        assetStatus = "Transcribing (\(selectedModel.displayName))"
        diagLog("[ENGINE] resumed")
    }

    func stop() async {
        lastError = nil
        removeDefaultDeviceListener()
        micTask?.cancel()
        sysTask?.cancel()
        micKeepAliveTask?.cancel()
        micTask = nil
        sysTask = nil
        micKeepAliveTask = nil
        await systemCapture.stop()
        micCapture.stop()
        currentMicDeviceID = 0
        isRunning = false
        assetStatus = "Ready"
    }

    /// Run offline diarization on the buffered system audio.
    /// Returns speaker segments (speakerId, startTime, endTime) or nil if no audio was buffered.
    nonisolated func runPostSessionDiarization() async -> [(speakerId: String, startTime: Float, endTime: Float)]? {
        guard let bufferURL = systemCapture.bufferFilePath,
              FileManager.default.fileExists(atPath: bufferURL.path) else {
            diagLog("[DIARIZE] No buffered system audio file found")
            return nil
        }

        diagLog("[DIARIZE] Starting post-session diarization on \(bufferURL.lastPathComponent)")

        do {
            let diarizer = OfflineDiarizerManager()

            diagLog("[DIARIZE] Preparing diarization models...")
            try await diarizer.prepareModels()

            diagLog("[DIARIZE] Processing audio...")
            let result = try await diarizer.process(bufferURL)

            let segments = result.segments.map { seg in
                (speakerId: seg.speakerId, startTime: seg.startTimeSeconds, endTime: seg.endTimeSeconds)
            }
            diagLog("[DIARIZE] Found \(segments.count) segments, \(Set(segments.map(\.speakerId)).count) speakers")

            systemCapture.cleanupBufferFile()
            return segments
        } catch {
            diagLog("[DIARIZE] Failed: \(error.localizedDescription)")
            systemCapture.cleanupBufferFile()
            return nil
        }
    }
}
