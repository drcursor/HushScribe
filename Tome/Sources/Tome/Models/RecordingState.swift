import Foundation
import Observation

@Observable
@MainActor
final class RecordingState {
    var isRecording = false
    var isPaused = false
}

extension Notification.Name {
    static let tomeStartCallCapture = Notification.Name("tomeStartCallCapture")
    static let tomeStartVoiceMemo = Notification.Name("tomeStartVoiceMemo")
    static let tomeStopRecording = Notification.Name("tomeStopRecording")
    static let tomePauseRecording = Notification.Name("tomePauseRecording")
    static let tomeResumeRecording = Notification.Name("tomeResumeRecording")
}
