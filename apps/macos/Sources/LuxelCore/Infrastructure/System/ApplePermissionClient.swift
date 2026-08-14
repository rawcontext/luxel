import AVFAudio
import AVFoundation
import AppKit
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
        case .inputMonitoring:
            return CGPreflightListenEventAccess() ? .authorized : .notDetermined
        }
    }

    public func request(_ permission: SystemPermission) async -> PermissionStatus {
        switch permission {
        case .screenRecording:
            return CGRequestScreenCaptureAccess() ? .authorized : .denied
        case .microphone:
            return await AVAudioApplication.requestRecordPermission()
                ? .authorized
                : await status(for: .microphone)
        case .camera:
            return await AVCaptureDevice.requestAccess(for: .video)
                ? .authorized
                : await status(for: .camera)
        case .inputMonitoring:
            return CGRequestListenEventAccess() ? .authorized : .denied
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

extension AVAudioApplication.recordPermission {
    fileprivate var permissionStatus: PermissionStatus {
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

extension AVAuthorizationStatus {
    fileprivate var permissionStatus: PermissionStatus {
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

extension SystemPermission {
    fileprivate var systemSettingsURLString: String {
        switch self {
        case .screenRecording:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .microphone:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .camera:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        case .inputMonitoring:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }
    }
}
