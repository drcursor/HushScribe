import SwiftUI
import AppKit

@main
struct HushScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var settings: AppSettings
    @State private var recordingState: RecordingState
    @State private var meetingMonitor: MeetingMonitor
    @State private var transcriptStore: TranscriptStore
    @State private var transcriptionEngine: TranscriptionEngine

    init() {
        let s = AppSettings()
        let rs = RecordingState()
        let mm = MeetingMonitor()
        let store = TranscriptStore()
        let engine = TranscriptionEngine(transcriptStore: store)
        engine.setModel(s.transcriptionModel)
        _settings = State(wrappedValue: s)
        _recordingState = State(wrappedValue: rs)
        _meetingMonitor = State(wrappedValue: mm)
        _transcriptStore = State(wrappedValue: store)
        _transcriptionEngine = State(wrappedValue: engine)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(
                settings: settings,
                recordingState: recordingState,
                transcriptStore: transcriptStore,
                transcriptionEngine: transcriptionEngine
            )
                .onAppear {
                    settings.applyScreenShareVisibility()
                    meetingMonitor.configure(settings: settings, recordingState: recordingState)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 480, height: 480)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About HushScribe") {
                    let credits = NSAttributedString(
                        string: "A fork of Tome by Gremble-io\nmaintained by drcursor\ngithub.com/drcursor/HushScribe",
                        attributes: [.font: NSFont.systemFont(ofSize: 11)]
                    )
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .credits: credits
                    ])
                }
            }
        }
        Settings {
            SettingsView(settings: settings, engine: transcriptionEngine)
        }
        MenuBarExtra {
            MenuBarMenuView(recordingState: recordingState, settings: settings, meetingMonitor: meetingMonitor)
        } label: {
            Image(systemName: menuBarIconName)
                .symbolRenderingMode(.monochrome)
        }
    }

    private var menuBarIconName: String {
        if recordingState.isPaused {
            return "pause.circle.fill"
        } else if recordingState.isRecording {
            return "record.circle.fill"
        } else {
            return "quote.bubble"
        }
    }
}

// Extracted so it can use @Environment(\.openWindow)
struct MenuBarMenuView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var recordingState: RecordingState
    @Bindable var settings: AppSettings
    var meetingMonitor: MeetingMonitor
    @State private var isWindowVisible = false

    var body: some View {
        Text("HushScribe")
            .font(.headline)
            .onAppear { isWindowVisible = checkWindowVisible() }
        Divider()
        Button("Show HushScribe") {
            NSApp.setActivationPolicy(.regular)
            if let existing = NSApp.windows.first(where: { (w: NSWindow) in !(w is NSPanel) && w.level == .normal }) {
                existing.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: "main")
            }
            NSApp.activate(ignoringOtherApps: true)
            isWindowVisible = true
        }
        Button("Hide HushScribe") {
            NSApp.windows.first { (w: NSWindow) in w.isVisible && !(w is NSPanel) && w.level == .normal }?.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
            isWindowVisible = false
        }
        Divider()
        if !recordingState.isRecording {
            Button("Start Call Capture") {
                NotificationCenter.default.post(name: .hushscribeStartCallCapture, object: nil)
            }
            Button("Start Voice Memo") {
                NotificationCenter.default.post(name: .hushscribeStartVoiceMemo, object: nil)
            }
        } else {
            if recordingState.isPaused {
                Button("Resume Recording") {
                    NotificationCenter.default.post(name: .hushscribeResumeRecording, object: nil)
                }
            } else {
                Button("Pause Recording") {
                    NotificationCenter.default.post(name: .hushscribePauseRecording, object: nil)
                }
            }
            Button("Stop Recording") {
                NotificationCenter.default.post(name: .hushscribeStopRecording, object: nil)
            }
        }
        Divider()
        Button {
            settings.autoMeetingDetect.toggle()
        } label: {
            HStack {
                Text("Auto-record meetings")
                if settings.autoMeetingDetect {
                    Image(systemName: "checkmark")
                }
            }
        }
        if settings.autoMeetingDetect && meetingMonitor.isMeetingActive {
            Text("Meeting detected")
                .foregroundStyle(.secondary)
        }
        Divider()
        Button("Transcript Viewer…") {
            NotificationCenter.default.post(name: .hushscribeOpenSummarize, object: nil)
        }
        Divider()
        Button("Settings...") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Button("About HushScribe") {
            NSApp.orderFrontStandardAboutPanel(options: [
                .credits: NSAttributedString(
                    string: "A fork of Tome by Gremble-io\nmaintained by drcursor\ngithub.com/drcursor/HushScribe",
                    attributes: [.font: NSFont.systemFont(ofSize: 11)]
                )
            ])
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit HushScribe") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func checkWindowVisible() -> Bool {
        NSApp.windows.contains { (w: NSWindow) in w.isVisible && !(w is NSPanel) && w.level == .normal }
    }
}

/// Observes new window creation and applies screen-share visibility setting.
/// Also hides the main window on launch for returning users (app lives in menu bar).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // After first run, app lives in the menu bar — close the main window on launch.
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if hasCompletedOnboarding {
            DispatchQueue.main.async {
                NSApp.windows.forEach { $0.orderOut(nil) }
            }
        }

        let hidden = UserDefaults.standard.object(forKey: "hideFromScreenShare") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "hideFromScreenShare")
        let sharingType: NSWindow.SharingType = hidden ? .none : .readOnly

        for window in NSApp.windows {
            window.sharingType = sharingType
        }

        // Watch for new windows being created (e.g. Settings window)
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                let hide = UserDefaults.standard.object(forKey: "hideFromScreenShare") == nil
                    ? true
                    : UserDefaults.standard.bool(forKey: "hideFromScreenShare")
                let type: NSWindow.SharingType = hide ? .none : .readOnly
                for window in NSApp.windows {
                    window.sharingType = type
                }
            }
        }

        // Hide dock icon when the last normal window is closed
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            DispatchQueue.main.async {
                let hasNormalWindow = NSApp.windows.contains { (w: NSWindow) in
                    w.isVisible && !(w is NSPanel) && w.level == .normal
                }
                if !hasNormalWindow {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
}
