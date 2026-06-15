enum EditorGIFLoopModeKind: String, CaseIterable, Equatable, Hashable {
    case forever
    case none
    case count
    case bounce

    var label: String {
        switch self {
        case .forever:
            "Forever"
        case .none:
            "Off"
        case .count:
            "Count"
        case .bounce:
            "Bounce"
        }
    }
}
