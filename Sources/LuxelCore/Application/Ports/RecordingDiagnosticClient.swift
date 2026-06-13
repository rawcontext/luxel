public protocol RecordingDiagnosticClient: Sendable {
    func recordCorruptRecording(_ diagnostic: CorruptRecordingDiagnostic)
}

public struct NoopRecordingDiagnosticClient: RecordingDiagnosticClient {
    public init() {}

    public func recordCorruptRecording(_ diagnostic: CorruptRecordingDiagnostic) {}
}
