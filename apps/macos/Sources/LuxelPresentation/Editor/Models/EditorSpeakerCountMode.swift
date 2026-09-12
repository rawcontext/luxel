import LuxelCore

enum EditorSpeakerCountMode: String, CaseIterable, Equatable, Hashable {
    case automatic
    case exact
    case range

    var label: String {
        switch self {
        case .automatic:
            LuxelLocalization.string("Auto")
        case .exact:
            LuxelLocalization.string("Exact")
        case .range:
            LuxelLocalization.string("Range")
        }
    }
}
