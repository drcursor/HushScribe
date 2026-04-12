import AppKit
import SwiftUI

/// Manages the status bar item and handles both standard (menu) and attached (popover) modes.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var closePopoverObserver: Any?
    private var openSettingsAction: (() -> Void)?
    private weak var mainWindow: NSWindow?

    func setOpenSettings(_ action: @escaping () -> Void) {
        openSettingsAction = action
    }

    // State references — set once in setup()
    private var settings: AppSettings?
    private var recordingState: RecordingState?
    private var meetingMonitor: MeetingMonitor?
    private var transcriptStore: TranscriptStore?
    private var transcriptionEngine: TranscriptionEngine?

    func setup(
        settings: AppSettings,
        recordingState: RecordingState,
        meetingMonitor: MeetingMonitor,
        transcriptStore: TranscriptStore,
        transcriptionEngine: TranscriptionEngine
    ) {
        guard statusItem == nil else { return }

        self.settings = settings
        self.recordingState = recordingState
        self.meetingMonitor = meetingMonitor
        self.transcriptStore = transcriptStore
        self.transcriptionEngine = transcriptionEngine

        mainWindow = NSApp.keyWindow ?? NSApp.windows.first(where: { !($0 is NSPanel) && $0.level == .normal })
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()
        applyMode(settings.mainWindowMode)

        closePopoverObserver = NotificationCenter.default.addObserver(
            forName: .hushscribeClosePopover,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.popover?.performClose(nil)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .hushscribeShowOnboarding,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.showMainWindow()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      window === self.mainWindow,
                      self.settings?.mainWindowMode == .detached else { return }
                self.settings?.mainWindowMode = .attached
            }
        }

        observeIcon()
        observeMode()
    }

    func updateIcon() {
        guard let button = statusItem?.button else { return }

        let iconSize = NSSize(width: 18, height: 18)
        if let svgURL = Bundle.main.url(forResource: "logo", withExtension: "svg"),
           let svgImage = NSImage(contentsOf: svgURL) {
            svgImage.size = iconSize
            if recordingState?.isPaused == true {
                button.image = logoTinted(svgImage, color: .systemOrange)
            } else if recordingState?.isRecording == true {
                button.image = logoTinted(svgImage, color: .systemRed)
            } else {
                svgImage.isTemplate = true
                button.image = svgImage
            }
        } else {
            // Fallback to SF Symbols if logo.svg is unavailable
            let name: String
            if recordingState?.isPaused == true {
                name = "pause.circle.fill"
            } else if recordingState?.isRecording == true {
                name = "record.circle.fill"
            } else {
                name = "quote.bubble"
            }
            button.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
    }

    private func logoTinted(_ image: NSImage, color: NSColor) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        color.withAlphaComponent(0.85).setFill()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        result.unlockFocus()
        return result
    }

    private func applyMode(_ mode: MainWindowMode) {
        guard let statusItem else { return }
        switch mode {
        case .attached:
            statusItem.menu = nil
            statusItem.button?.target = self
            statusItem.button?.action = #selector(statusButtonClicked)
        case .detached:
            statusItem.button?.action = nil
            statusItem.button?.target = nil
            let menu = NSMenu()
            menu.delegate = self
            statusItem.menu = menu
            popover?.performClose(nil)
            popover = nil
        }
    }

    private func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideMainWindow() {
        mainWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    private var onboardingComplete: Bool {
        UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }

    @objc private func statusButtonClicked() {
        guard onboardingComplete else { return }
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
        } else {
            openPopover(relativeTo: button)
        }
    }

    private func openPopover(relativeTo button: NSButton) {
        guard let settings, let recordingState, let transcriptStore, let transcriptionEngine else { return }

        if popover == nil {
            guard let meetingMonitor else { return }
            let contentView = ContentView(
                settings: settings,
                recordingState: recordingState,
                transcriptStore: transcriptStore,
                transcriptionEngine: transcriptionEngine,
                meetingMonitor: meetingMonitor,
                openSettingsOverride: { [weak self] in
                    guard let self else { return }
                    let action = self.openSettingsAction
                    self.popover?.performClose(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        action?()
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            )
            let hosting = NSHostingController(rootView: contentView)
            hosting.sizingOptions = []
            let p = NSPopover()
            p.contentSize = NSSize(width: 480, height: 460)
            p.contentViewController = hosting
            p.behavior = .transient
            popover = p
        }

        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        guard onboardingComplete else { return }
        buildMenuItems(into: menu)
    }

    private func buildMenuItems(into menu: NSMenu) {
        guard let settings, let recordingState, let meetingMonitor else { return }

        let title = NSMenuItem(title: "HushScribe", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        menu.addItem(makeItem("Show HushScribe", action: #selector(showHushScribe)))
        menu.addItem(makeItem("Hide HushScribe", action: #selector(hideHushScribe)))
        menu.addItem(.separator())

        if !recordingState.isRecording {
            menu.addItem(makeItem("Start Call Capture", action: #selector(startCallCapture)))
            menu.addItem(makeItem("Start Voice Memo", action: #selector(startVoiceMemo)))
        } else {
            if recordingState.isPaused {
                menu.addItem(makeItem("Resume Recording", action: #selector(resumeRecording)))
            } else {
                menu.addItem(makeItem("Pause Recording", action: #selector(pauseRecording)))
            }
            menu.addItem(makeItem("Stop Recording", action: #selector(stopRecording)))
        }
        menu.addItem(.separator())

        let autoItem = makeItem("Auto-record meetings", action: #selector(toggleAutoMeetings))
        autoItem.state = settings.autoMeetingDetect ? .on : .off
        menu.addItem(autoItem)
        if settings.autoMeetingDetect && meetingMonitor.isMeetingActive {
            let detectedItem = NSMenuItem(title: "Meeting detected", action: nil, keyEquivalent: "")
            detectedItem.isEnabled = false
            menu.addItem(detectedItem)
        }
        menu.addItem(.separator())

        menu.addItem(makeItem("Transcript Viewer…", action: #selector(openTranscriptViewer)))
        menu.addItem(.separator())

        let settingsItem = makeItem("Settings...", action: #selector(openSettingsMenu))
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = makeItem("Quit HushScribe", action: #selector(quitApp))
        quitItem.keyEquivalent = "q"
        menu.addItem(quitItem)
    }

    private func makeItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Menu Actions

    @objc private func showHushScribe() {
        NSApp.setActivationPolicy(.regular)
        if let existing = NSApp.windows.first(where: { !($0 is NSPanel) && $0.level == .normal }) {
            existing.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func hideHushScribe() {
        NSApp.windows.first { $0.isVisible && !($0 is NSPanel) && $0.level == .normal }?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func startCallCapture() {
        NotificationCenter.default.post(name: .hushscribeStartCallCapture, object: nil)
    }

    @objc private func startVoiceMemo() {
        NotificationCenter.default.post(name: .hushscribeStartVoiceMemo, object: nil)
    }

    @objc private func pauseRecording() {
        NotificationCenter.default.post(name: .hushscribePauseRecording, object: nil)
    }

    @objc private func resumeRecording() {
        NotificationCenter.default.post(name: .hushscribeResumeRecording, object: nil)
    }

    @objc private func stopRecording() {
        NotificationCenter.default.post(name: .hushscribeStopRecording, object: nil)
    }

    @objc private func toggleAutoMeetings() {
        settings?.autoMeetingDetect.toggle()
    }

    @objc private func openTranscriptViewer() {
        NotificationCenter.default.post(name: .hushscribeOpenSummarize, object: nil)
    }

    @objc private func openSettingsMenu() {
        openSettingsAction?()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Observation

    private func observeIcon() {
        withObservationTracking {
            _ = recordingState?.isRecording
            _ = recordingState?.isPaused
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateIcon()
                self?.observeIcon()
            }
        }
    }

    private func observeMode() {
        withObservationTracking {
            _ = settings?.mainWindowMode
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let mode = self.settings?.mainWindowMode else { return }
                self.applyMode(mode)
                switch mode {
                case .detached: self.showMainWindow()
                case .attached: self.hideMainWindow()
                }
                self.observeMode()
            }
        }
    }
}
