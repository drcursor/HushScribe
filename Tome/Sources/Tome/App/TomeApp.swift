import SwiftUI
import AppKit
import Sparkle

@main
struct TomeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var settings = AppSettings()
    @State private var recordingState = RecordingState()
    private let updaterController = AppUpdaterController()

    var body: some Scene {
        WindowGroup {
            ContentView(settings: settings, recordingState: recordingState)
                .onAppear {
                    settings.applyScreenShareVisibility()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 320, height: 560)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
        Settings {
            SettingsView(settings: settings, updater: updaterController.updater)
        }
        MenuBarExtra {
            Text("Tome")
                .font(.headline)
            Divider()
            if !recordingState.isRecording {
                Button("Start Call Capture") {
                    NotificationCenter.default.post(name: .tomeStartCallCapture, object: nil)
                }
                Button("Start Voice Memo") {
                    NotificationCenter.default.post(name: .tomeStartVoiceMemo, object: nil)
                }
            } else {
                if recordingState.isPaused {
                    Button("Resume Recording") {
                        NotificationCenter.default.post(name: .tomeResumeRecording, object: nil)
                    }
                } else {
                    Button("Pause Recording") {
                        NotificationCenter.default.post(name: .tomePauseRecording, object: nil)
                    }
                }
                Button("Stop Recording") {
                    NotificationCenter.default.post(name: .tomeStopRecording, object: nil)
                }
            }
            Divider()
            Button("Quit Tome") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
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
            return "book.closed"
        }
    }
}

/// Observes new window creation and applies screen-share visibility setting.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
    }
}
