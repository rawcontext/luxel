import AVFAudio
import AVFoundation
import AppKit
import Foundation
import ScreenCaptureKit

public protocol ScreenCapturePermissionChecking: Sendable {
    func hasScreenCaptureAccess() async -> Bool
}

public struct ScreenCaptureKitPermissionChecker: ScreenCapturePermissionChecking {
    public init() {}

    public func hasScreenCaptureAccess() async -> Bool {
        do {
            _ = try await SCShareableContent.current
            return true
        } catch {
            return false
        }
    }
}

public struct ApplePermissionClient: PermissionClient {
    private let screenCapturePermissionChecker: any ScreenCapturePermissionChecking

    public init(
        screenCapturePermissionChecker: any ScreenCapturePermissionChecking =
            ScreenCaptureKitPermissionChecker()
    ) {
        self.screenCapturePermissionChecker = screenCapturePermissionChecker
    }

    public func status(for permission: SystemPermission) async -> PermissionStatus {
        switch permission {
        case .screenRecording:
            return await screenCapturePermissionChecker.hasScreenCaptureAccess()
                ? .authorized
                : .notDetermined
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
        }
    }
}
