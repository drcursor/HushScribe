import Foundation
import Observation

@Observable
@MainActor
final class RecordingState {
    var isRecording = false
    var isPaused = false
}

extension Notification.Name {
    static let hushscribeStartCallCapture = Notification.Name("hushscribeStartCallCapture")
    static let hushscribeStartVoiceMemo = Notification.Name("hushscribeStartVoiceMemo")
    static let hushscribeStopRecording = Notification.Name("hushscribeStopRecording")
    static let hushscribePauseRecording = Notification.Name("hushscribePauseRecording")
    static let hushscribeResumeRecording = Notification.Name("hushscribeResumeRecording")
    static let hushscribeOpenSummarize = Notification.Name("hushscribeOpenSummarize")
    static let hushscribeClosePopover = Notification.Name("hushscribeClosePopover")
    static let hushscribeShowOnboarding = Notification.Name("hushscribeShowOnboarding")
}
