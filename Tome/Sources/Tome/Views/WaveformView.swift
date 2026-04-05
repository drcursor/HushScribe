import SwiftUI

struct WaveformView: View {
    let isRecording: Bool
    let micLevel: Float
    let sysLevel: Float

    var body: some View {
        if isRecording {
            HStack(spacing: 0) {
                // Mic meter
                VStack(spacing: 2) {
                    VUMeter(audioLevel: micLevel, barCount: 13)
                        .frame(height: 24)
                    Text("MIC")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.fg3.opacity(0.6))
                }

                // Divider
                Rectangle()
                    .fill(Color.fg2.opacity(0.15))
                    .frame(width: 1)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 4)

                // System audio meter
                VStack(spacing: 2) {
                    VUMeter(audioLevel: sysLevel, barCount: 13)
                        .frame(height: 24)
                    Text("SYSTEM")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.fg3.opacity(0.6))
                }
            }
            .clipped()
        } else {
            Rectangle()
                .fill(Color.fg2.opacity(0.35))
                .frame(height: 1)
                .padding(.horizontal, 16)
                .frame(height: 28)
        }
    }
}

private let segmentCount = 5

// Bell curve weights — center bars taller, edges shorter
private func positionCurve(barCount: Int) -> [Float] {
    (0..<barCount).map { i in
        let x = (Float(i) - Float(barCount - 1) / 2) / (Float(barCount) / 4)
        return exp(-x * x / 2)
    }
}

// Color per segment index (0 = top, segmentCount-1 = bottom)
private func segmentColor(index: Int) -> Color {
    if index == 0 {
        return Color(red: 1.0, green: 0.15, blue: 0.05)   // red (top)
    } else if index == 1 {
        return Color(red: 0.95, green: 0.78, blue: 0.0)   // yellow
    } else {
        return Color(red: 0.05, green: 0.92, blue: 0.22)  // green (bottom)
    }
}

private struct VUMeter: View {
    let audioLevel: Float
    let barCount: Int

    @State private var barOffsets: [Float] = []
    @State private var barHeights: [CGFloat] = []
    @State private var peakSegments: [Int] = []
    @State private var peakTimers: [Int] = []

    private var glowLevel: CGFloat { CGFloat(min(audioLevel * 1.4, 1.0)) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                if i < barHeights.count {
                    VStack(spacing: 1) {
                        ForEach(0..<segmentCount, id: \.self) { seg in
                            let litCount = Int((barHeights[i] / 13.0) * CGFloat(segmentCount) + 0.5)
                            let isLit = (segmentCount - 1 - seg) < litCount
                            let isPeak = peakSegments[i] == seg
                            let color = segmentColor(index: seg)
                            Rectangle()
                                .fill(isLit || isPeak ? color : color.opacity(0.08))
                                .frame(height: 4)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .drawingGroup()
        .shadow(color: Color(red: 0.05, green: 0.92, blue: 0.22).opacity(glowLevel * 0.5), radius: glowLevel * 6)
        .onAppear {
            barOffsets = (0..<barCount).map { _ in Float.random(in: -0.12...0.12) }
            barHeights = Array(repeating: 0, count: barCount)
            peakSegments = Array(repeating: -1, count: barCount)
            peakTimers = Array(repeating: 0, count: barCount)
        }
        .onChange(of: audioLevel) {
            updateBars()
        }
    }

    private func updateBars() {
        guard barHeights.count == barCount else { return }
        let level = CGFloat(audioLevel)
        let curve = positionCurve(barCount: barCount)

        for i in 0..<barCount {
            barOffsets[i] = Float.random(in: -0.12...0.12)
        }

        var newHeights = [CGFloat](repeating: 0, count: barCount)
        for i in 0..<barCount {
            let c = CGFloat(curve[i])
            let jitter = CGFloat(1.0 + barOffsets[i])
            newHeights[i] = level * c * jitter * 13
        }

        var newPeaks = peakSegments
        var newTimers = peakTimers
        for i in 0..<barCount {
            let litCount = Int((newHeights[i] / 13.0) * CGFloat(segmentCount) + 0.5)
            let topLitSeg = litCount > 0 ? segmentCount - litCount : -1

            if topLitSeg >= 0 && (newPeaks[i] < 0 || topLitSeg <= newPeaks[i]) {
                newPeaks[i] = topLitSeg
                newTimers[i] = 4
            } else if newTimers[i] > 0 {
                newTimers[i] -= 1
            } else if newPeaks[i] >= 0 {
                newPeaks[i] = newPeaks[i] + 1
                if newPeaks[i] >= segmentCount { newPeaks[i] = -1 }
            }
        }

        peakSegments = newPeaks
        peakTimers = newTimers

        withAnimation(.easeOut(duration: 0.08)) {
            barHeights = newHeights
        }
    }
}
