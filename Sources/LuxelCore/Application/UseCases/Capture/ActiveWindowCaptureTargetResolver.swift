public struct ActiveWindowCaptureTargetResolver: Sendable {
    public init() {}

    public func resolve(
        from targets: [CaptureTargetOption],
        orderedWindowIDs: [UInt32]
    ) -> CaptureTargetOption? {
        let windowTargets = targets.reduce(into: [UInt32: CaptureTargetOption]()) { result, target in
            guard case .window(let id) = target.target, result[id] == nil else {
                return
            }

            result[id] = target
        }

        for windowID in orderedWindowIDs {
            if let target = windowTargets[windowID] {
                return target
            }
        }

        return nil
    }
}
