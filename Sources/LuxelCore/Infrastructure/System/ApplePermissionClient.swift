import AppKit
import AVFoundation
import CoreGraphics
import Foundation

public struct ApplePermissionClient: PermissionClient {
    public init() {}

    public func status(for permission: SystemPermission) async -> PermissionStatus {
        switch permission {
        case .screenRecording:
            CGPreflightScreenCaptureAccess() ? PermissionStatus.authorized : PermissionStatus.denied
        case .microphone:
            AVCaptureDevice.authorizationStatus(for: .audio).permissionStatus
        }
    }

    public func request(_ permission: SystemPermission) async -> PermissionStatus {
        switch permission {
        case .screenRecording:
            return CGRequestScreenCaptureAccess() ? PermissionStatus.authorized : PermissionStatus.denied
        case .microphone:
            if await AVCaptureDevice.requestAccess(for: .audio) {
                return .authorized
            }

            return await status(for: .microphone)
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
        }
    }
}
