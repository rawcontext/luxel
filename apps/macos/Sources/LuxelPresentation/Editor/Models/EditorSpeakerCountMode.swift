enum EditorSpeakerCountMode: String, CaseIterable, Equatable, Hashable {
    case automatic
    case exact
    case range

    var label: String {
        switch self {
        case .automatic:
            "Auto"
        case .exact:
            "Exact"
        case .range:
            "Range"
        }
    }
}
