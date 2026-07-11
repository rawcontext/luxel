import Foundation

public enum SystemPermission: Codable, Equatable, Sendable {
    case screenRecording
    case microphone
    case camera
    case inputMonitoring
}

public enum PermissionStatus: Codable, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unknown
}

public protocol PermissionClient: Sendable {
    func status(for permission: SystemPermission) async -> PermissionStatus
    func request(_ permission: SystemPermission) async -> PermissionStatus
    func openSettings(for permission: SystemPermission) async
}
