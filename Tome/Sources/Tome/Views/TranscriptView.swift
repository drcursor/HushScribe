import SwiftUI

struct TranscriptView: View {
    let utterances: [Utterance]
    let volatileYouText: String
    let volatileThemText: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(utterances) { utterance in
                        UtteranceBubble(utterance: utterance)
                            .id(utterance.id)
                    }

                    if !volatileYouText.isEmpty {
                        VolatileIndicator(text: volatileYouText, speaker: .you)
                            .id("volatile-you")
                    }

                    if !volatileThemText.isEmpty {
                        VolatileIndicator(text: volatileThemText, speaker: .them)
                            .id("volatile-them")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .onChange(of: utterances.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    if let last = utterances.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: volatileYouText) {
                proxy.scrollTo("volatile-you", anchor: .bottom)
            }
            .onChange(of: volatileThemText) {
                proxy.scrollTo("volatile-them", anchor: .bottom)
            }
        }
    }
}

// MARK: - Chat Bubble

private struct UtteranceBubble: View {
    let utterance: Utterance

    private var accentColor: Color {
        utterance.speaker == .you ? .accent1 : .fg2
    }

    var body: some View {
        HStack {
            if utterance.speaker == .you { Spacer() }

            VStack(alignment: .leading, spacing: 4) {
                Text(utterance.speaker == .you ? "You" : "Them")
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(accentColor)

                Text(utterance.text)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.fg1)
                    .textSelection(.enabled)

                Text(utterance.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 10))
                    .foregroundStyle(Color.fg3)
            }
            .padding(10)
            .frame(maxWidth: 260, alignment: .leading)
            .background(Color.bg1.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06)))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)
                    .fill(accentColor)
                    .frame(width: 3)
            }

            if utterance.speaker == .them { Spacer() }
        }
    }
}

// MARK: - Volatile Indicator

private struct VolatileIndicator: View {
    let text: String
    let speaker: Speaker
    @State private var pulse = false

    private var accentColor: Color {
        speaker == .you ? .accent1 : .fg2
    }

    var body: some View {
        HStack {
            if speaker == .you { Spacer() }

            HStack(spacing: 4) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.fg3)
                Circle()
                    .fill(Color.accent1)
                    .frame(width: 4, height: 4)
            }
            .padding(10)
            .frame(maxWidth: 260, alignment: .leading)
            .background(Color.bg1.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06)))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)
                    .fill(accentColor)
                    .frame(width: 3)
            }
            .opacity(pulse ? 0.6 : 0.35)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }

            if speaker == .them { Spacer() }
        }
    }
}

// MARK: - Design Tokens

extension Color {
    // Backgrounds — warm
    static let bg0 = Color(red: 0.10, green: 0.09, blue: 0.09)   // #1A1818
    static let bg1 = Color(red: 0.18, green: 0.17, blue: 0.16)   // #2E2B29 (glass base)
    static let bg2 = Color(red: 0.14, green: 0.13, blue: 0.12)   // #242120

    // Foregrounds — warm cream
    static let fg1 = Color(red: 0.94, green: 0.93, blue: 0.91)   // #F0EDE8
    static let fg2 = Color(red: 0.54, green: 0.52, blue: 0.50)   // #8A8480
    static let fg3 = Color(red: 0.36, green: 0.34, blue: 0.33)   // #5C5854

    // Accent — lavender
    static let accent1 = Color(red: 0.77, green: 0.63, blue: 1.0) // #C4A0FF
    static let accent2 = Color(red: 0.58, green: 0.47, blue: 0.75)// dimmer

    // Recording red
    static let recordRed = Color(red: 0.91, green: 0.36, blue: 0.36) // #E85B5B
}
