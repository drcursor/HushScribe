import SwiftUI
import AVFoundation
import Speech
import CoreGraphics

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @Bindable var settings: AppSettings
    @State private var currentStep = 0
    @State private var arrowOpacity: Double = 1
    @State private var micGranted = false
    @State private var screenGranted = false
    @State private var speechGranted = false
    @State private var disclaimerAcknowledged = false

    private let steps: [(icon: String, title: String, body: String)] = [
        (
            "waveform.circle",
            "Welcome to HushScribe",
            "A lightweight meeting transcription tool that captures your conversations — all running locally on your Mac. No API keys, no cloud services."
        ),
        (
            "text.quote",
            "Live Transcript",
            "Your conversation is transcribed in real time. \"You\" captures your mic, \"Them\" captures system audio from the other side. The transcript is the primary view — clean and full-window."
        ),
        (
            "waveform.badge.plus",
            "Auto-Record Meetings",
            "Enable \"Auto-record meetings\" from the menu bar. HushScribe watches for Zoom, Teams, Slack, and other conferencing apps — recording starts only when a call is actually in progress (mic active), and stops when the call ends. Note: browser-based meetings (e.g. Google Meet or Teams in a web browser) are not detected."
        ),
        (
            "sparkles",
            "AI Summaries",
            "After a session, open the Transcript Viewer and click \"Generate Summary\" to get highlights and action items from your transcript. All models run on-device — no internet required. Download Qwen3, Gemma 3, or Gemma 4 in Settings → Models for best results."
        ),
        (
            "lock.shield",
            "Permissions",
            "HushScribe needs a few permissions to work. Click each one to grant access."
        ),
        (
            "exclamationmark.shield",
            "Legal Disclaimer",
            "Recording laws vary by jurisdiction. In many places, all parties must consent before a conversation may be recorded. It is your sole responsibility to ensure you comply with applicable local laws before using HushScribe to record any conversation."
        ),
        (
            "menubar.rectangle",
            "Lives in Your Menu Bar",
            "HushScribe runs quietly in the background. Use \"Show HushScribe\" from the menu bar icon any time to bring this window back."
        ),
    ]

    private let permissionsStepIndex = 4
    private let disclaimerStepIndex = 5

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Spacer()

                // Icon
                if currentStep == 0 {
                    if let svgURL = Bundle.main.url(forResource: "logo", withExtension: "svg"),
                       let svgImage = NSImage(contentsOf: svgURL) {
                        Image(nsImage: svgImage)
                            .resizable()
                            .renderingMode(.template)
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .foregroundStyle(Color.accent1)
                            .id(currentStep)
                    } else {
                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .id(currentStep)
                    }
                } else {
                    Image(systemName: steps[currentStep].icon)
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color.accent1)
                        .frame(height: 52)
                        .id(currentStep)
                }

                Spacer().frame(height: 20)

                // Title
                Text(steps[currentStep].title)
                    .font(.system(size: 16, weight: .semibold))
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 10)

                // Body
                Text(steps[currentStep].body)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if currentStep == 2 {
                    Spacer().frame(height: 16)
                    Toggle("Enable auto-record meetings", isOn: $settings.autoMeetingDetect)
                        .font(.system(size: 13, weight: .medium))
                        .toggleStyle(.switch)
                        .frame(maxWidth: 260)
                }

                if currentStep == disclaimerStepIndex {
                    Spacer().frame(height: 16)
                    Button {
                        disclaimerAcknowledged.toggle()
                        settings.hasAcknowledgedDisclaimer = disclaimerAcknowledged
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: disclaimerAcknowledged ? "checkmark.square.fill" : "square")
                                .font(.system(size: 16))
                                .foregroundStyle(disclaimerAcknowledged ? Color.accent1 : .secondary)
                            Text("I understand it's my sole responsibility to comply with local recording laws")
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: 300, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }

                if currentStep == permissionsStepIndex {
                    Spacer().frame(height: 16)
                    VStack(spacing: 8) {
                        PermissionRow(
                            icon: "mic",
                            label: "Microphone",
                            reason: "Captures your voice during recording sessions.",
                            granted: micGranted,
                            action: requestMic
                        )
                        PermissionRow(
                            icon: "rectangle.inset.filled.on.rectangle",
                            label: "Screen Recording",
                            reason: "Captures system audio from Teams, Zoom, and other apps.",
                            granted: screenGranted,
                            action: requestScreen
                        )
                        PermissionRow(
                            icon: "waveform",
                            label: "Speech Recognition",
                            reason: "Required only when using the Apple Speech transcription model.",
                            granted: speechGranted,
                            action: requestSpeech
                        )
                    }
                }

                Spacer()

                // Dots
                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentStep ? Color.accent1 : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.bottom, 20)

                // Buttons
                HStack {
                    Spacer()

                    let isDisclaimerBlocked = currentStep == disclaimerStepIndex && !disclaimerAcknowledged
                    Button {
                        if currentStep < steps.count - 1 {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                currentStep += 1
                            }
                        } else {
                            finish()
                        }
                    } label: {
                        Text(currentStep < steps.count - 1 ? "Next" : "Get Started")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(isDisclaimerBlocked ? Color.accent1.opacity(0.35) : Color.accent1, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(isDisclaimerBlocked)
                }
            }
            .padding(28)

            // Arrow pointing to the menu bar icon — shown on the last step
            if currentStep == steps.count - 1 {
                VStack(spacing: 3) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.accent1)
                    Text("menu bar")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.accent1)
                }
                .opacity(arrowOpacity)
                .padding(.top, 10)
                .padding(.trailing, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .onAppear {
                    arrowOpacity = 1
                    Task {
                        for _ in 0..<2 {
                            try? await Task.sleep(for: .milliseconds(200))
                            withAnimation(.easeInOut(duration: 0.6)) { arrowOpacity = 0 }
                            try? await Task.sleep(for: .milliseconds(600))
                            withAnimation(.easeInOut(duration: 0.6)) { arrowOpacity = 1 }
                            try? await Task.sleep(for: .milliseconds(600))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg0)
        .onAppear {
            refreshStatuses()
            disclaimerAcknowledged = settings.hasAcknowledgedDisclaimer
        }
        .onChange(of: currentStep) { _, step in
            if step == permissionsStepIndex { refreshStatuses() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if currentStep == permissionsStepIndex { refreshStatuses() }
        }
    }

    private func refreshStatuses() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        screenGranted = CGPreflightScreenCaptureAccess()
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    private func requestMic() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micGranted = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { micGranted = granted }
            }
        default:
            openSettings("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone")
        }
    }

    private func requestScreen() {
        // CGRequestScreenCaptureAccess only shows a banner on modern macOS; always open
        // Settings so the user can actually toggle the permission on.
        CGRequestScreenCaptureAccess()
        openSettings("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")
    }

    private func requestSpeech() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechGranted = true
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async { speechGranted = status == .authorized }
            }
        default:
            openSettings("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_SpeechRecognition")
        }
    }

    private func openSettings(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func finish() {
        isPresented = false
        NSApp.windows.first { !($0 is NSPanel) && $0.level == .normal }?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct PermissionRow: View {
    let icon: String
    let label: String
    let reason: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(granted ? .green : .primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if granted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 14))
                } else {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
