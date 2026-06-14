public protocol NotchPresenter: Sendable {
    var interactions: AsyncStream<NotchInteraction> { get }

    func acquire(on geometry: NotchGeometry) async
    func present(_ update: NotchPresentationUpdate) async
    func setExpanded(_ isExpanded: Bool) async
    func release() async
}

public enum NotchInteraction: Equatable, Sendable {
    case hoverEntered
    case hoverExited
    case setExpanded(Bool)
    case action(NotchActivityActionID)
    case dragArtifact(NotchArtifact)
}

public struct NotchPresentationUpdate: Equatable, Sendable {
    public let geometry: NotchGeometry
    public let activity: NotchActivity
    public let presentationState: NotchPresentationState
    public let viewModel: NotchActivityViewModel
    public let motion: NotchMotion

    public init(
        geometry: NotchGeometry,
        activity: NotchActivity,
        presentationState: NotchPresentationState,
        viewModel: NotchActivityViewModel,
        motion: NotchMotion
    ) {
        self.geometry = geometry
        self.activity = activity
        self.presentationState = presentationState
        self.viewModel = viewModel
        self.motion = motion
    }
}
