import Observation

@Observable
@MainActor
final class RecordingState {
    var isRecording = false
    var isPaused = false
}
