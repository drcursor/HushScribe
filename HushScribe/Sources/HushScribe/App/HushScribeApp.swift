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
                transcriptionEngine: transcriptionEngine,
                meetingMonitor: meetingMonitor
            )
            .background(
                SettingsBridge { action in
                    appDelegate.statusBarController.setOpenSettings(action)
                }
            )
            .onAppear {
                settings.applyScreenShareVisibility()
                meetingMonitor.configure(settings: settings, recordingState: recordingState)
                appDelegate.statusBarController.setup(
                    settings: settings,
                    recordingState: recordingState,
                    meetingMonitor: meetingMonitor,
                    transcriptStore: transcriptStore,
                    transcriptionEngine: transcriptionEngine
                )
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 480, height: 480)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) { }
        }
        Settings {
            SettingsView(settings: settings, engine: transcriptionEngine)
        }
    }
}

/// Captures the SwiftUI openSettings environment action and forwards it to an AppKit caller.
private struct SettingsBridge: View {
    @Environment(\.openSettings) private var openSettings
    var onCapture: (@escaping () -> Void) -> Void

    var body: some View {
        Color.clear
            .onAppear { onCapture { openSettings() } }
    }
}

/// Observes new window creation and applies screen-share visibility setting.
/// Also hides the main window on launch for returning users (app lives in menu bar).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusBarController = StatusBarController()
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
