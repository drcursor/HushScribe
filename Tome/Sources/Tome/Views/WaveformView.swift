import SwiftUI

struct WaveformView: View {
    let isRecording: Bool

    var body: some View {
        if isRecording {
            AnimatedWave()
                .frame(height: 28)
        } else {
            Rectangle()
                .fill(Color.fg2.opacity(0.35))
                .frame(height: 1)
                .padding(.horizontal, 16)
                .frame(height: 28)
        }
    }
}

private struct AnimatedWave: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        WavePath(phase: phase)
            .stroke(Color.accent1, lineWidth: 2)
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

private struct WavePath: Shape {
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = rect.midY
        let amplitude: CGFloat = 8
        let wavelength: CGFloat = 40
        path.move(to: CGPoint(x: 0, y: mid))
        for x in stride(from: CGFloat(0), through: rect.width, by: 2) {
            let y = mid + amplitude * sin((x / wavelength + phase * 2.5) * .pi * 2)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}
