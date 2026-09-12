import LuxelCore

enum EditorGIFLoopModeKind: String, CaseIterable, Equatable, Hashable {
    case forever
    case none
    case count
    case bounce

    var label: String {
        switch self {
        case .forever:
            LuxelLocalization.string("Forever")
        case .none:
            LuxelLocalization.string("Off")
        case .count:
            LuxelLocalization.string("Count")
        case .bounce:
            LuxelLocalization.string("Bounce")
        }
    }
}
