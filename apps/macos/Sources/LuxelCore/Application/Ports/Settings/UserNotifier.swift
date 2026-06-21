import Foundation

public protocol UserNotifier: Sendable {
    func notifyExportCompleted(fileURL: URL, presetName: String) async throws
    func notifyRecordingAutoStopped(duration: TimeInterval) async throws
}

extension UserNotifier {
    public func notifyRecordingAutoStopped(duration: TimeInterval) async throws {}
}
