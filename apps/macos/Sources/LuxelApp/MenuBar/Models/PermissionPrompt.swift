import LuxelCore

struct PermissionPrompt: Equatable {
    let source: CapturePermissionSource?
    let permission: SystemPermission
    let guidance: PermissionGuidance
}
