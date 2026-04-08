import AppKit
import Foundation
import Observation
import CoreAudio

enum SessionType: String {
    case callCapture
    case voiceMemo
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
        let storedThreshold = defaults.double(forKey: "sysVadThreshold")
        self.sysVadThreshold = storedThreshold > 0 ? storedThreshold : 0.92
        self.autoMeetingDetect = defaults.bool(forKey: "autoMeetingDetect")
        let storedDelay = defaults.integer(forKey: "meetingDetectDelaySecs")
        self.meetingDetectDelaySecs = storedDelay > 0 ? storedDelay : 3
        self.vaultMeetingsPath = defaults.string(forKey: "vaultMeetingsPath") ?? NSString("~/Documents/HushScribe/Meetings").expandingTildeInPath
        self.vaultVoicePath = defaults.string(forKey: "vaultVoicePath") ?? NSString("~/Documents/HushScribe/Voice").expandingTildeInPath
        // Default to true (hidden) if key has never been set
        if defaults.object(forKey: "hideFromScreenShare") == nil {
            self.hideFromScreenShare = true
        } else {
            self.hideFromScreenShare = defaults.bool(forKey: "hideFromScreenShare")
        }
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
