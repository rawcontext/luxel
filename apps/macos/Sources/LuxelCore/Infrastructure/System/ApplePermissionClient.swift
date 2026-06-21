import AppKit
import AVFoundation
import AVFAudio
import CoreGraphics
import Foundation

public struct ApplePermissionClient: PermissionClient {
    public init() {}

    public func status(for permission: SystemPermission) async -> PermissionStatus {
        switch permission {
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .authorized : .notDetermined
        case .microphone:
            return AVAudioApplication.shared.recordPermission.permissionStatus
        case .camera:
            return AVCaptureDevice.authorizationStatus(for: .video).permissionStatus
        }
    }

    public func request(_ permission: SystemPermission) async -> PermissionStatus {
        switch permission {
        case .screenRecording:
            return await status(for: .screenRecording)
        case .microphone:
            if await AVAudioApplication.requestRecordPermission() {
                return .authorized
            }

            return await status(for: .microphone)
        case .camera:
            if await AVCaptureDevice.requestAccess(for: .video) {
                return .authorized
            }

            return await status(for: .camera)
        }
    }

    @MainActor
    public func openSettings(for permission: SystemPermission) async {
        guard let url = URL(string: permission.systemSettingsURLString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private extension AVAudioApplication.recordPermission {
    var permissionStatus: PermissionStatus {
        switch self {
        case .undetermined:
            .notDetermined
        case .denied:
            .denied
        case .granted:
            .authorized
        @unknown default:
            .unknown
        }
    }
}

private extension AVAuthorizationStatus {
    var permissionStatus: PermissionStatus {
        switch self {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .authorized:
            .authorized
        @unknown default:
            .unknown
        }
    }
}

private extension SystemPermission {
    var systemSettingsURLString: String {
        switch self {
        case .screenRecording:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .microphone:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .camera:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        }
    }
}
