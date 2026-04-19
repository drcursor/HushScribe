@preconcurrency import AVFoundation
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

/// Tracks the number of 16 kHz audio samples consumed by a StreamingTranscriber.
/// Used during file transcription to compute file-relative utterance timestamps.
final class FileOffsetTracker: @unchecked Sendable {
    private var _samples: Int = 0
    private let lock = NSLock()

    /// Current audio position in seconds (samples / 16 000 Hz).
    var seconds: Double { lock.withLock { Double(_samples) / 16_000.0 } }

    func set(_ samples: Int) { lock.withLock { _samples = samples } }
}

/// Dual-stream mic + system audio transcription.
@Observable
@MainActor
final class TranscriptionEngine {
    private(set) var isRunning = false
    private(set) var isPaused = false
    private(set) var modelDownloadState: ModelDownloadState
    /// Set while a non-Parakeet model is being pre-downloaded from the Models tab.
    private(set) var downloadingModel: TranscriptionModel?
    var assetStatus: String = "Ready"
    var lastError: String?
    /// True while a partial transcript is being built (speech detected, not yet finalised).
    private(set) var isSpeechDetected: Bool = false

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
    private var fileTask: Task<Void, Never>?
    /// Source URL for the current file-transcription session (used by diarization).
    private(set) var fileTranscriptionURL: URL?
    /// Tracks 16 kHz samples consumed — lets diarization use only the processed portion on mid-stop.
    private var fileOffsetTracker: FileOffsetTracker?
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

    /// App bundle ID used when system audio capture was last started — needed for restarts.
    private var captureAppBundleID: String? = nil

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

    // MARK: - Per-model download/remove (used by Models settings tab)

