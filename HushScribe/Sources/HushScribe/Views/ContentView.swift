import SwiftUI
import AppKit
import Combine
import CoreAudio

private let conferencingBundleIDs: [String: String] = [
    "com.microsoft.teams2": "Teams",
    "com.microsoft.teams": "Teams",
    "us.zoom.xos": "Zoom",
    "com.apple.FaceTime": "FaceTime",
    "com.tinyspeck.slackmacgap": "Slack",
    "com.cisco.webexmeetingsapp": "Webex",
    "Cisco-Systems.Spark": "Webex",
    "com.google.Chrome": "Chrome",
    "company.thebrowser.Browser": "Arc",
    "com.apple.Safari": "Safari",
    "com.microsoft.edgemac": "Edge",
]

struct ContentView: View {
    @Bindable var settings: AppSettings
    var recordingState: RecordingState
    var transcriptStore: TranscriptStore
    var transcriptionEngine: TranscriptionEngine
    @State private var sessionStore = SessionStore()
    @Environment(\.openSettings) private var openSettings
    @State private var transcriptLogger = TranscriptLogger()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var audioLevel: Float = 0
    @State private var micLevel: Float = 0
    @State private var sysLevel: Float = 0
    @State private var activeSessionType: SessionType?
    @State private var detectedAppName: String?
    @State private var silenceSeconds: Int = 0
    @State private var savedFileURL: URL?
    @State private var bannerDismissTask: Task<Void, Never>?
    @State private var sessionElapsed: Int = 0
    @State private var inputDevices: [(id: AudioDeviceID, name: String)] = []
    @State private var showSpeakerNaming = false
    @State private var speakerLabelsForNaming: [String] = []
    @State private var speakerPreviewsForNaming: [String: [String]] = [:]
    @State private var speakerNamingContinuation: CheckedContinuation<[String: String], Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Glass top bar
            topBar

            // Icon toolbar
            windowToolbar

            // Main content area
            if !isRunning && transcriptStore.utterances.isEmpty
                && transcriptStore.volatileYouText.isEmpty
                && transcriptStore.volatileThemText.isEmpty {
                if transcriptionEngine.modelDownloadState != .ready {
                    modelDownloadState
                } else {
                    emptyState
                }
            } else {
                TranscriptView(
                    utterances: transcriptStore.utterances,
                    volatileYouText: transcriptStore.volatileYouText,
                    volatileThemText: transcriptStore.volatileThemText
                )
            }

            // Save banner
            if let url = savedFileURL, activeSessionType == nil {
                saveBanner(url: url)
            }

            // Waveform ribbon
            WaveformView(
                isRecording: isRunning,
                micLevel: micLevel,
                sysLevel: sysLevel,
                isMicMuted: transcriptionEngine.isMicMuted,
                isSysMuted: transcriptionEngine.isSysMuted,
                onToggleMicMute: { transcriptionEngine.isMicMuted.toggle() },
                onToggleSysMute: { transcriptionEngine.isSysMuted.toggle() }
            )

