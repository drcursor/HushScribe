import SwiftUI

struct WaveformView: View {
    let isRecording: Bool
    let audioLevel: Float

    var body: some View {
        if isRecording {
            VUMeter(audioLevel: audioLevel)
                .frame(height: 28)
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

private let barCount = 28
private let segmentCount = 5

// Bell curve weights — center bars taller, edges shorter
private let positionCurve: [Float] = (0..<barCount).map { i in
    let x = (Float(i) - Float(barCount - 1) / 2) / (Float(barCount) / 4)
    return exp(-x * x / 2)
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

    @State private var barOffsets: [Float] = []
    @State private var barHeights: [CGFloat] = Array(repeating: 0, count: barCount)
    @State private var peakSegments: [Int] = Array(repeating: -1, count: barCount)
    @State private var peakTimers: [Int] = Array(repeating: 0, count: barCount)

    private var glowLevel: CGFloat { CGFloat(min(audioLevel * 1.4, 1.0)) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
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
        .padding(.horizontal, 12)
        .drawingGroup()
        .shadow(color: Color(red: 0.05, green: 0.92, blue: 0.22).opacity(glowLevel * 0.5), radius: glowLevel * 6)
        .onAppear {
            barOffsets = (0..<barCount).map { _ in Float.random(in: -0.12...0.12) }
        }
        .onChange(of: audioLevel) {
            updateBars()
        }
    }

    private func updateBars() {
        let level = CGFloat(audioLevel)

        for i in 0..<barCount {
            barOffsets[i] = Float.random(in: -0.12...0.12)
        }

        var newHeights = [CGFloat](repeating: 0, count: barCount)
        for i in 0..<barCount {
            let curve = CGFloat(positionCurve[i])
            let jitter = CGFloat(1.0 + barOffsets[i])
            newHeights[i] = level * curve * jitter * 13
        }

        // Peak hold per bar (as segment index from top)
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
