import SwiftUI
import CoreAudio
import FluidAudio

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var engine: TranscriptionEngine
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            RecordingSettingsTab(settings: settings)
                .tabItem { Label("Recording", systemImage: "waveform") }
                .tag(0)
            MeetingDetectionSettingsTab(settings: settings)
                .tabItem { Label("Meetings", systemImage: "person.2") }
                .tag(1)
            ModelsSettingsTab(settings: settings, engine: engine)
                .tabItem { Label("Models", systemImage: "cpu") }
                .tag(2)
            OutputSettingsTab(settings: settings)
                .tabItem { Label("Output", systemImage: "folder") }
                .tag(3)
            PrivacySettingsTab(settings: settings)
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
                .tag(4)
        }
        .frame(width: 540, height: 560)
        .onAppear { selectedTab = settings.preferredSettingsTab }
        .onChange(of: settings.preferredSettingsTab) { _, tab in selectedTab = tab }
    }
}

// MARK: - Recording Tab

private struct RecordingSettingsTab: View {
    @Bindable var settings: AppSettings
    @State private var inputDevices: [(id: AudioDeviceID, name: String)] = []

    var body: some View {
        Form {
            Section("Audio Input") {
                Picker("Microphone", selection: $settings.inputDeviceID) {
                    Text("System Default").tag(AudioDeviceID(0))
                    ForEach(inputDevices, id: \.id) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .font(.system(size: 12))
            }

            Section("Silence Timeout") {
                Stepper(
                    "Stop after: \(formatTimeout(settings.silenceTimeoutSeconds))",
                    value: $settings.silenceTimeoutSeconds,
                    in: 30...600,
                    step: 30
                )
                .font(.system(size: 12))
                Text("Session stops automatically after this much silence. During a recording, click the countdown below the waveform to reset the timer.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("System Audio") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("VAD sensitivity")
                            .font(.system(size: 12))
                        Spacer()
                        Text(String(format: "%.2f", settings.sysVadThreshold))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.sysVadThreshold, in: 0.5...0.99, step: 0.01)
                }
                Text("Controls how confidently the VAD must detect speech before transcribing. Higher values reduce false positives from background noise. Default: 0.92.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
        .onAppear {
            inputDevices = MicCapture.availableInputDevices()
            if settings.inputDeviceID != 0 && !inputDevices.contains(where: { $0.id == settings.inputDeviceID }) {
                settings.inputDeviceID = 0
            }
        }
    }

    private func formatTimeout(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }
}

// MARK: - Meeting Detection Tab

private struct MeetingDetectionSettingsTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Auto-Record") {
                Toggle("Auto-record when meeting detected", isOn: $settings.autoMeetingDetect)
                    .font(.system(size: 12))
                Text("Automatically starts a Call Capture session when Teams, Zoom, Slack, FaceTime, Webex, Discord, or Google Meet is detected. Recording stops after the app quits. Browser-based meetings (e.g. Google Meet or Teams in a web browser) are not supported.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Timing") {
                Stepper(
                    "Start delay: \(settings.meetingDetectDelaySecs)s",
                    value: $settings.meetingDetectDelaySecs,
                    in: 0...15,
                    step: 1
                )
                .font(.system(size: 12))
                .disabled(!settings.autoMeetingDetect)
                Text("Seconds to wait after the meeting app launches before recording starts.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Stepper(
                    "Stop delay: \(settings.meetingStopDelaySecs)s",
                    value: $settings.meetingStopDelaySecs,
                    in: 0...60,
                    step: 5
                )
                .font(.system(size: 12))
                .disabled(!settings.autoMeetingDetect)
                Text("Seconds to wait after the meeting ends before stopping recording. Gives time for any remaining audio to be captured.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Models Tab

private struct ModelsSettingsTab: View {
    @Bindable var settings: AppSettings
    var engine: TranscriptionEngine

    var body: some View {
        Form {
            Section {
                ForEach(TranscriptionModel.allCases, id: \.self) { model in
                    ModelRow(model: model, settings: settings, engine: engine)
                }
            } header: {
                Text("All models run entirely on-device. No audio or data leaves your Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModelRow: View {
    let model: TranscriptionModel
    @Bindable var settings: AppSettings
    var engine: TranscriptionEngine
    @State private var isDownloaded = false

    private var isDownloading: Bool {
        switch model {
        case .parakeet: return engine.modelDownloadState == .downloading
        default: return engine.downloadingModel == model
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.system(size: 13, weight: .medium))
                        if settings.transcriptionModel == model {
                            Text("Active")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(model.settingsDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    statusBadge
                    HStack(spacing: 8) {
                        downloadButton
                        useButton
                    }
                }
            }

            if isDownloading {
                ProgressView(engine.assetStatus)
                    .font(.system(size: 11))
                    .progressViewStyle(.linear)
            }
        }
        .padding(.vertical, 2)
        .onAppear { isDownloaded = engine.isModelDownloaded(model) }
        .onChange(of: engine.modelDownloadState) { _, _ in isDownloaded = engine.isModelDownloaded(model) }
        .onChange(of: engine.downloadingModel) { _, _ in isDownloaded = engine.isModelDownloaded(model) }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch model {
        case .appleSpeech:
            Text("Built-in")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        default:
            if isDownloading {
                EmptyView()
            } else if isDownloaded {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Text(model.sizeLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var downloadButton: some View {
        if !model.isAppleSpeech && !isDownloading {
            if isDownloaded {
                Button("Remove") {
                    engine.removeModel(model)
                    isDownloaded = false
                    if settings.transcriptionModel == model {
                        settings.transcriptionModel = .parakeet
                        engine.setModel(.parakeet)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .buttonStyle(.plain)
                .disabled(engine.isRunning)
            } else {
                Button("Download") {
                    Task { await engine.downloadModel(model) }
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private var useButton: some View {
        let isActive = settings.transcriptionModel == model
        let canUse = model.isAppleSpeech || isDownloaded
        if !isActive && !isDownloading {
            Button("Use") {
                settings.transcriptionModel = model
                engine.setModel(model)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(canUse ? .white : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(canUse ? Color.accentColor : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            .buttonStyle(.plain)
            .disabled(!canUse || engine.isRunning)
        }
    }
}

// MARK: - Output Tab

private struct OutputSettingsTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Output Folders") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Meetings")
                            .font(.system(size: 12, weight: .medium))
                        Text(settings.vaultMeetingsPath.isEmpty ? "No folder selected" : settings.vaultMeetingsPath)
                            .font(.system(size: 11))
                            .foregroundStyle(settings.vaultMeetingsPath.isEmpty ? .tertiary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if !settings.vaultMeetingsPath.isEmpty {
                        Button("Show in Finder") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: settings.vaultMeetingsPath))
                        }
                        .font(.system(size: 11))
                    }
                    Button("Choose...") {
                        chooseFolder(message: "Choose the folder for meeting transcripts") { path in
                            settings.vaultMeetingsPath = path
                        }
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voice Memos")
                            .font(.system(size: 12, weight: .medium))
                        Text(settings.vaultVoicePath.isEmpty ? "No folder selected" : settings.vaultVoicePath)
                            .font(.system(size: 11))
                            .foregroundStyle(settings.vaultVoicePath.isEmpty ? .tertiary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if !settings.vaultVoicePath.isEmpty {
                        Button("Show in Finder") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: settings.vaultVoicePath))
                        }
                        .font(.system(size: 11))
                    }
                    Button("Choose...") {
                        chooseFolder(message: "Choose the folder for voice memo transcripts") { path in
                            settings.vaultVoicePath = path
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder(message: String, onSelect: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        if panel.runModal() == .OK, let url = panel.url {
            onSelect(url.path)
        }
    }
}

// MARK: - Privacy Tab

private struct PrivacySettingsTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Screen Sharing") {
                Toggle("Hide from screen sharing", isOn: $settings.hideFromScreenShare)
                    .font(.system(size: 12))
                Text("When enabled, the app window is invisible during screen sharing and screen recording.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