            // Silence timeout countdown / pause indicator
            if isRunning {
                if transcriptionEngine.isPaused {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 10))
                        Text("Paused")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Color.fg3)
                    .padding(.vertical, 4)
                } else {
                    silenceTimeoutDisplay
                }
            }

            // Glass control bar
            ControlBar(
                isRecording: isRunning,
                isPaused: transcriptionEngine.isPaused,
                modelsReady: transcriptionEngine.modelDownloadState == .ready,
                activeSessionType: activeSessionType,
                audioLevel: audioLevel,
                detectedApp: detectedAppName,
                silenceSeconds: silenceSeconds,
                statusMessage: transcriptionEngine.modelDownloadState == .downloading ? nil : transcriptionEngine.assetStatus,
                errorMessage: transcriptionEngine.lastError,
                onStartCallCapture: { startSession(type: .callCapture) },
                onStartVoiceMemo: { startSession(type: .voiceMemo) },
                onStop: stopSession,
                onPause: pauseFromMenu,
                onResume: resumeFromMenu
            )
        }
        .frame(minWidth: 480, maxWidth: 480, minHeight: 360)
        .background(Color.bg0)
        .overlay {
            if showOnboarding {
                OnboardingView(isPresented: $showOnboarding, settings: settings)
                    .transition(.opacity)
            }
        }
        .overlay {
            if showSpeakerNaming {
                SpeakerNamingView(
                    speakerLabels: speakerLabelsForNaming,
                    previews: speakerPreviewsForNaming,
                    onApply: { mapping in
                        showSpeakerNaming = false
                        speakerNamingContinuation?.resume(returning: mapping)
                        speakerNamingContinuation = nil
                    },
                    onSkip: {
                        showSpeakerNaming = false
                        speakerNamingContinuation?.resume(returning: [:])
                        speakerNamingContinuation = nil
                    }
                )
                .transition(.opacity)
            }
        }
        .onChange(of: showOnboarding) {
            if !showOnboarding {
                hasCompletedOnboarding = true
            }
        }
        .task {
            if !hasCompletedOnboarding {
                showOnboarding = true
                // LSUIElement apps don't auto-activate; bring the window to front for onboarding.
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.mainWindow?.makeKeyAndOrderFront(nil)
            }
        }
        // Audio level polling
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                if transcriptionEngine.isRunning {
                    let newMic = transcriptionEngine.micAudioLevel
                    let newSys = transcriptionEngine.sysAudioLevel
                    let newCombined = transcriptionEngine.audioLevel
                    if abs(newMic - micLevel) > 0.005 { micLevel = newMic }
                    if abs(newSys - sysLevel) > 0.005 { sysLevel = newSys }
                    if abs(newCombined - audioLevel) > 0.005 { audioLevel = newCombined }
                    if audioLevel > 0.01 {
                        silenceSeconds = 0
                    }
                } else if audioLevel != 0 {
                    audioLevel = 0
                    micLevel = 0
                    sysLevel = 0
                }
            }
        }
        // Silence auto-stop + elapsed timer
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard isRunning else {
                    silenceSeconds = 0
                    continue
                }
                guard !transcriptionEngine.isPaused else { continue }
                sessionElapsed += 1
                if audioLevel < 0.01 {
                    silenceSeconds += 1
                    if silenceSeconds >= settings.silenceTimeoutSeconds {
                        stopSession()
                    }
                }
            }
        }
        // Transcript buffer flush
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await transcriptLogger.flushIfNeeded()
            }
        }
        // Menu bar action notifications
        .onReceive(NotificationCenter.default.publisher(for: .hushscribeStartCallCapture)) { _ in
            startSession(type: .callCapture)
        }
        .onReceive(NotificationCenter.default.publisher(for: .hushscribeStartVoiceMemo)) { _ in
            startSession(type: .voiceMemo)
        }
        .onReceive(NotificationCenter.default.publisher(for: .hushscribeStopRecording)) { _ in
            stopSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hushscribePauseRecording)) { _ in
            pauseFromMenu()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hushscribeResumeRecording)) { _ in
            resumeFromMenu()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hushscribeOpenSummarize)) { _ in
            SummarizeView.openWindow(settings: settings, logger: transcriptLogger)
        }
        .onChange(of: settings.inputDeviceID) {
            if isRunning {
                transcriptionEngine.restartMic(inputDeviceID: settings.inputDeviceID)
            }
        }
        .onChange(of: settings.transcriptionModel) {
            transcriptionEngine.setModel(settings.transcriptionModel)
        }
        .onChange(of: transcriptStore.utterances.count) {
            handleNewUtterance()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 0) {
            Text("HUSHSCRIBE")
                .font(.system(size: 14, weight: .heavy))
                .tracking(3)
                .foregroundStyle(Color.fg1)

            Spacer()

            HStack(spacing: 10) {
                Menu {
                    Button {
                        settings.inputDeviceID = 0
                    } label: {
                        HStack {
                            Text("System Default")
                            if settings.inputDeviceID == 0 { Image(systemName: "checkmark") }
                        }
                    }
                    Divider()
                    ForEach(inputDevices, id: \.id) { device in
                        Button {
                            settings.inputDeviceID = device.id
                        } label: {
                            HStack {
                                Text(device.name)
                                if settings.inputDeviceID == device.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Text(topBarStatus)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isRunning ? Color.fg1 : Color.fg2)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .onAppear { inputDevices = MicCapture.availableInputDevices() }
                .help("Click to select input device")

                if isRunning {
                    PulsingDot(size: 6)
                } else {
                    Circle()
                        .fill(Color.fg2)
                        .frame(width: 6, height: 6)
                        .opacity(0.5)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.bar)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Window Toolbar

    private var windowToolbar: some View {
        HStack(spacing: 0) {
            toolbarButton(icon: "doc.text.magnifyingglass", label: "Transcripts") {
                SummarizeView.openWindow(settings: settings, logger: transcriptLogger)
            }
            toolbarButton(icon: "gear", label: "Settings") {
                settings.preferredSettingsTab = 0
                openSettings()
            }
            Spacer()
            toolbarButton(icon: "eye.slash", label: "Hide") {
                NSApp.windows.first { (w: NSWindow) in w.isVisible && !(w is NSPanel) && w.level == .normal }?.orderOut(nil)
                NSApp.setActivationPolicy(.accessory)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 44)
        .background(.bar)
        .overlay(Divider(), alignment: .bottom)
    }

    private func toolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(Color.fg2)
            .frame(width: 52, height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var topBarStatus: String {
        let deviceID = settings.inputDeviceID == 0
            ? (MicCapture.defaultInputDeviceID() ?? 0)
            : settings.inputDeviceID
        let deviceSuffix = deviceID != 0 ? MicCapture.deviceName(for: deviceID).map { " · \($0)" } ?? "" : ""

        if isRunning {
            let pauseSuffix = transcriptionEngine.isPaused ? " · Paused" : ""
            return "\(formatTime(sessionElapsed))\(pauseSuffix)\(deviceSuffix)"
        } else if savedFileURL != nil {
            return "\(formatTime(sessionElapsed)) · Done\(deviceSuffix)"
        } else {
            return "Ready\(deviceSuffix)"
        }
    }

    // MARK: - Model Download State

    private var modelDownloadState: some View {
        VStack(spacing: 12) {
            if transcriptionEngine.modelDownloadState == .downloading {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color.accent1)
                Text(transcriptionEngine.assetStatus)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.fg2)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.fg3)
                Text("Transcription model required")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.fg2)
                Text("Download the on-device model (~600 MB)\nto start transcribing.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.fg3)
                    .multilineTextAlignment(.center)
                Button("Download Model") {
                    Task { await transcriptionEngine.downloadModels() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accent1)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accent1.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                if let error = transcriptionEngine.lastError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.recordRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 28))
                .foregroundStyle(Color.fg3)
            Text("No active session")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.fg2)
            Text("Start a call capture or voice memo\nto begin transcribing.")
                .font(.system(size: 11))
                .foregroundStyle(Color.fg3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Silence Timeout Display

    private var silenceTimeoutDisplay: some View {
        let remaining = max(0, settings.silenceTimeoutSeconds - silenceSeconds)
        let isUrgent = remaining <= 30
        let isActive = silenceSeconds > 0
        return Button {
            silenceSeconds = 0
        } label: {
            Text(formatTime(remaining))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isUrgent ? Color.red : (isActive ? Color.primary : Color.secondary))
                .opacity(isActive ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 3)
    }

    // MARK: - Save Banner

    private func saveBanner(url: URL) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.accent1.opacity(0.15))
                .frame(width: 16, height: 16)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.accent1)
                )
            Text("Saved to \(url.lastPathComponent)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.fg1)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Show Transcript") {
                SummarizeView.openWindow(for: url, settings: settings, logger: transcriptLogger)
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(Color.accent1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(Divider(), alignment: .top)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Helpers

    private var isRunning: Bool {
        transcriptionEngine.isRunning
    }

    private func formatTime(_ s: Int) -> String {
        "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    // MARK: - Actions

    private func startSession(type: SessionType) {
        transcriptStore.clear()
        silenceSeconds = 0
        sessionElapsed = 0
        savedFileURL = nil
        bannerDismissTask?.cancel()

        // Determine output folder and app bundle ID based on session type
        let outputPath: String
        let sourceApp: String
        var appBundleID: String?
        var resolvedAppName: String?

        switch type {
        case .callCapture:
            outputPath = settings.vaultMeetingsPath
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               let bundleID = frontApp.bundleIdentifier,
               let appName = conferencingBundleIDs[bundleID] {
                sourceApp = appName
                appBundleID = bundleID
                resolvedAppName = appName
            } else {
                sourceApp = "Call"
            }
        case .voiceMemo:
            outputPath = settings.vaultVoicePath
            sourceApp = "Voice Memo"
        }

        Task {
            transcriptionEngine.lastError = nil
            await sessionStore.startSession()
            do {
                try await transcriptLogger.startSession(
                    sourceApp: sourceApp,
                    vaultPath: outputPath,
                    sessionType: type
                )
            } catch {
                await sessionStore.endSession()
                transcriptionEngine.lastError = error.localizedDescription
                return
            }
            activeSessionType = type
            detectedAppName = resolvedAppName
            recordingState.isRecording = true
            recordingState.isPaused = false
            if type == .callCapture {
                await transcriptionEngine.start(
                    locale: settings.locale,
                    inputDeviceID: settings.inputDeviceID,
                    appBundleID: appBundleID,
                    sysVadThreshold: settings.sysVadThreshold
                )
            } else {
                await transcriptionEngine.start(
                    locale: settings.locale,
                    inputDeviceID: settings.inputDeviceID,
                    sysVadThreshold: settings.sysVadThreshold
                )
            }
        }
    }

    private func pauseFromMenu() {
        transcriptionEngine.pause()
        recordingState.isPaused = true
    }

    private func resumeFromMenu() {
        transcriptionEngine.resume()
        recordingState.isPaused = false
    }

    private func stopSession() {
        let wasCallCapture = activeSessionType == .callCapture
        activeSessionType = nil
        detectedAppName = nil
        silenceSeconds = 0
        recordingState.isRecording = false
        recordingState.isPaused = false

        Task {
            await transcriptionEngine.stop()
            await sessionStore.endSession()
            await transcriptLogger.endSession()

            if wasCallCapture {
                transcriptionEngine.assetStatus = "Identifying speakers..."
                if let segments = await transcriptionEngine.runPostSessionDiarization() {
                    transcriptionEngine.assetStatus = "Rewriting transcript..."
                    let speakerMap = await transcriptLogger.rewriteWithDiarization(segments: segments)

                    let genericLabels = Set(speakerMap.values).sorted()
                    if !genericLabels.isEmpty {
                        transcriptionEngine.assetStatus = "Ready"

                        let previews = await transcriptLogger.speakerExcerpts(for: genericLabels)

                        let mapping: [String: String] = await withCheckedContinuation { continuation in
                            speakerLabelsForNaming = genericLabels
                            speakerPreviewsForNaming = previews
                            speakerNamingContinuation = continuation
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showSpeakerNaming = true
                            }
                        }

                        if !mapping.isEmpty {
                            transcriptionEngine.assetStatus = "Applying names..."
                            await transcriptLogger.applySpeakerRenames(mapping)
                        }
                    }
                }
            }

            transcriptionEngine.assetStatus = "Finalizing..."
            let savedPath = await transcriptLogger.finalizeFrontmatter()

            transcriptionEngine.assetStatus = "Ready"

            if activeSessionType == nil, let savedPath {
                savedFileURL = savedPath
                bannerDismissTask?.cancel()
                bannerDismissTask = Task {
                    try? await Task.sleep(for: .seconds(8))
                    if !Task.isCancelled { savedFileURL = nil }
                }
            }
        }
    }

    private func handleNewUtterance() {
        guard let last = transcriptStore.utterances.last else { return }

        silenceSeconds = 0

        let speakerName = last.speaker == .you ? "You" : "Them"
        Task {
            await transcriptLogger.append(
                speaker: speakerName,
                text: last.text,
                timestamp: last.timestamp
            )
        }

        Task {
            await sessionStore.appendRecord(SessionRecord(
                speaker: last.speaker,
                text: last.text,
                timestamp: last.timestamp
            ))
        }
    }
}
