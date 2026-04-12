import AppKit
import Foundation
import Observation
import CoreAudio

struct CustomSummaryPrompt: Codable, Equatable {
    var name: String
    var body: String
    var isEmpty: Bool { name.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// Identifies which system prompt to use for LLM summarisation.
/// `.default` uses the built-in prompt; `.custom(0/1/2)` uses one of the three user-defined prompts.
enum SummaryPromptSelection: Equatable, Hashable {
    case `default`
    case custom(Int)

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .custom(let i): return "Custom \(i + 1)"
        }
    }
}

enum SessionType: String {
    case callCapture
    case voiceMemo
}

enum MainWindowMode: String, CaseIterable {
    case attached
    case detached
}

enum TranscriptionModel: String, CaseIterable {
    case parakeet = "parakeet"
    case whisperBase = "whisperBase"
    case whisperLargeV3 = "whisperLargeV3"
    case appleSpeech = "appleSpeech"

    var displayName: String {
        switch self {
        case .parakeet: return "Parakeet-TDT v3 (Multilingual)"
        case .whisperBase: return "Whisper Base"
        case .whisperLargeV3: return "Whisper Large v3"
        case .appleSpeech: return "Apple Speech"
        }
    }

    var whisperModelID: String? {
        switch self {
        case .parakeet: return nil
        case .whisperBase: return "openai_whisper-base"
        case .whisperLargeV3: return "openai_whisper-large-v3"
        case .appleSpeech: return nil
        }
    }

    var isWhisperKit: Bool { whisperModelID != nil }
    var isAppleSpeech: Bool { self == .appleSpeech }

    var settingsDescription: String {
        switch self {
        case .parakeet:
            return "Parakeet-TDT v3 via FluidAudio. 25 European languages, auto-detected. Runs on Apple Silicon ANE. Fastest option."
        case .whisperBase:
            return "OpenAI Whisper Base via WhisperKit. Good for English. Smaller and faster than Large v3."
        case .whisperLargeV3:
            return "OpenAI Whisper Large v3 via WhisperKit. Best accuracy across 99 languages. Larger download."
        case .appleSpeech:
            return "macOS built-in speech recogniser. No download required. Requires a one-time permission prompt."
        }
    }

    var sizeLabel: String {
        switch self {
        case .parakeet: return "~600 MB"
        case .whisperBase: return "~150 MB"
        case .whisperLargeV3: return "~1.5 GB"
        case .appleSpeech: return ""
        }
    }
}

@Observable
@MainActor
final class AppSettings {
    var transcriptionLocale: String {
        didSet { UserDefaults.standard.set(transcriptionLocale, forKey: "transcriptionLocale") }
    }

    /// Stored as the AudioDeviceID integer. 0 means "use system default".
    var inputDeviceID: AudioDeviceID {
        didSet { UserDefaults.standard.set(Int(inputDeviceID), forKey: "inputDeviceID") }
    }

    var vaultMeetingsPath: String {
        didSet { UserDefaults.standard.set(vaultMeetingsPath, forKey: "vaultMeetingsPath") }
    }

    var vaultVoicePath: String {
        didSet { UserDefaults.standard.set(vaultVoicePath, forKey: "vaultVoicePath") }
    }

    /// Seconds of silence before a session auto-stops. Default 120.
    var silenceTimeoutSeconds: Int {
        didSet { UserDefaults.standard.set(silenceTimeoutSeconds, forKey: "silenceTimeoutSeconds") }
    }

    /// Which ASR model to use for transcription.
    var transcriptionModel: TranscriptionModel {
        didSet { UserDefaults.standard.set(transcriptionModel.rawValue, forKey: "transcriptionModel") }
    }

    /// Which model to use for AI summaries. Default is the built-in NL framework.
    var summaryModel: SummaryModel {
        didSet { UserDefaults.standard.set(summaryModel.rawValue, forKey: "summaryModel") }
    }

