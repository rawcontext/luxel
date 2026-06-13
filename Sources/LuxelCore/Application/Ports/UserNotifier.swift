import Foundation

public protocol UserNotifier: Sendable {
    func notifyExportCompleted(fileURL: URL, presetName: String) async throws
}
