public protocol RecordingHistoryStore: AnyObject, Sendable {
    var activeRecording: ActiveRecording? { get set }
    var recordings: [PastRecording] { get set }
}