    /// Temperature for LLM summary generation (0.0–1.0). Default 0.3.
    var summaryTemperature: Double {
        didSet { UserDefaults.standard.set(summaryTemperature, forKey: "summaryTemperature") }
    }

    /// Maximum tokens for LLM summary generation. Default 4000.
    var summaryMaxTokens: Int {
        didSet { UserDefaults.standard.set(summaryMaxTokens, forKey: "summaryMaxTokens") }
    }

    /// Three user-defined summary prompts (name + body). Empty slots are ignored in the UI.
    var customSummaryPrompts: [CustomSummaryPrompt] {
        didSet {
            if let data = try? JSONEncoder().encode(customSummaryPrompts) {
                UserDefaults.standard.set(data, forKey: "customSummaryPrompts")
            }
        }
    }

    /// Which prompt is selected for summarisation. Not persisted (resets to default on launch).
    var selectedSummaryPrompt: SummaryPromptSelection = .default

    /// VAD confidence threshold for system audio (0.0–1.0). Higher = less sensitive, fewer false positives.
    var sysVadThreshold: Double {
        didSet { UserDefaults.standard.set(sysVadThreshold, forKey: "sysVadThreshold") }
    }

    /// When true, recording starts automatically when a meeting app is detected.
    var autoMeetingDetect: Bool {
        didSet { UserDefaults.standard.set(autoMeetingDetect, forKey: "autoMeetingDetect") }
    }

    /// Seconds to wait after a meeting app launches before auto-starting. Default 3.
    var meetingDetectDelaySecs: Int {
        didSet { UserDefaults.standard.set(meetingDetectDelaySecs, forKey: "meetingDetectDelaySecs") }
    }

    /// Seconds to wait after a meeting ends before auto-stopping. Default 5.
    var meetingStopDelaySecs: Int {
        didSet { UserDefaults.standard.set(meetingStopDelaySecs, forKey: "meetingStopDelaySecs") }
    }

    /// In-memory tab index for Settings navigation (not persisted).
    var preferredSettingsTab: Int = 0

    /// When true, the user has acknowledged the legal disclaimer in the onboarding wizard.
    /// Recording is blocked until this is true.
    var hasAcknowledgedDisclaimer: Bool {
        didSet { UserDefaults.standard.set(hasAcknowledgedDisclaimer, forKey: "hasAcknowledgedDisclaimer") }
    }

    /// Controls how the main window behaves relative to the status bar.
    var mainWindowMode: MainWindowMode {
        didSet { UserDefaults.standard.set(mainWindowMode.rawValue, forKey: "mainWindowMode") }
    }

