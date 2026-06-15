import LuxelCore

@MainActor
final class RecordingFramePanelController {
    func present(
        for _: RecordingRequest,
        availableTargets _: [CaptureTargetOption],
        exclusionRegistry _: CaptureExclusionRegistry
    ) async {}

    func close() async {}
}
