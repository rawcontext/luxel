import Foundation

public protocol UserNotifier: Sendable {
    func notifyExportCompleted(fileURL: URL, presetName: String) async throws
    func notifyRecordingAutoStopped(duration: TimeInterval) async throws
}

public extension UserNotifier {
    func notifyRecordingAutoStopped(duration: TimeInterval) async throws {}
}
