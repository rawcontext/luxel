public final class InMemoryRecordingHistoryStore: RecordingHistoryStore, @unchecked Sendable {
    public var activeRecording: ActiveRecording?
    public var recordings: [PastRecording]

    public init(activeRecording: ActiveRecording? = nil, recordings: [PastRecording] = []) {
        self.activeRecording = activeRecording
        self.recordings = recordings
    }
}
