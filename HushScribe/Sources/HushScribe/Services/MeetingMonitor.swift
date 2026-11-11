import AppKit
import CoreAudio
import Foundation
import Observation

/// Detects meetings from input I/O attributed to a watched conferencing app.
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

    /// True when a watched app is capturing audio input.
    private(set) var isMeetingActive = false

    private weak var settings: AppSettings?
    private weak var recordingState: RecordingState?
    private var configured = false

    // Tasks
    private var pollingTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?

    // MARK: - Setup

    /// Call once at app startup. Safe to call multiple times.
    func configure(settings: AppSettings, recordingState: RecordingState) {
        guard !configured else { return }
        configured = true
        self.settings = settings
        self.recordingState = recordingState

        startPolling()
    }

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
        guard let active = Self.watchedAppUsingInput(), active != isMeetingActive else { return }
        isMeetingActive = active
        if active {
            stopTask?.cancel()
            considerStarting()
        } else {
            startTask?.cancel()
            considerStopping()
        }
    }

    // MARK: - Start / stop logic

    private func considerStarting() {
        guard let settings, let recordingState,
              settings.autoMeetingDetect,
              isMeetingActive,
              !recordingState.isRecording else { return }

        let delaySecs = settings.meetingDetectDelaySecs
        startTask?.cancel()
        startTask = Task {
            if delaySecs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delaySecs) * 1_000_000_000)
            }
            guard !Task.isCancelled, settings.autoMeetingDetect,
                  Self.watchedAppUsingInput() == true,
                  !recordingState.isRecording else { return }
            NotificationCenter.default.post(name: .hushscribeStartCallCapture, object: nil)
        }
    }

    private func considerStopping() {
        guard let settings, let recordingState,
              settings.autoMeetingDetect,
              recordingState.isRecording else { return }

        let stopDelaySecs = settings.meetingStopDelaySecs
        stopTask?.cancel()
        stopTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(stopDelaySecs) * 1_000_000_000)
            guard !Task.isCancelled, settings.autoMeetingDetect, recordingState.isRecording,
                  Self.watchedAppUsingInput() == false else { return }
            NotificationCenter.default.post(name: .hushscribeStopRecording, object: nil)
        }
    }

    // A failed list read is inconclusive (for example, a process exited mid-query).
    private static func watchedAppUsingInput() -> Bool? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = propertyAddress(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
            return nil
        }
        let stride = MemoryLayout<AudioObjectID>.stride
        guard size > 0 else { return false }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / stride)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else {
            return nil
        }
        return processes.prefix(Int(size) / stride).contains { process in
            var running: UInt32 = 0
            var bytes = UInt32(MemoryLayout.size(ofValue: running))
            var input = propertyAddress(kAudioProcessPropertyIsRunningInput)
            guard AudioObjectGetPropertyData(process, &input, 0, nil, &bytes, &running) == noErr,
                  running != 0 else { return false }

            var bundle: Unmanaged<CFString>?
            bytes = UInt32(MemoryLayout.size(ofValue: bundle))
            var bundleID = propertyAddress(kAudioProcessPropertyBundleID)
            guard AudioObjectGetPropertyData(process, &bundleID, 0, nil, &bytes, &bundle) == noErr,
                  let id = bundle?.takeRetainedValue() as String? else { return false }
            // Electron apps may capture through a helper with a child bundle identifier.
            return watchedApps.keys.contains { id == $0 || id.hasPrefix($0 + ".") }
        }
    }

    private static func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
