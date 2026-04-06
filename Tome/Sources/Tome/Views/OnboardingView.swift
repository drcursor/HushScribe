import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentStep = 0
    @State private var arrowOpacity: Double = 1

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
            "Auto-Record Meetings (Experimental)",
            "Enable \"Auto-record meetings\" from the menu bar. HushScribe watches for Zoom, Teams, Slack, and other conferencing apps — recording starts only when a call is actually in progress (mic active), and stops when the call ends. This feature is experimental and may not work reliably in all setups."
        ),
        (
            "menubar.rectangle",
            "Lives in Your Menu Bar",
            "HushScribe runs quietly in the background. Use \"Show HushScribe\" from the menu bar icon any time to bring this window back."
        ),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Spacer()

                // Icon
                Image(systemName: steps[currentStep].icon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.accent1)
                    .frame(height: 52)
                    .id(currentStep) // force transition on change

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
                    Button("Skip") {
                        finish()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                    Spacer()

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
                            .background(Color.accent1, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
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
    }

    private func finish() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPresented = false
        }
    }
}