    /// Returns true if a model's files are present on disk and ready to use.
    func isModelDownloaded(_ model: TranscriptionModel) -> Bool {
        switch model {
        case .parakeet:
            let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)
            return AsrModels.modelsExist(at: cacheDir, version: .v3)
        case .whisperBase, .whisperLargeV3:
            guard let modelID = model.whisperModelID else { return false }
            return FileManager.default.fileExists(atPath: Self.whisperCacheURL(for: modelID).path)
        case .appleSpeech:
            return true
        }
    }

    /// Pre-downloads a model without starting a session. No-op for Apple Speech.
    func downloadModel(_ model: TranscriptionModel) async {
        switch model {
        case .parakeet:
            await downloadModels()
        case .whisperBase, .whisperLargeV3:
            await preDownloadWhisperKit(model)
        case .appleSpeech:
            break
        }
    }

    /// Removes a downloaded model from disk. No-op if running or Apple Speech.
    func removeModel(_ model: TranscriptionModel) {
        guard !isRunning else { return }
        switch model {
        case .parakeet:
            let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)
            try? FileManager.default.removeItem(at: cacheDir)
            asrManager = nil
            micVadManager = nil
            sysVadManager = nil
            modelDownloadState = .needed
        case .whisperBase, .whisperLargeV3:
            guard let modelID = model.whisperModelID else { return }
            try? FileManager.default.removeItem(at: Self.whisperCacheURL(for: modelID))
            if selectedModel == model { whisperKitBackend = nil }
        case .appleSpeech:
            break
        }
    }

    private func preDownloadWhisperKit(_ model: TranscriptionModel) async {
        guard let modelID = model.whisperModelID, downloadingModel == nil else { return }
        downloadingModel = model
        assetStatus = "Downloading \(model.displayName)..."
        do {
            let wk = try await WhisperKit(model: modelID)
            if selectedModel == model {
                whisperKitBackend = WhisperKitASRBackend(wk)
            }
        } catch {
            lastError = "Failed to download \(model.displayName): \(error.localizedDescription)"
        }
        downloadingModel = nil
        assetStatus = "Ready"
    }

    private static func whisperCacheURL(for modelID: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml/\(modelID)")
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
        captureAppBundleID = appBundleID
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
            onSpeechStart: { [weak self] in
                Task { @MainActor in self?.isSpeechDetected = true }
            },
            onPartial: { text in
                Task { @MainActor in store.volatileYouText = text }
            },
            onFinal: { [weak self] text in
                Task { @MainActor in
                    store.volatileYouText = ""
                    store.append(Utterance(text: text, speaker: .you))
                    self?.isSpeechDetected = false
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
                onSpeechStart: { [weak self] in
                    Task { @MainActor in self?.isSpeechDetected = true }
                },
                onPartial: { text in
                    Task { @MainActor in store.volatileThemText = text }
                },
                onFinal: { [weak self] text in
                    Task { @MainActor in
                        store.volatileThemText = ""
                        store.append(Utterance(text: text, speaker: .them))
                        self?.isSpeechDetected = false
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

        // Reset capture pipelines shortly after start to flush any residual audio state.
        // Use Task.detached so TranscriptionEngine is not captured as the executor context,
        // avoiding a use-after-free if AttributeGraph reclaims the actor's memory mid-sleep.
        let startDeviceID = inputDeviceID
        Task.detached { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            await self?.resetCapture(inputDeviceID: startDeviceID)
        }

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
        let targetMicID: AudioDeviceID? = inputDeviceID > 0 ? inputDeviceID : MicCapture.defaultInputDeviceID()
        let resolvedTarget = targetMicID ?? 0
        guard resolvedTarget != currentMicDeviceID else {
            diagLog("[ENGINE-MIC-SWAP] same device \(resolvedTarget), skipping")
            return
        }

        diagLog("[ENGINE-MIC-SWAP] switching mic from \(currentMicDeviceID) to \(resolvedTarget)")

        // Tear down old mic (no engine.reset() — keeps AUHAL alive for device property change)
        micTask?.cancel()
        micTask = nil
        micCapture.stopForSwitch()

        currentMicDeviceID = resolvedTarget

        // Start new mic stream
        let micStream = micCapture.bufferStream(deviceID: targetMicID)
        let store = transcriptStore
        let micTranscriber = StreamingTranscriber(
            asrBackend: backend,
            vadManager: micVadManager,
            speaker: .you,
            audioSource: .microphone,
            onSpeechStart: { [weak self] in Task { @MainActor in self?.isSpeechDetected = true } },
            onPartial: { text in Task { @MainActor in store.volatileYouText = text } },
            onFinal: { [weak self] text in
                Task { @MainActor in
                    store.volatileYouText = ""
                    store.append(Utterance(text: text, speaker: .you))
                    self?.isSpeechDetected = false
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

        diagLog("[ENGINE-MIC-SWAP] mic restarted on device \(resolvedTarget)")
    }

    /// Force-restart both mic and system audio capture pipelines without stopping the session.
    /// Unlike restartMic, this bypasses the same-device guard and also tears down sys audio.
    func resetCapture(inputDeviceID: AudioDeviceID) async {
        guard isRunning else { return }
        diagLog("[ENGINE-RESET] full capture reset requested")
        lastError = nil

        let backend: any ASRBackend
        if selectedModel.isWhisperKit, let wk = whisperKitBackend {
            backend = wk
        } else if selectedModel.isAppleSpeech, let sf = sfSpeechBackend {
            backend = sf
        } else if let asr = asrManager {
            backend = FluidAudioASRBackend(manager: asr)
        } else {
            diagLog("[ENGINE-RESET] no backend available, aborting")
            return
        }

        guard let micVadManager, let sysVadManager else { return }

        // --- Mic ---
        userSelectedDeviceID = inputDeviceID
        let targetMicID: AudioDeviceID? = inputDeviceID > 0 ? inputDeviceID : MicCapture.defaultInputDeviceID()
        currentMicDeviceID = targetMicID ?? 0

        micTask?.cancel()
        micTask = nil
        micCapture.stopForSwitch()

        let micStream = micCapture.bufferStream(deviceID: targetMicID)
        let store = transcriptStore
        let micTranscriber = StreamingTranscriber(
            asrBackend: backend,
            vadManager: micVadManager,
            speaker: .you,
            audioSource: .microphone,
            onSpeechStart: { [weak self] in Task { @MainActor in self?.isSpeechDetected = true } },
            onPartial: { text in Task { @MainActor in store.volatileYouText = text } },
            onFinal: { [weak self] text in
                Task { @MainActor in
                    store.volatileYouText = ""
                    store.append(Utterance(text: text, speaker: .you))
                    self?.isSpeechDetected = false
                }
            }
        )
        let reportMicError: @Sendable (String) -> Void = { [weak self] msg in
            Task { @MainActor in self?.lastError = msg }
        }
        micTask = Task.detached {
            let hadFatalError = await micTranscriber.run(stream: micStream)
            if hadFatalError { reportMicError("Mic transcription failed — restart session") }
        }
        diagLog("[ENGINE-RESET] mic restarted on device \(currentMicDeviceID)")

        // --- System audio ---
        sysTask?.cancel()
        sysTask = nil
        await systemCapture.stop()

        let sysStreams: SystemAudioCapture.CaptureStreams?
        do {
            sysStreams = try await systemCapture.bufferStream(appBundleID: captureAppBundleID)
            diagLog("[ENGINE-RESET] system audio restarted")
        } catch {
            let msg = "System audio restart failed: \(error.localizedDescription)"
            diagLog("[ENGINE-RESET] \(msg)")
            lastError = msg
            sysStreams = nil
        }

        if let sysStream = sysStreams?.systemAudio {
            let sysTranscriber = StreamingTranscriber(
                asrBackend: backend,
                vadManager: sysVadManager,
                speaker: .them,
                audioSource: .system,
                onSpeechStart: { [weak self] in Task { @MainActor in self?.isSpeechDetected = true } },
                onPartial: { text in Task { @MainActor in store.volatileThemText = text } },
                onFinal: { [weak self] text in
                    Task { @MainActor in
                        store.volatileThemText = ""
                        store.append(Utterance(text: text, speaker: .them))
                        self?.isSpeechDetected = false
                    }
                }
            )
            let reportSysError: @Sendable (String) -> Void = { [weak self] msg in
                Task { @MainActor in self?.lastError = msg }
            }
            sysTask = Task.detached {
                let hadFatalError = await sysTranscriber.run(stream: sysStream)
                if hadFatalError { reportSysError("System audio transcription failed — restart session") }
            }
        }

        diagLog("[ENGINE-RESET] full capture reset complete")
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
        fileTask?.cancel()
        micKeepAliveTask?.cancel()
        micTask = nil
        sysTask = nil
        fileTask = nil
        micKeepAliveTask = nil
        // fileTranscriptionURL is NOT cleared here — runFileTranscriptionDiarization() reads it
        // after stop() returns, then clears it (mirrors how systemCapture.cleanupBufferFile() works).
        await systemCapture.stop()
        micCapture.stop()
        currentMicDeviceID = 0
        isRunning = false
        assetStatus = "Ready"
    }

    // MARK: - File Transcription

    /// Transcribe an audio or video file using the same VAD + ASR pipeline as live sessions.
    /// Posts `.hushscribeStopRecording` when processing completes so ContentView can finalize the session.
    func startFileTranscription(url: URL, locale: Locale) async {
        guard !isRunning else { return }
        lastError = nil
        isRunning = true
        isPaused = false

        // Load ASR backend — same logic as start()
        let asrBackend: any ASRBackend
        if selectedModel.isWhisperKit {
            if micVadManager == nil {
                assetStatus = "Loading VAD model..."
                do {
                    micVadManager = try await VadManager()
                } catch {
                    lastError = "Failed to load VAD: \(error.localizedDescription)"
                    assetStatus = "Ready"; isRunning = false; return
                }
            }
            if let existing = whisperKitBackend {
                asrBackend = existing
            } else {
                let modelID = selectedModel.whisperModelID!
                assetStatus = "Downloading \(selectedModel.displayName)..."
                do {
                    let wk = try await WhisperKit(model: modelID)
                    let backend = WhisperKitASRBackend(wk)
                    whisperKitBackend = backend
                    asrBackend = backend
                } catch {
                    lastError = "Failed to load WhisperKit: \(error.localizedDescription)"
                    assetStatus = "Ready"; isRunning = false; return
                }
            }
        } else if selectedModel.isAppleSpeech {
            let authorized = await SFSpeechBackend.requestAuthorization()
            guard authorized else {
                lastError = "Speech recognition permission denied."
                assetStatus = "Ready"; isRunning = false; return
            }
            if micVadManager == nil {
                assetStatus = "Loading VAD model..."
                do {
                    micVadManager = try await VadManager()
                } catch {
                    lastError = "Failed to load VAD: \(error.localizedDescription)"
                    assetStatus = "Ready"; isRunning = false; return
                }
            }
            if let existing = sfSpeechBackend {
                asrBackend = existing
            } else {
                do {
                    let backend = try SFSpeechBackend(locale: locale)
                    sfSpeechBackend = backend
                    asrBackend = backend
                } catch {
                    lastError = "Failed to initialize Apple Speech: \(error.localizedDescription)"
                    assetStatus = "Ready"; isRunning = false; return
                }
            }
        } else {
            // Parakeet
            if asrManager == nil || micVadManager == nil {
                guard modelDownloadState == .ready else {
                    lastError = "Models not downloaded."
                    assetStatus = "Ready"; isRunning = false; return
                }
                assetStatus = "Loading models..."
                do {
                    let models = try await AsrModels.downloadAndLoad(version: .v3)
                    let asr = AsrManager(config: .default)
                    try await asr.loadModels(models)
                    asrManager = asr
                    micVadManager = try await VadManager()
                } catch {
                    lastError = "Failed to load models: \(error.localizedDescription)"
                    assetStatus = "Ready"; isRunning = false; return
                }
            }
            guard let asr = asrManager else { isRunning = false; return }
            asrBackend = FluidAudioASRBackend(manager: asr)
        }

        guard let vadManager = micVadManager else { isRunning = false; return }

        fileTranscriptionURL = url   // cleared by runFileTranscriptionDiarization() after use
        let sessionStart = Date()
        let offsetTracker = FileOffsetTracker()
        fileOffsetTracker = offsetTracker

        let store = transcriptStore
        let fileStream = fileAudioStream(from: url)

        let transcriber = StreamingTranscriber(
            asrBackend: asrBackend,
            vadManager: vadManager,
            speaker: .you,
            audioSource: .microphone,
            onSpeechStart: { [weak self] in
                Task { @MainActor in self?.isSpeechDetected = true }
            },
            onPartial: { text in
                Task { @MainActor in store.volatileYouText = text }
            },
            onFinal: { [weak self] text in
                // Use file-relative offset so diarization timestamps align correctly.
                let utteranceDate = sessionStart.addingTimeInterval(offsetTracker.seconds)
                Task { @MainActor in
                    store.volatileYouText = ""
                    store.append(Utterance(text: text, speaker: .you, timestamp: utteranceDate))
                    self?.isSpeechDetected = false
                }
            }
        )

        assetStatus = "Transcribing file (\(selectedModel.displayName))"
        diagLog("[ENGINE] starting file transcription for \(url.lastPathComponent)")

        fileTask = Task.detached { [weak self] in
            _ = await transcriber.run(stream: fileStream, offsetTracker: offsetTracker)
            Task { @MainActor [weak self] in self?.isSpeechDetected = false }
            // Only auto-stop when the file finished naturally.
            // If fileTask was cancelled (manual Stop), stopSession() already ran — don't call it again.
            guard !Task.isCancelled else { return }
            NotificationCenter.default.post(name: .hushscribeStopRecording, object: nil)
        }
    }

    /// Run post-session diarization on the source file loaded by the user.
    /// Exports audio to a temp WAV first so the diarizer always receives a format it can handle,
    /// regardless of whether the source was an M4A, MP4, MOV, or other container.
    /// Reads and then clears fileTranscriptionURL (mirrors cleanupBufferFile() for system audio).
    nonisolated func runFileTranscriptionDiarization() async -> [(speakerId: String, startTime: Float, endTime: Float)]? {
        let (url, processedSeconds): (URL?, Double) = await MainActor.run {
            let u = fileTranscriptionURL
            let s = fileOffsetTracker?.seconds ?? .infinity
            fileTranscriptionURL = nil
            fileOffsetTracker = nil
            return (u, s)
        }
        guard let url else {
            diagLog("[DIARIZE-FILE] No source URL stored")
            return nil
        }

        diagLog("[DIARIZE-FILE] Exporting \(url.lastPathComponent) to temp WAV (limit: \(processedSeconds)s)...")
        let wavURL: URL
        do {
            wavURL = try await exportAudioToWAV(url, maxDuration: processedSeconds)
        } catch {
            diagLog("[DIARIZE-FILE] WAV export failed: \(error.localizedDescription)")
            return nil
        }
        defer { try? FileManager.default.removeItem(at: wavURL) }

        diagLog("[DIARIZE-FILE] Starting diarization on WAV")
        do {
            let diarizer = OfflineDiarizerManager()
            try await diarizer.prepareModels()
            let result = try await diarizer.process(wavURL)
            let segments = result.segments.map { seg in
                (speakerId: seg.speakerId, startTime: seg.startTimeSeconds, endTime: seg.endTimeSeconds)
            }
            diagLog("[DIARIZE-FILE] Found \(segments.count) segments, \(Set(segments.map(\.speakerId)).count) speakers")
            return segments
        } catch {
            diagLog("[DIARIZE-FILE] Failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Decode any audio/video file to a temporary 16 kHz mono Float32 WAV for the diarizer.
    /// - Parameter maxDuration: only export up to this many seconds (use `.infinity` for the full file).
    private nonisolated func exportAudioToWAV(_ sourceURL: URL, maxDuration: Double = .infinity) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else {
            throw CocoaError(.fileReadUnknown)
        }
        guard let reader = try? AVAssetReader(asset: asset) else {
            throw CocoaError(.fileReadUnknown)
        }

        // Limit the read range when only part of the file was processed
        if maxDuration.isFinite && maxDuration > 0 {
            reader.timeRange = CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: maxDuration, preferredTimescale: 44100)
            )
        }

        // Ask AVAssetReader to decode to 16 kHz mono Float32 non-interleaved PCM
        let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false
        )!
        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true
        ]
        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        trackOutput.alwaysCopiesSampleData = false
        reader.add(trackOutput)
        guard reader.startReading() else { throw CocoaError(.fileReadUnknown) }

        let wavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hushscribe_diar_\(UUID().uuidString).wav")
        guard let audioFile = try? AVAudioFile(forWriting: wavURL, settings: pcmFormat.settings) else {
            throw CocoaError(.fileWriteUnknown)
        }

        while reader.status == .reading {
            guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else { break }
            let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
            guard frameCount > 0,
                  let pcmBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCount)
            else { continue }
            pcmBuffer.frameLength = frameCount
            let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
                sampleBuffer, at: 0, frameCount: Int32(frameCount), into: pcmBuffer.mutableAudioBufferList
            )
            guard status == noErr else { continue }
            try? audioFile.write(from: pcmBuffer)
        }

        return wavURL
    }

    /// Creates an AsyncStream of PCM buffers by decoding an audio or video file via AVAssetReader.
    private nonisolated func fileAudioStream(from url: URL) -> AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { continuation in
            Task.detached {
                let asset = AVURLAsset(url: url)
                guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
                      let reader = try? AVAssetReader(asset: asset) else {
                    continuation.finish()
                    return
                }

                // Decode to mono Float32 at 44100 Hz; StreamingTranscriber resamples to 16 kHz
                let outputSettings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatLinearPCM),
                    AVSampleRateKey: 44100.0,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
                let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
                trackOutput.alwaysCopiesSampleData = false
                reader.add(trackOutput)

                guard reader.startReading() else { continuation.finish(); return }

                let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: 44100,
                    channels: 1,
                    interleaved: true
                )!

                while reader.status == .reading, !Task.isCancelled {
                    guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else { break }
                    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

                    var totalLength = 0
                    var dataPointer: UnsafeMutablePointer<Int8>?
                    let result = CMBlockBufferGetDataPointer(
                        blockBuffer, atOffset: 0,
                        lengthAtOffsetOut: nil,
                        totalLengthOut: &totalLength,
                        dataPointerOut: &dataPointer
                    )
                    guard result == kCMBlockBufferNoErr, let src = dataPointer, totalLength > 0 else { continue }

                    let frameCount = totalLength / 4  // Float32 = 4 bytes per sample
                    guard frameCount > 0,
                          let audioBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
                    else { continue }
                    audioBuffer.frameLength = AVAudioFrameCount(frameCount)
                    audioBuffer.mutableAudioBufferList.pointee.mBuffers.mData!
                        .copyMemory(from: src, byteCount: totalLength)

                    continuation.yield(audioBuffer)
                }
                continuation.finish()
            }
        }
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
