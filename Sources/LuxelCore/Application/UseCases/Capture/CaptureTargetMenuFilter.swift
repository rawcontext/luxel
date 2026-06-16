public struct CaptureTargetMenuFilter: Sendable {
    private let hiddenWindowTitles: Set<String>

    public init() {
        self.init(hiddenWindowTitles: Self.defaultHiddenWindowTitles)
    }

    public init(hiddenWindowTitles: Set<String>) {
        self.hiddenWindowTitles = hiddenWindowTitles
    }

    public func visibleTargets(from targets: [CaptureTargetOption]) -> [CaptureTargetOption] {
        targets.filter { target in
            target.kind != .window || !hiddenWindowTitles.contains(target.title)
        }
    }

    private static let defaultHiddenWindowTitles: Set<String> = [
        "App Icon Window",
        "Gesture Blocking Overlay"
    ]
}
