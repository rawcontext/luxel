public protocol RecordingTerminationProtection: Sendable {
    func recordingWillStart()
    func recordingDidEnd()
}

public struct NoopRecordingTerminationProtection: RecordingTerminationProtection {
    public init() {}

    public func recordingWillStart() {}

    public func recordingDidEnd() {}
}
