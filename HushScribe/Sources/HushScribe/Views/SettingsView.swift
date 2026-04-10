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
            ModelsSettingsTab(settings: settings, engine: engine, llmEngine: LLMSummaryEngine.shared)
                .tabItem { Label("Models", systemImage: "cpu") }
                .tag(2)
            OutputSettingsTab(settings: settings)
                .tabItem { Label("Output", systemImage: "folder") }
                .tag(3)
            PrivacySettingsTab(settings: settings)
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
                .tag(4)
        }
        .frame(width: 540, height: 460)
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
    var llmEngine: LLMSummaryEngine
    @State private var modelSubTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $modelSubTab) {
                Text("Transcription").tag(0)
                Text("AI Summaries").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            if modelSubTab == 0 {
                TranscriptionModelsSubTab(settings: settings, engine: engine)
            } else {
                SummaryModelsSubTab(settings: settings, llmEngine: llmEngine)
            }
        }
    }
}

private struct TranscriptionModelsSubTab: View {
    @Bindable var settings: AppSettings
    var engine: TranscriptionEngine

    var body: some View {
        Form {
            Section {
                ForEach(TranscriptionModel.allCases, id: \.self) { model in
                    ModelRow(model: model, settings: settings, engine: engine)
                }
            } header: {
                Text("Convert speech to text. All models run on-device via Apple Silicon.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .padding(.bottom, 2)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SummaryModelsSubTab: View {
    @Bindable var settings: AppSettings
    var llmEngine: LLMSummaryEngine

    var body: some View {
        Form {
            Section {
                ForEach(SummaryModel.allCases, id: \.self) { model in
                    SummaryModelRow(model: model, settings: settings, llmEngine: llmEngine)
                }
            } header: {
                Text("Generate highlights and to-dos from transcripts. All models run on-device.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .padding(.bottom, 2)
            }

            // Apple NL warning
            if settings.summaryModel.isBuiltIn {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 13))
                        Text("Apple NL produces keyword-based output and is usually not satisfactory. Download and use Qwen3 or Gemma 3 for better results.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Generation") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Temperature")
                            .font(.system(size: 12))
                        Spacer()
                        Text(String(format: "%.2f", settings.summaryTemperature))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.summaryTemperature, in: 0.0...1.0, step: 0.05)
                }
                .disabled(settings.summaryModel.isBuiltIn)
                Text("Controls how creative vs. deterministic the summary is. Lower values produce more focused output; higher values more varied. Has no effect on the built-in Apple NL model.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Stepper(
                    "Max tokens: \(settings.summaryMaxTokens)",
                    value: $settings.summaryMaxTokens,
                    in: 500...16000,
                    step: 500
                )
                .font(.system(size: 12))
                .disabled(settings.summaryModel.isBuiltIn)
                Text("Maximum number of tokens the model can generate. Higher values allow longer summaries but take more time. Default: 4000.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(0..<3) { i in
                    CustomPromptRow(index: i, prompt: $settings.customSummaryPrompts[i])
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CUSTOM PROMPTS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accent1)
                    Text("Define up to 3 named system prompts. A named prompt appears in the transcript viewer's prompt picker.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .textCase(nil)
                .padding(.bottom, 2)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CustomPromptRow: View {
    let index: Int
    @Binding var prompt: CustomSummaryPrompt

    private static let namePlaceholders = [
        "e.g. Action items only",
        "e.g. Executive summary",
        "e.g. Technical notes",
    ]

    private static let bodyPlaceholders = [
        "e.g. List only action items and decisions. Skip pleasantries and small talk.",
        "e.g. Write a 3-sentence executive summary of the key outcomes and next steps.",
        "e.g. Extract technical decisions, architecture choices, and any bugs discussed.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom Prompt \(index + 1)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Name")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
                TextField(
                    "",
                    text: $prompt.name,
                    prompt: Text(Self.namePlaceholders[index])
                        .italic()
                        .foregroundStyle(Color(NSColor.placeholderTextColor))
                )
                .font(.system(size: 12))
                .textFieldStyle(.roundedBorder)
            }

            HStack(alignment: .top, spacing: 8) {
                Text("Prompt")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
                    .fixedSize()
                    .padding(.top, 4)
                ZStack(alignment: .topLeading) {
                    if prompt.body.isEmpty {
                        Text(Self.bodyPlaceholders[index])
                            .font(.system(size: 11))
                            .italic()
                            .foregroundStyle(Color(NSColor.placeholderTextColor))
                            .padding(.horizontal, 5)
                            .padding(.top, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $prompt.body)
                        .font(.system(size: 11))
                        .frame(minHeight: 72, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                }
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(NSColor.separatorColor)))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ModelRow: View {
    let model: TranscriptionModel
    @Bindable var settings: AppSettings
    var engine: TranscriptionEngine
    @State private var isDownloaded = false

    private var isActive: Bool { settings.transcriptionModel == model }

    private var isDownloading: Bool {
        switch model {
        case .parakeet: return engine.modelDownloadState == .downloading
        default: return engine.downloadingModel == model
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                // Name + description
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.system(size: 13, weight: .medium))
                        if isActive {
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
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Single contextual action area — one clear state at a time
                actionArea
            }

            if isDownloading {
                ProgressView(engine.assetStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .progressViewStyle(.linear)
            }
        }
        .padding(.vertical, 2)
        .onAppear { isDownloaded = engine.isModelDownloaded(model) }
        .onChange(of: engine.modelDownloadState) { _, _ in isDownloaded = engine.isModelDownloaded(model) }
        .onChange(of: engine.downloadingModel) { _, _ in isDownloaded = engine.isModelDownloaded(model) }
    }

    @ViewBuilder
    private var actionArea: some View {
        if isDownloading {
            ProgressView()
                .controlSize(.small)
        } else if model.isAppleSpeech {
            // Built-in: no download needed, just Use or nothing
            if !isActive {
                useButton
            }
        } else if isDownloaded {
            HStack(spacing: 10) {
                Text(model.sizeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Button("Remove") {
                    engine.removeModel(model)
                    isDownloaded = false
                    if isActive {
                        settings.transcriptionModel = .parakeet
                        engine.setModel(.parakeet)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .buttonStyle(.plain)
                .disabled(engine.isRunning)

                if !isActive {
                    useButton
                }
            }
        } else {
            // Not downloaded: show size + download
            Button("Download  \(model.sizeLabel)") {
                Task { await engine.downloadModel(model) }
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)
        }
    }

    private var useButton: some View {
        Button("Use") {
            settings.transcriptionModel = model
            engine.setModel(model)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 5))
        .buttonStyle(.plain)
        .disabled(engine.isRunning)
    }
}

// MARK: - Summary Model Row

private struct SummaryModelRow: View {
    let model: SummaryModel
    @Bindable var settings: AppSettings
    var llmEngine: LLMSummaryEngine
    @State private var isDownloaded = false

    private var isActive: Bool { settings.summaryModel == model }
    private var isDownloading: Bool { llmEngine.downloadingModel == model }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.system(size: 13, weight: .medium))
                        if isActive {
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
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
                actionArea
            }

            if isDownloading {
                ProgressView(value: llmEngine.downloadProgress)
                    .progressViewStyle(.linear)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .onAppear { isDownloaded = llmEngine.isModelDownloaded(model) }
        .onChange(of: llmEngine.downloadingModel) { _, _ in isDownloaded = llmEngine.isModelDownloaded(model) }
    }

    @ViewBuilder
    private var actionArea: some View {
        if isDownloading {
            ProgressView()
                .controlSize(.small)
        } else if model.isBuiltIn {
            if !isActive {
                useButton
            }
        } else if isDownloaded {
            HStack(spacing: 10) {
                Text(model.sizeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Button("Remove") {
                    llmEngine.removeModel(model)
                    isDownloaded = false
                    if isActive { settings.summaryModel = .appleNL }
                }
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .buttonStyle(.plain)

                if !isActive { useButton }
            }
        } else {
            Button("Download  \(model.sizeLabel)") {
                Task { await llmEngine.downloadModel(model) }
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)
        }
    }

    private var useButton: some View {
        Button("Use") {
            settings.summaryModel = model
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 5))
        .buttonStyle(.plain)
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
