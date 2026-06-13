import AppKit
import AVFAudio
import CoreGraphics
import Foundation
import ScreenCaptureKit

public struct ApplePermissionClient: PermissionClient {
    public init() {}

    public func status(for permission: SystemPermission) async -> PermissionStatus {
        switch permission {
        case .screenRecording:
            if CGPreflightScreenCaptureAccess() {
                return .authorized
            }

            return await screenCaptureKitStatus()
        case .microphone:
            return AVAudioApplication.shared.recordPermission.permissionStatus
        }
    }

    public func request(_ permission: SystemPermission) async -> PermissionStatus {
        switch permission {
        case .screenRecording:
            return CGRequestScreenCaptureAccess() ? PermissionStatus.authorized : PermissionStatus.denied
        case .microphone:
            if await AVAudioApplication.requestRecordPermission() {
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

    private func screenCaptureKitStatus() async -> PermissionStatus {
        do {
            _ = try await SCShareableContent.current
            return .authorized
        } catch {
            return .denied
        }
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
