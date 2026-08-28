public struct FullscreenCaptureTargetResolver: Sendable {
    public init() {}

    public func resolve(
        from targets: [CaptureTargetOption],
        pointerDisplayID: DisplayID?,
        selectedTargetID: String?
    ) -> CaptureTargetOption? {
        if let pointerDisplayID,
            let pointerTarget = displayTarget(from: targets, matching: pointerDisplayID) {
            return pointerTarget
        }

        if let selectedTargetID,
            let selectedTarget = targets.first(where: { $0.id == selectedTargetID }),
            case .display = selectedTarget.target {
            return selectedTarget
        }

        return targets.first { target in
            if case .display = target.target {
                return true
            }

            return false
        }
    }

    private func displayTarget(
        from targets: [CaptureTargetOption],
        matching displayID: DisplayID
    ) -> CaptureTargetOption? {
        targets.first { target in
            if case .display(let targetDisplayID) = target.target {
                return targetDisplayID == displayID
            }

            return false
        }
    }
}
