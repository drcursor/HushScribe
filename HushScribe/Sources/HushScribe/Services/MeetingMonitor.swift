import AppKit
import CoreAudio
import Foundation
import Observation

/// Detects active meetings by combining two signals:
///   1. A watched conferencing app is running (NSWorkspace).
///   2. The default microphone is actively in use (CoreAudio).
///
/// Recording only starts when both are true, preventing false triggers when
/// the meeting app is open but idle (no call in progress).
@Observable
@MainActor
final class MeetingMonitor {

    /// Bundle IDs treated as meeting apps.
    static let watchedApps: [String: String] = [
        "com.microsoft.teams2":       "Teams",
        "com.microsoft.teams":        "Teams",
        "us.zoom.xos":                "Zoom",
        "com.apple.FaceTime":         "FaceTime",
        "com.tinyspeck.slackmacgap":  "Slack",
        "com.cisco.webexmeetingsapp": "Webex",
        "Cisco-Systems.Spark":        "Webex",
        "com.google.meet":            "Google Meet",
        "com.discord":                "Discord",
        "com.loom.desktop":           "Loom",
    ]

    /// True when a watched app is running AND the mic is actively in use.
    private(set) var isMeetingActive = false

    private weak var settings: AppSettings?
    private weak var recordingState: RecordingState?
    private var configured = false

    // NSWorkspace observers
    private var launchObserver: Any?
    private var terminateObserver: Any?

    // State
    private var watchedAppRunning = false
    private var micActive = false
    private var micDeviceID: AudioDeviceID = 0

    // Tasks
    private var pollingTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var triggerBundleID: String?

    // MARK: - Setup

    /// Call once at app startup. Safe to call multiple times.
    func configure(settings: AppSettings, recordingState: RecordingState) {
        guard !configured else { return }
        configured = true
        self.settings = settings
        self.recordingState = recordingState

        watchedAppRunning = Self.anyWatchedAppRunning()
        micDeviceID = Self.defaultInputDeviceID()
        micActive = micDeviceID != 0 && Self.queryMicRunning(micDeviceID)

        installAppObservers()
        startPolling()
        updateMeetingActive()
    }

    // MARK: - Mic polling

    private func startPolling() {
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 s
                guard let self else { return }
                await MainActor.run { self.pollMicState() }
            }
        }
    }

    private func pollMicState() {
        // Re-resolve device ID in case default input changed.
        let deviceID = Self.defaultInputDeviceID()
        if deviceID != micDeviceID { micDeviceID = deviceID }

        let nowActive = deviceID != 0 && Self.queryMicRunning(deviceID)
        guard nowActive != micActive else { return }
        micActive = nowActive
        updateMeetingActive()

        if micActive {
            considerStarting()
        } else {
            considerStopping()
        }
    }

    // MARK: - NSWorkspace observers

    private func installAppObservers() {
        let ws = NSWorkspace.shared.notificationCenter

        launchObserver = ws.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor [weak self] in self?.handleLaunch(bundleID: bundleID) }
        }

        terminateObserver = ws.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor [weak self] in self?.handleTerminate(bundleID: bundleID) }
        }
    }

    private func handleLaunch(bundleID: String?) {
        guard let bundleID, Self.watchedApps[bundleID] != nil else { return }
        watchedAppRunning = true
        updateMeetingActive()
        stopTask?.cancel()
        // Mic may already be active (e.g. FaceTime launched mid-call).
        if micActive { considerStarting() }
    }

    private func handleTerminate(bundleID: String?) {
        guard let bundleID, Self.watchedApps[bundleID] != nil else { return }
        watchedAppRunning = Self.anyWatchedAppRunning()
        updateMeetingActive()
        startTask?.cancel()
        if bundleID == triggerBundleID { considerStopping() }
    }

    // MARK: - Start / stop logic

    private func considerStarting() {
        guard let settings, let recordingState,
              settings.autoMeetingDetect,
              watchedAppRunning, micActive,
              !recordingState.isRecording else { return }

        let delaySecs = settings.meetingDetectDelaySecs
        startTask?.cancel()
        startTask = Task {
            if delaySecs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delaySecs) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                // Re-check after delay — both signals must still be true.
                guard self.watchedAppRunning, self.micActive,
                      !(self.recordingState?.isRecording ?? true) else { return }
            }
            self.triggerBundleID = NSWorkspace.shared.runningApplications
                .first(where: { Self.watchedApps[$0.bundleIdentifier ?? ""] != nil })?
                .bundleIdentifier
            NotificationCenter.default.post(name: .hushscribeStartCallCapture, object: nil)
        }
    }

    private func considerStopping() {
        guard let settings, let recordingState,
              settings.autoMeetingDetect,
              recordingState.isRecording else { return }

        stopTask?.cancel()
        stopTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 s grace
            guard !Task.isCancelled, !self.isMeetingActive else { return }
            self.triggerBundleID = nil
            NotificationCenter.default.post(name: .hushscribeStopRecording, object: nil)
        }
    }

    private func updateMeetingActive() {
        isMeetingActive = watchedAppRunning && micActive
    }

    // MARK: - CoreAudio helpers

    private static func defaultInputDeviceID() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &deviceID
        )
        return deviceID == kAudioDeviceUnknown ? 0 : deviceID
    }

    private static func queryMicRunning(_ deviceID: AudioDeviceID) -> Bool {
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &running)
        return running != 0
    }

    private static func anyWatchedAppRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            guard let id = $0.bundleIdentifier else { return false }
            return watchedApps[id] != nil
        }
    }
}
