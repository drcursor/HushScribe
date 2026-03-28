import SwiftUI

struct PulsingDot: View {
    var size: CGFloat = 10
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(Color.recordRed)
            .frame(width: size, height: size)
            .opacity(pulse ? 1.0 : 0.4)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

struct ControlBar: View {
    let isRecording: Bool
    let activeSessionType: SessionType?
    let audioLevel: Float
    let detectedApp: String?
    let silenceSeconds: Int
    let statusMessage: String?
    let errorMessage: String?
    let onStartCallCapture: () -> Void
    let onStartVoiceMemo: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.recordRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }

            if let status = statusMessage, status != "Ready" {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.accent1)
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.fg2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }

            if isRecording {
                Button(action: onStop) {
                    HStack(spacing: 10) {
                        PulsingDot(size: 6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stop Recording")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.fg1)
                            Text(activeSessionLabel)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.fg2)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.accent1.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accent1.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(".", modifiers: .command)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                if silenceSeconds >= 90 {
                    Text("Silence — auto-stop in \(120 - silenceSeconds)s")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }
            } else {
                HStack(spacing: 10) {
                    Button(action: onStartCallCapture) {
                        HStack(spacing: 6) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.fg1)
                            Text("Call Capture")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.fg1)
                            Text("⌘R")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.fg3)
                        }
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .background(Color.bg1.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("r", modifiers: .command)

                    Button(action: onStartVoiceMemo) {
                        HStack(spacing: 6) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.fg1)
                            Text("Voice Memo")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.fg1)
                            Text("⌘⇧R")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.fg3)
                        }
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .background(Color.bg1.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .background(Color.bg1.opacity(0.45))
        .overlay(Divider(), alignment: .top)
    }

    private var activeSessionLabel: String {
        switch activeSessionType {
        case .callCapture:
            if let app = detectedApp {
                return "Call Capture · \(app)"
            }
            return "Call Capture"
        case .voiceMemo:
            return "Voice Memo"
        case nil:
            return "Recording"
        }
    }
}