    /// When true, a subtle sound plays when recording starts or stops.
    var notificationSoundEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationSoundEnabled, forKey: "notificationSoundEnabled") }
    }

    /// When true, all app windows are invisible to screen sharing / recording.
    var hideFromScreenShare: Bool {
        didSet {
            UserDefaults.standard.set(hideFromScreenShare, forKey: "hideFromScreenShare")
            applyScreenShareVisibility()
        }
    }

    init() {
        let defaults = UserDefaults.standard
        self.transcriptionLocale = defaults.string(forKey: "transcriptionLocale") ?? "en-US"
        self.inputDeviceID = AudioDeviceID(defaults.integer(forKey: "inputDeviceID"))
        let storedTimeout = defaults.integer(forKey: "silenceTimeoutSeconds")
        self.silenceTimeoutSeconds = storedTimeout > 0 ? storedTimeout : 120
        let storedModel = defaults.string(forKey: "transcriptionModel") ?? ""
        self.transcriptionModel = TranscriptionModel(rawValue: storedModel) ?? .parakeet
        let storedSummaryModel = defaults.string(forKey: "summaryModel") ?? ""
        self.summaryModel = SummaryModel(rawValue: storedSummaryModel) ?? .appleNL
        let storedTemp = defaults.double(forKey: "summaryTemperature")
        self.summaryTemperature = storedTemp > 0 ? storedTemp : 0.3
        let storedMaxTokens = defaults.integer(forKey: "summaryMaxTokens")
        self.summaryMaxTokens = storedMaxTokens > 0 ? storedMaxTokens : 4000
        if let data = defaults.data(forKey: "customSummaryPrompts"),
           let decoded = try? JSONDecoder().decode([CustomSummaryPrompt].self, from: data) {
            self.customSummaryPrompts = decoded
        } else {
            self.customSummaryPrompts = [
                CustomSummaryPrompt(name: "", body: ""),
                CustomSummaryPrompt(name: "", body: ""),
                CustomSummaryPrompt(name: "", body: ""),
            ]
        }
        let storedThreshold = defaults.double(forKey: "sysVadThreshold")
        self.sysVadThreshold = storedThreshold > 0 ? storedThreshold : 0.92
        self.autoMeetingDetect = defaults.bool(forKey: "autoMeetingDetect")
        let storedDelay = defaults.integer(forKey: "meetingDetectDelaySecs")
        self.meetingDetectDelaySecs = storedDelay > 0 ? storedDelay : 3
        let storedStopDelay = defaults.integer(forKey: "meetingStopDelaySecs")
        self.meetingStopDelaySecs = storedStopDelay > 0 ? storedStopDelay : 5
        self.preferredSettingsTab = 0
        self.vaultMeetingsPath = defaults.string(forKey: "vaultMeetingsPath") ?? NSString("~/Documents/HushScribe/Meetings").expandingTildeInPath
        self.vaultVoicePath = defaults.string(forKey: "vaultVoicePath") ?? NSString("~/Documents/HushScribe/Voice").expandingTildeInPath
        self.hasAcknowledgedDisclaimer = defaults.bool(forKey: "hasAcknowledgedDisclaimer")
        self.notificationSoundEnabled = defaults.bool(forKey: "notificationSoundEnabled")
        let storedMode = defaults.string(forKey: "mainWindowMode") ?? ""
        self.mainWindowMode = MainWindowMode(rawValue: storedMode) ?? .attached
        // Default to true (hidden) if key has never been set
        if defaults.object(forKey: "hideFromScreenShare") == nil {
            self.hideFromScreenShare = true
        } else {
            self.hideFromScreenShare = defaults.bool(forKey: "hideFromScreenShare")
        }
    }

    /// Resets all settings to their defaults.
    func reset() {
        transcriptionLocale = "en-US"
        inputDeviceID = 0
        silenceTimeoutSeconds = 120
        transcriptionModel = .parakeet
        summaryModel = .appleNL
        summaryTemperature = 0.3
        summaryMaxTokens = 4000
        customSummaryPrompts = [
            CustomSummaryPrompt(name: "", body: ""),
            CustomSummaryPrompt(name: "", body: ""),
            CustomSummaryPrompt(name: "", body: ""),
        ]
        sysVadThreshold = 0.92
        autoMeetingDetect = false
        meetingDetectDelaySecs = 3
        meetingStopDelaySecs = 5
        vaultMeetingsPath = NSString("~/Documents/HushScribe/Meetings").expandingTildeInPath
        vaultVoicePath = NSString("~/Documents/HushScribe/Voice").expandingTildeInPath
        hasAcknowledgedDisclaimer = false
        mainWindowMode = .attached
        hideFromScreenShare = true
        notificationSoundEnabled = false
    }

    /// Apply current screen-share visibility to all app windows.
    func applyScreenShareVisibility() {
        let type: NSWindow.SharingType = hideFromScreenShare ? .none : .readOnly
        for window in NSApp.windows {
            window.sharingType = type
        }
    }

    var vaultMeetingsURL: URL? {
        guard !vaultMeetingsPath.isEmpty else { return nil }
        return URL(fileURLWithPath: vaultMeetingsPath)
    }

    var vaultVoiceURL: URL? {
        guard !vaultVoicePath.isEmpty else { return nil }
        return URL(fileURLWithPath: vaultVoicePath)
    }

    var locale: Locale {
        Locale(identifier: transcriptionLocale)
    }
}
